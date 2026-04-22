using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Text;
using System.Windows.Forms;
using Microsoft.Win32;
using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.GenericAttributeProfile;
using Windows.Devices.Enumeration;

namespace BLE_tcp_driver
{
    public partial class Form1 : Form
    {
        private static BleCore bleCore = new BleCore();
        private TcpServer tcpServer;
        private AppConfig config;
        private Timer retryTimer;
        private bool autoConnecting = false;
        private bool targetConfirmed = false;
        private bool _suppressInitialShow;
        private bool _loaded;
        List<DeviceInformation> devicesList = null;

        public Form1()
        {
            InitializeComponent();
            config = AppConfig.Load();
            bool launchMinimized = Environment.GetCommandLineArgs()
                .Any(arg => string.Equals(arg, "--minimized", StringComparison.OrdinalIgnoreCase));
            _suppressInitialShow = config.StartMinimized || launchMinimized;
        }

        protected override void SetVisibleCore(bool value)
        {
            if (_suppressInitialShow)
            {
                _suppressInitialShow = false;
                if (!IsHandleCreated) CreateHandle();
                if (!_loaded) Form1_Load(this, EventArgs.Empty);
                base.SetVisibleCore(false);
                return;
            }
            base.SetVisibleCore(value);
        }

        private void log(Color c, string message)
        {
            BeginInvoke(new Action(() =>
            {
                rtbMsg.SelectionColor = c;
                rtbMsg.AppendText(DateTime.Now.ToString("HH:mm:ss.fff") + "> ");
                rtbMsg.AppendText(message);
                rtbMsg.AppendText("\n");
                rtbMsg.SelectionStart = rtbMsg.Text.Length;
                rtbMsg.ScrollToCaret();
            }));
        }

        private void Form1_Load(object sender, EventArgs e)
        {
            if (_loaded) return;
            _loaded = true;

            this.Opacity = 0.8;

            // 同步checkbox
            checkBox_start_mode.Checked = config.StartMinimized;
            checkBox_start_mode.CheckedChanged += CheckBox_start_mode_CheckedChanged;

            // 同步开机自启动 checkbox（先摘除 Designer 绑定的事件，避免初始化时误写注册表）
            checkBox_follow_system.CheckedChanged -= checkBox_follow_system_CheckedChanged;
            checkBox_follow_system.Checked = IsAutoStartEnabled();
            checkBox_follow_system.CheckedChanged += checkBox_follow_system_CheckedChanged;

            // BLE事件
            bleCore.DeviceAdded += DeviceAdded;
            bleCore.ConnectDeviceSuccess += DeviceConnected;
            bleCore.DeviceDisconnected += DeviceDisconnected;
            bleCore.CharacteristicAdded += CharacteristicAdded;
            bleCore.ReceiveNotifyData += ReceiveNotifyData;
            //bleCore.WriteDataSuccess += WriteDataSuccess;
            bleCore.AllCharacteristicsDiscovered += OnAllCharacteristicsDiscovered;
            BindRichTextBoxContextMenu(rtbMsg);

            // 启动TCP服务器
            tcpServer = new TcpServer(bleCore, config.ServerPort);
            tcpServer.OnLog += (msg) => log(Color.DarkCyan, "[TCP] " + msg);
            tcpServer.OnClientCountChanged += (count) =>
            {
                BeginInvoke(new Action(() =>
                {
                    label_ip_port.Text = $"TCP服务: {TcpServer.GetLocalIPAddress()}:{config.ServerPort} (客户端:{count})";
                }));
            };
            tcpServer.Start();
            label_ip_port.Text = $"TCP服务: {TcpServer.GetLocalIPAddress()}:{config.ServerPort} (客户端:0)";

            // 重试定时器 (UI线程Timer)
            retryTimer = new Timer();
            retryTimer.Interval = 8000;
            retryTimer.Tick += RetryTimer_Tick;

            // 自动开始扫描
            devicesList = new List<DeviceInformation>();
            bleCore.StartBleDeviceWatcher();
            log(Color.Blue, "自动扫描蓝牙设备中...");

            if (config.HasSavedDevice)
            {
                log(Color.Blue, $"目标设备: {config.BleName} [{config.BleMac}]");
                retryTimer.Start();
            }
        }

