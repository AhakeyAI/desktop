using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

namespace BLE_tcp_driver
{
    class AppConfig
    {
        public string BleName { get; set; } = "";
        public string BleMac { get; set; } = "";
        public string ServerIP { get; set; } = "0.0.0.0";
        public int ServerPort { get; set; } = 9000;
        public bool StartMinimized { get; set; } = false;

        public bool HasSavedDevice => !string.IsNullOrEmpty(BleName) && !string.IsNullOrEmpty(BleMac);

        private static readonly string ConfigPath = Path.Combine(
            Path.GetDirectoryName(Application.ExecutablePath), "config_server.json");

        public static AppConfig Load()
        {
            if (!File.Exists(ConfigPath))
                return CreateDefault();

            try
            {
                string json = File.ReadAllText(ConfigPath, Encoding.UTF8);
                var config = new AppConfig();
                config.BleName = JsonExtractString(json, "BleName");
                config.BleMac = JsonExtractString(json, "BleMac");
                config.ServerIP = JsonExtractString(json, "ServerIP");
                if (string.IsNullOrEmpty(config.ServerIP)) config.ServerIP = "0.0.0.0";
                config.ServerPort = JsonExtractInt(json, "ServerPort", 9000);
                config.StartMinimized = JsonExtractBool(json, "StartMinimized", false);
                return config;
            }
            catch (Exception ex)
            {
                Console.WriteLine("配置文件读取失败: " + ex.Message);
                return CreateDefault();
            }
        }

        public void Save()
        {
            try
            {
                var sb = new StringBuilder();
                sb.AppendLine("{");
                sb.AppendLine($"  \"BleName\": \"{JsonEscape(BleName)}\",");
                sb.AppendLine($"  \"BleMac\": \"{JsonEscape(BleMac)}\",");
                sb.AppendLine($"  \"ServerIP\": \"{JsonEscape(ServerIP)}\",");
                sb.AppendLine($"  \"ServerPort\": {ServerPort},");
                sb.AppendLine($"  \"StartMinimized\": {(StartMinimized ? "true" : "false")}");
                sb.AppendLine("}");
                File.WriteAllText(ConfigPath, sb.ToString(), Encoding.UTF8);
            }
            catch (Exception ex)
            {
                Console.WriteLine("配置文件保存失败: " + ex.Message);
            }
        }

        private static AppConfig CreateDefault()
        {
            var config = new AppConfig();
            config.Save();
            return config;
        }

        #region JSON工具方法 (无外部依赖)

        private static string JsonExtractString(string json, string key)
        {
            var match = Regex.Match(json, "\"" + Regex.Escape(key) + "\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
            return match.Success ? JsonUnescape(match.Groups[1].Value) : "";
        }

        private static int JsonExtractInt(string json, string key, int defaultValue)
        {
            var match = Regex.Match(json, "\"" + Regex.Escape(key) + "\"\\s*:\\s*(\\d+)");
            return match.Success && int.TryParse(match.Groups[1].Value, out int val) ? val : defaultValue;
        }

        private static bool JsonExtractBool(string json, string key, bool defaultValue)
        {
            var match = Regex.Match(json, "\"" + Regex.Escape(key) + "\"\\s*:\\s*(true|false)");
            return match.Success ? match.Groups[1].Value == "true" : defaultValue;
        }

        /// <summary>
        /// JSON字符串转义 (非ASCII字符使用\uXXXX编码)
        /// </summary>
        private static string JsonEscape(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            var sb = new StringBuilder(s.Length);
            foreach (char c in s)
            {
                switch (c)
                {
                    case '"': sb.Append("\\\""); break;
                    case '\\': sb.Append("\\\\"); break;
                    case '\b': sb.Append("\\b"); break;
                    case '\f': sb.Append("\\f"); break;
                    case '\n': sb.Append("\\n"); break;
                    case '\r': sb.Append("\\r"); break;
                    case '\t': sb.Append("\\t"); break;
                    default:
                        if (c < 0x20 || c > 0x7E)
                            sb.AppendFormat("\\u{0:X4}", (int)c);
                        else
                            sb.Append(c);
                        break;
                }
            }
            return sb.ToString();
        }

        /// <summary>
        /// JSON字符串反转义
        /// </summary>
        private static string JsonUnescape(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            var sb = new StringBuilder(s.Length);
            for (int i = 0; i < s.Length; i++)
            {
                if (s[i] == '\\' && i + 1 < s.Length)
                {
                    char next = s[++i];
                    switch (next)
                    {
                        case '"': sb.Append('"'); break;
                        case '\\': sb.Append('\\'); break;
                        case '/': sb.Append('/'); break;
                        case 'b': sb.Append('\b'); break;
                        case 'f': sb.Append('\f'); break;
                        case 'n': sb.Append('\n'); break;
                        case 'r': sb.Append('\r'); break;
                        case 't': sb.Append('\t'); break;
                        case 'u':
                            if (i + 4 < s.Length)
                            {
                                sb.Append((char)Convert.ToInt32(s.Substring(i + 1, 4), 16));
                                i += 4;
                            }
                            break;
                        default: sb.Append('\\').Append(next); break;
                    }
                }
                else
                {
                    sb.Append(s[i]);
                }
            }
            return sb.ToString();
        }

        #endregion
    }
}
