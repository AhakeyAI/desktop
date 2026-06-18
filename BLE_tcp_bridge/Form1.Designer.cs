namespace BLE_tcp_driver
{
    partial class Form1
    {
        /// <summary>
        /// 必需的设计器变量。
        /// </summary>
        private System.ComponentModel.IContainer components = null;

        /// <summary>
        /// 清理所有正在使用的资源。
        /// </summary>
        /// <param name="disposing">如果应释放托管资源，为 true；否则为 false。</param>
        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null))
            {
                components.Dispose();
            }
            base.Dispose(disposing);
        }

        #region Windows 窗体设计器生成的代码

        /// <summary>
        /// 设计器支持所需的方法 - 不要修改
        /// 使用代码编辑器修改此方法的内容。
        /// </summary>
        private void InitializeComponent()
        {
            this.components = new System.ComponentModel.Container();
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(Form1));
            this.DeviceSelect = new System.Windows.Forms.ComboBox();
            this.BtnConnect = new System.Windows.Forms.Button();
            this.rtbMsg = new System.Windows.Forms.RichTextBox();
            this.label_connected_devices = new System.Windows.Forms.Label();
            this.label_ip_port = new System.Windows.Forms.Label();
            this.checkBox_start_mode = new System.Windows.Forms.CheckBox();
            this.notifyIcon1 = new System.Windows.Forms.NotifyIcon(this.components);
            this.trayContextMenu = new System.Windows.Forms.ContextMenuStrip(this.components);
            this.tsmiExit = new System.Windows.Forms.ToolStripMenuItem();
            this.button1 = new System.Windows.Forms.Button();
            this.checkBox_follow_system = new System.Windows.Forms.CheckBox();
            this.trayContextMenu.SuspendLayout();
            this.SuspendLayout();
            // 
            // DeviceSelect
            // 
            this.DeviceSelect.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            this.DeviceSelect.FormattingEnabled = true;
            this.DeviceSelect.Location = new System.Drawing.Point(147, 51);
            this.DeviceSelect.Name = "DeviceSelect";
            this.DeviceSelect.Size = new System.Drawing.Size(121, 20);
            this.DeviceSelect.TabIndex = 4;
            // 
            // BtnConnect
            // 
            this.BtnConnect.Location = new System.Drawing.Point(274, 51);
            this.BtnConnect.Name = "BtnConnect";
            this.BtnConnect.Size = new System.Drawing.Size(75, 23);
            this.BtnConnect.TabIndex = 5;
            this.BtnConnect.Text = "连接";
            this.BtnConnect.UseVisualStyleBackColor = true;
            this.BtnConnect.Click += new System.EventHandler(this.BtnConnect_Click);
            // 
            // rtbMsg
            // 
            this.rtbMsg.Font = new System.Drawing.Font("微软雅黑", 12F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(134)));
            this.rtbMsg.Location = new System.Drawing.Point(0, 116);
            this.rtbMsg.Name = "rtbMsg";
            this.rtbMsg.ReadOnly = true;
            this.rtbMsg.ScrollBars = System.Windows.Forms.RichTextBoxScrollBars.Vertical;
            this.rtbMsg.ShortcutsEnabled = false;
            this.rtbMsg.Size = new System.Drawing.Size(816, 465);
            this.rtbMsg.TabIndex = 6;
            this.rtbMsg.Text = "";
            this.rtbMsg.KeyDown += new System.Windows.Forms.KeyEventHandler(this.rtbMsg_KeyDown);
            // 
            // label_connected_devices
            // 
            this.label_connected_devices.AutoSize = true;
            this.label_connected_devices.Location = new System.Drawing.Point(410, 26);
            this.label_connected_devices.Name = "label_connected_devices";
            this.label_connected_devices.Size = new System.Drawing.Size(95, 12);
            this.label_connected_devices.TabIndex = 7;
            this.label_connected_devices.Text = "当前连接设备:无";
            // 
            // label_ip_port
            // 
            this.label_ip_port.AutoSize = true;
            this.label_ip_port.Location = new System.Drawing.Point(410, 54);
            this.label_ip_port.Name = "label_ip_port";
            this.label_ip_port.Size = new System.Drawing.Size(131, 12);
            this.label_ip_port.TabIndex = 8;
            this.label_ip_port.Text = "当前服务器地址及端口:";
            // 
            // checkBox_start_mode
            // 
            this.checkBox_start_mode.AutoSize = true;
            this.checkBox_start_mode.Location = new System.Drawing.Point(412, 81);
            this.checkBox_start_mode.Name = "checkBox_start_mode";
            this.checkBox_start_mode.Size = new System.Drawing.Size(108, 16);
            this.checkBox_start_mode.TabIndex = 9;
            this.checkBox_start_mode.Text = "下次最小化启动";
            this.checkBox_start_mode.UseVisualStyleBackColor = true;
            // 
            // notifyIcon1
            // 
            this.notifyIcon1.ContextMenuStrip = this.trayContextMenu;
            this.notifyIcon1.Icon = ((System.Drawing.Icon)(resources.GetObject("notifyIcon1.Icon")));
            this.notifyIcon1.Text = "BLE TCP Bridge";
            this.notifyIcon1.Visible = true;
            this.notifyIcon1.MouseClick += new System.Windows.Forms.MouseEventHandler(this.notifyIcon1_MouseClick);
            // 
            // trayContextMenu
            // 
            this.trayContextMenu.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.tsmiExit});
            this.trayContextMenu.Name = "trayContextMenu";
            this.trayContextMenu.Size = new System.Drawing.Size(125, 26);
            // 
            // tsmiExit
            // 
            this.tsmiExit.Name = "tsmiExit";
            this.tsmiExit.Size = new System.Drawing.Size(124, 22);
            this.tsmiExit.Text = "退出程序";
            this.tsmiExit.Click += new System.EventHandler(this.tsmiExit_Click);
            // 
            // button1
            // 
            this.button1.Location = new System.Drawing.Point(725, 0);
            this.button1.Name = "button1";
            this.button1.Size = new System.Drawing.Size(75, 23);
            this.button1.TabIndex = 10;
            this.button1.Text = "退出程序";
            this.button1.UseVisualStyleBackColor = true;
            this.button1.Click += new System.EventHandler(this.button1_Click);
            // 
            // checkBox_follow_system
            // 
            this.checkBox_follow_system.AutoSize = true;
            this.checkBox_follow_system.Location = new System.Drawing.Point(552, 81);
            this.checkBox_follow_system.Name = "checkBox_follow_system";
            this.checkBox_follow_system.Size = new System.Drawing.Size(96, 16);
            this.checkBox_follow_system.TabIndex = 11;
            this.checkBox_follow_system.Text = "跟随系统启动";
            this.checkBox_follow_system.UseVisualStyleBackColor = true;
            this.checkBox_follow_system.CheckedChanged += new System.EventHandler(this.checkBox_follow_system_CheckedChanged);
            // 
            // Form1
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 12F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(800, 578);
            this.Controls.Add(this.checkBox_follow_system);
            this.Controls.Add(this.button1);
            this.Controls.Add(this.checkBox_start_mode);
            this.Controls.Add(this.label_ip_port);
            this.Controls.Add(this.label_connected_devices);
            this.Controls.Add(this.rtbMsg);
            this.Controls.Add(this.BtnConnect);
            this.Controls.Add(this.DeviceSelect);
            this.Name = "Form1";
            this.Text = "kjasdhbgvjkhreaubvuo";
            this.FormClosing += new System.Windows.Forms.FormClosingEventHandler(this.Form1_FormClosing);
            this.Load += new System.EventHandler(this.Form1_Load);
            this.Resize += new System.EventHandler(this.Form1_Resize);
            this.trayContextMenu.ResumeLayout(false);
            this.ResumeLayout(false);
            this.PerformLayout();

        }

        #endregion
        private System.Windows.Forms.ComboBox DeviceSelect;
        private System.Windows.Forms.Button BtnConnect;
        private System.Windows.Forms.RichTextBox rtbMsg;
        private System.Windows.Forms.Label label_connected_devices;
        private System.Windows.Forms.Label label_ip_port;
        private System.Windows.Forms.CheckBox checkBox_start_mode;
        private System.Windows.Forms.NotifyIcon notifyIcon1;
        private System.Windows.Forms.ContextMenuStrip trayContextMenu;
        private System.Windows.Forms.ToolStripMenuItem tsmiExit;
        private System.Windows.Forms.Button button1;
        private System.Windows.Forms.CheckBox checkBox_follow_system;
    }
}