        private void RetryTimer_Tick(object sender, EventArgs e)
        {
            // 已连接则跳过
            if (bleCore.CurrentDevice != null &&
                bleCore.CurrentDevice.ConnectionStatus == BluetoothConnectionStatus.Connected)
                return;

            autoConnecting = false;
            devicesList = new List<DeviceInformation>();
            DeviceSelect.Items.Clear();

            try { bleCore.StopBleDeviceWatcher(); } catch { }
            bleCore.StartBleDeviceWatcher();
            log(Color.Gray, "重新扫描蓝牙设备...");
        }

        private void WriteDataSuccess(GattCharacteristic sender, byte[] data)
        {
            UTF8Encoding utf8 = new UTF8Encoding();
            log(Color.FromArgb(0x00ff00FF), Utilities.ConvertUuidToShortId(sender.Uuid).ToString() + "write :" + utf8.GetString(data));
        }

        private void ReceiveNotifyData(GattCharacteristic sender, byte[] data)
        {
            if (ProtocolHelper.IsDeviceStatusNotification(data))
            {
                var info = ProtocolHelper.ParseDeviceStatusFromNotification(data);
                log(Color.DarkGreen, $"设备状态: 电量={info.BatteryLevel} 信号={info.SignalStrength} " +
                    $"固件={info.FirmwareVersionMain}.{info.FirmwareVersionSub} " +
                    $"模式={info.WorkMode} 灯光={info.LightMode} 开关={info.SwitchState}");
            }
            else
            {
                log(Color.FromArgb(0x00ff0000), Utilities.ConvertUuidToShortId(sender.Uuid).ToString() +
                    "receive :" + BitConverter.ToString(data));
            }
        }

        private void DeviceAdded(DeviceInformation deviceInformation)
        {
            BeginInvoke(new Action(() =>
            {
                if (string.IsNullOrEmpty(deviceInformation.Name)) return;

                DeviceSelect.Items.Add(deviceInformation.Name);
                devicesList.Add(deviceInformation);
                if (DeviceSelect.SelectedIndex == -1)
                    DeviceSelect.SelectedIndex = DeviceSelect.Items.Count - 1;

                // 自动连接: 匹配已保存的设备名称+MAC
                if (config.HasSavedDevice && !autoConnecting)
                {
                    string mac = GetMacFromDeviceInfo(deviceInformation);
                    if (deviceInformation.Name == config.BleName &&
                        string.Equals(mac, config.BleMac, StringComparison.OrdinalIgnoreCase))
                    {
                        autoConnecting = true;
                        log(Color.Blue, "发现目标设备, 自动连接...");
                        try { bleCore.StopBleDeviceWatcher(); } catch { }
                        bleCore.ConnectDeviceByInfo(deviceInformation);
                    }
                }
            }));
        }

        private void DeviceConnected(BluetoothLEDevice bluetoothLEDevice)
        {
            BeginInvoke(new Action(() =>
            {
                log(Color.FromArgb(0x00ff00FF), "Connected:" + bluetoothLEDevice.Name);
                label_connected_devices.Text = "当前连接设备:" + bluetoothLEDevice.Name;
                retryTimer.Stop();
                autoConnecting = false;
                targetConfirmed = false;
            }));
        }

        private void DeviceDisconnected(BluetoothLEDevice bluetoothLEDevice)
        {
            BeginInvoke(new Action(() =>
            {
                log(Color.Red, "Disconnected:" + (bluetoothLEDevice?.Name ?? ""));
                label_connected_devices.Text = "当前连接设备:无";
                autoConnecting = false;

                if (config.HasSavedDevice)
                {
                    log(Color.Gray, "将在数秒后尝试重连...");
                    retryTimer.Start();
                }
            }));
        }

