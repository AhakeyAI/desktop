using System;
using System.IO;
using System.Text;

namespace BLE_tcp_driver
{
    /// <summary>
    /// 驱动日志: 写入 %LOCALAPPDATA%\AhaKeyStudio\logs\ble-driver-yyyy-MM-dd.log
    /// 每行格式: yyyy-MM-dd HH:mm:ss.fff LEVEL message
    /// 线程安全, 永不抛出异常.
    /// </summary>
    static class DriverLog
    {
        public const string Info = "INFO";
        public const string Warn = "WARN";
        public const string Error = "ERROR";
        public const string Debug = "DEBUG";

        private static readonly object _lock = new object();
        private static readonly Encoding _utf8NoBom = new UTF8Encoding(false);
        private static string _directory;

        private static string LogDirectory
        {
            get
            {
                if (_directory == null)
                {
                    string baseDir = null;
                    try { baseDir = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData); } catch { }
                    if (string.IsNullOrEmpty(baseDir))
                    {
                        try { baseDir = Environment.GetEnvironmentVariable("LOCALAPPDATA"); } catch { }
                    }
                    if (string.IsNullOrEmpty(baseDir))
                    {
                        baseDir = AppDomain.CurrentDomain.BaseDirectory;
                    }
                    _directory = Path.Combine(Path.Combine(baseDir, "AhaKeyStudio"), "logs");
                }
                return _directory;
            }
        }

        public static void Write(string level, string message)
        {
            try
            {
                DateTime now = DateTime.Now;
                string text = message ?? "";
                text = text.Replace("\r\n", " | ").Replace("\n", " | ").Replace("\r", " | ");
                string line = now.ToString("yyyy-MM-dd HH:mm:ss.fff") + " " + (level ?? Info) + " " + text + "\r\n";
                lock (_lock)
                {
                    string dir = LogDirectory;
                    Directory.CreateDirectory(dir);
                    string path = Path.Combine(dir, "ble-driver-" + now.ToString("yyyy-MM-dd") + ".log");
                    using (var stream = new FileStream(path, FileMode.Append, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete))
                    using (var writer = new StreamWriter(stream, _utf8NoBom))
                    {
                        writer.Write(line);
                    }
                }
            }
            catch
            {
                // 日志失败不影响程序
            }
        }

        public static void LogInfo(string message) { Write(Info, message); }
        public static void LogWarn(string message) { Write(Warn, message); }
        public static void LogError(string message) { Write(Error, message); }
        public static void LogDebug(string message) { Write(Debug, message); }

        /// <summary>
        /// 把 Console 输出转到日志文件 (WinExe 下 Console 原本无处可去)
        /// </summary>
        public static void RedirectConsole()
        {
            try
            {
                Console.SetOut(TextWriter.Synchronized(new ConsoleLogWriter()));
            }
            catch { }
        }

        /// <summary>
        /// 按 Console 文字猜测级别 (匹配 BleCore 中现有的中文输出)
        /// </summary>
        public static string GuessLevel(string message)
        {
            if (string.IsNullOrEmpty(message)) return Info;
            if (message.StartsWith("发送数据", StringComparison.Ordinal))
                return message.EndsWith("Success", StringComparison.Ordinal) ? Debug : Warn;
            if (message.StartsWith("读取数据", StringComparison.Ordinal))
                return Debug;
            if (message.StartsWith("#", StringComparison.Ordinal))
                return Debug;
            if (message.IndexOf("失败", StringComparison.Ordinal) >= 0
                || message.IndexOf("异常", StringComparison.Ordinal) >= 0
                || message.IndexOf("没有发现设备", StringComparison.Ordinal) >= 0
                || message.IndexOf("Exception", StringComparison.Ordinal) >= 0
                || message == "ERROR"
                || message == "Error")
                return Error;
            if (message.IndexOf("设备已断开", StringComparison.Ordinal) >= 0
                || message.IndexOf("设备不可用", StringComparison.Ordinal) >= 0
                || message.IndexOf("当前没有", StringComparison.Ordinal) >= 0
                || message.IndexOf("Unreachable", StringComparison.Ordinal) >= 0
                || message == "Canceled")
                return Warn;
            return Info;
        }

        private sealed class ConsoleLogWriter : TextWriter
        {
            private readonly StringBuilder _buffer = new StringBuilder();

            public override Encoding Encoding { get { return _utf8NoBom; } }

            public override void Write(char value)
            {
                try
                {
                    if (value == '\n')
                    {
                        Flush();
                    }
                    else if (value != '\r')
                    {
                        _buffer.Append(value);
                    }
                }
                catch { }
            }

            public override void Write(string value)
            {
                if (value == null) return;
                for (int i = 0; i < value.Length; i++) Write(value[i]);
            }

            public override void WriteLine(string value)
            {
                Write(value);
                Flush();
            }

            public override void Flush()
            {
                try
                {
                    if (_buffer.Length == 0) return;
                    string line = _buffer.ToString();
                    _buffer.Clear();
                    string level = DriverLog.GuessLevel(line);
                    if (!line.StartsWith("[", StringComparison.Ordinal)) line = "[BLE] " + line;
                    DriverLog.Write(level, line);
                }
                catch { }
            }
        }
    }
}