        private void CharacteristicAdded(GattCharacteristic gattCharacteristic)
        {
            BeginInvoke(new Action(() =>
            {
                ushort shortId = Utilities.ConvertUuidToShortId(gattCharacteristic.Uuid);
                log(Color.Black, "Chara:0x" + shortId.ToString("X") +
                    ", des:" + gattCharacteristic.UserDescription);

                if (shortId == 0x7341)
                {
                    bleCore.CurrentDataCharacteristic = gattCharacteristic;
                    log(Color.Green, "  → 数据特征(0x7341)已就绪");
                }
                if (shortId == 0x7343)
                {
                    bleCore.CurrentWriteCharacteristic = gattCharacteristic;
                    log(Color.Green, "  → 命令特征(0x7343)已就绪");
                }
                if (shortId == 0x7344)
                {
                    bleCore.CurrentNotifyCharacteristic = gattCharacteristic;
                    bleCore.EnableNotifications(gattCharacteristic);
                    log(Color.Green, "  → 通知特征(0x7344)已就绪");
                }

                // 所有目标特征就绪 → 确认为目标设备, 保存配置 (仅触发一次)
                if (!targetConfirmed
                    && bleCore.CurrentDataCharacteristic != null
                    && bleCore.CurrentWriteCharacteristic != null
                    && bleCore.CurrentNotifyCharacteristic != null)
                {
                    targetConfirmed = true;
                    log(Color.Blue, "目标设备已确认, 所有特征就绪");
                    SaveCurrentDeviceToConfig();

                    // 自动向命令特征写入设备状态查询指令
                    bleCore.WriteDataToCharacterstuc(
                        bleCore.CurrentWriteCharacteristic,
                        ProtocolHelper.DeviceStatusQueryCommand);
                    log(Color.Blue, "已发送设备状态查询指令");

                    if (ProtocolHelper.LastClaudeState !=  null)
                    {
                        bleCore.WriteDataToCharacterstuc(
                            bleCore.CurrentWriteCharacteristic,
                            ProtocolHelper.LastClaudeState);
                        log(Color.Blue, "已发送设置claude状态指令");
                    }
                }
            }));
        }

        /// <summary>
        /// 所有服务的特征发现完毕后, 检查是否找齐目标UUID
        /// </summary>
        private void OnAllCharacteristicsDiscovered()
        {
            BeginInvoke(new Action(() =>
            {
                if (targetConfirmed) return; // 已确认, 无需处理

                bool allFound = bleCore.CurrentDataCharacteristic != null
                             && bleCore.CurrentWriteCharacteristic != null
                             && bleCore.CurrentNotifyCharacteristic != null;

                if (!allFound)
                {
                    string devName = bleCore.CurrentDevice?.Name ?? "未知";
                    log(Color.OrangeRed, $"设备 [{devName}] 未找齐目标UUID, 断开连接");
                    bleCore.Dispose();
                    label_connected_devices.Text = "当前连接设备:无";

                    if (config.HasSavedDevice)
                    {
                        log(Color.Gray, "将继续尝试查找目标设备...");
                        retryTimer.Start();
                    }
                }
            }));
        }

        /// <summary>
        /// 保存当前连接的蓝牙设备信息到配置文件
        /// </summary>
        private void SaveCurrentDeviceToConfig()
        {
            if (bleCore.CurrentDevice == null) return;

            byte[] macBytes = BitConverter.GetBytes(bleCore.CurrentDevice.BluetoothAddress);
            Array.Reverse(macBytes);
            string mac = BitConverter.ToString(macBytes, 2, 6).Replace('-', ':');

            config.BleName = bleCore.CurrentDevice.Name;
            config.BleMac = mac;
            config.Save();
            log(Color.Blue, $"已保存设备: {config.BleName} [{config.BleMac}]");
        }

        private void BtnConnect_Click(object sender, EventArgs e)
        {
            if (DeviceSelect.SelectedIndex >= 0 && DeviceSelect.SelectedIndex < devicesList.Count)
                bleCore.ConnectDeviceByInfo(devicesList[DeviceSelect.SelectedIndex]);
        }

        private void CheckBox_start_mode_CheckedChanged(object sender, EventArgs e)
        {
            config.StartMinimized = checkBox_start_mode.Checked;
            config.Save();
        }

        /// <summary>
        /// 从DeviceInformation中提取蓝牙MAC地址
        /// </summary>
        private static string GetMacFromDeviceInfo(DeviceInformation devInfo)
        {
            try
            {
                if (devInfo.Properties.ContainsKey("System.Devices.Aep.DeviceAddress"))
                {
                    var value = devInfo.Properties["System.Devices.Aep.DeviceAddress"];
                    if (value != null)
                    {
                        string addr = value.ToString().ToUpper().Replace("-", "");
                        // 无冒号的12位hex → 插入冒号
                        if (addr.Length == 12 && !addr.Contains(":"))
                            addr = string.Join(":", Enumerable.Range(0, 6).Select(i => addr.Substring(i * 2, 2)));
                        return addr;
                    }
                }
            }
            catch { }
            return "";
        }

        private void BindRichTextBoxContextMenu(RichTextBox textBox)
        {
            ContextMenu contextMenu = new ContextMenu();

            System.Windows.Forms.MenuItem cutItem = new System.Windows.Forms.MenuItem("剪切");
            cutItem.Click += (sender, eventArgs) => textBox.Cut();

            System.Windows.Forms.MenuItem copyItem = new System.Windows.Forms.MenuItem("复制");
            copyItem.Click += (sender, eventArgs) => textBox.Copy();

            System.Windows.Forms.MenuItem pasteItem = new System.Windows.Forms.MenuItem("粘贴");
            pasteItem.Click += (sender, eventArgs) => textBox.Paste();

            contextMenu.MenuItems.Add(cutItem);
            contextMenu.MenuItems.Add(copyItem);
            contextMenu.MenuItems.Add(pasteItem);
            textBox.ContextMenu = contextMenu;
        }

        private void rtbMsg_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyValue > 0)
            {
                rtbMsg.Copy();
            }
        }

        /// <summary>
        /// 最小化时隐藏到系统托盘
        /// </summary>
        private void Form1_Resize(object sender, EventArgs e)
        {
            if (this.WindowState == FormWindowState.Minimized)
            {
                this.Hide();
            }
        }

        /// <summary>
        /// 点击托盘图标恢复窗口
        /// </summary>
        private void notifyIcon1_MouseClick(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left)
            {
                this.Show();
                this.WindowState = FormWindowState.Normal;
                this.Activate();
            }
        }

        /// <summary>
        /// 托盘右键菜单 - 退出程序
        /// </summary>
        private void tsmiExit_Click(object sender, EventArgs e)
        {
            notifyIcon1.Visible = false;
            Application.Exit();
        }

        /// <summary>
        /// 关闭窗口时最小化到托盘而不是退出
        /// </summary>
        private void Form1_FormClosing(object sender, FormClosingEventArgs e)
        {
            if (e.CloseReason == CloseReason.UserClosing)
            {
                e.Cancel = true;
                this.WindowState = FormWindowState.Minimized;
            }
        }

        private void button1_Click(object sender, EventArgs e)
        {
            Application.Exit();
        }

        private void checkBox_follow_system_CheckedChanged(object sender, EventArgs e)
        {
            try
            {
                SetAutoStart(checkBox_follow_system.Checked);
            }
            catch (Exception ex)
            {
                MessageBox.Show("设置开机自启动失败: " + ex.Message, "错误", MessageBoxButtons.OK, MessageBoxIcon.Error);
                // 还原 checkbox 状态
                checkBox_follow_system.CheckedChanged -= checkBox_follow_system_CheckedChanged;
                checkBox_follow_system.Checked = !checkBox_follow_system.Checked;
                checkBox_follow_system.CheckedChanged += checkBox_follow_system_CheckedChanged;
            }
        }

        private const string AutoStartKeyName = "BLE_tcp_driver";

        private bool IsAutoStartEnabled()
        {
            using (var key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Run", false))
            {
                return key?.GetValue(AutoStartKeyName) != null;
            }
        }

        private void SetAutoStart(bool enable)
        {
            using (var key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Run", true))
            {
                if (enable)
                    key.SetValue(AutoStartKeyName, Application.ExecutablePath);
                else
                    key.DeleteValue(AutoStartKeyName, false);
            }
        }
    }
}
