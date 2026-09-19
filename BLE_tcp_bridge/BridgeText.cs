using System;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Resources;

namespace BLE_tcp_driver
{
    /// <summary>UI text only; language never changes wire data or diagnostic IDs.</summary>
    internal static class BridgeText
    {
        private static readonly ResourceManager English = Manager("en");
        private static ResourceManager selected = English;
        internal static string Language { get; private set; } = "en";

        private static ResourceManager Manager(string language) =>
            new ResourceManager("BLE_tcp_driver.Messages." + language, typeof(BridgeText).Assembly);

        internal static string Normalize(string language)
        {
            string code = (language ?? "").Trim().ToLowerInvariant().Split('-', '_')[0];
            return code == "ru" || code == "zh" ? code : "en";
        }

        internal static void Initialize(string[] arguments, string preferencesPath, string systemLanguage)
        {
            string explicitLanguage = arguments.FirstOrDefault(arg =>
                arg.StartsWith("--language=", StringComparison.OrdinalIgnoreCase));
            string language = explicitLanguage == null ? null : explicitLanguage.Substring(11);
            if (string.IsNullOrWhiteSpace(language))
            {
                try
                {
                    if (File.Exists(preferencesPath))
                        foreach (string line in File.ReadLines(preferencesPath))
                        {
                            string entry = line.Trim();
                            if (entry.StartsWith("#") || entry.StartsWith("!")) continue;
                            int delimiter = entry.IndexOfAny(new[] { '=', ':' });
                            if (delimiter > 0 && entry.Substring(0, delimiter).Trim() == "AhaKeySelectedLanguage")
                                language = entry.Substring(delimiter + 1).Trim();
                        }
                }
                catch (IOException) { }
                catch (UnauthorizedAccessException) { }
            }
            Language = Normalize(string.IsNullOrWhiteSpace(language) ? systemLanguage : language);
            selected = Manager(Language);
        }

        internal static string T(string key, params object[] arguments)
        {
            string template = selected.GetString(key, CultureInfo.InvariantCulture)
                ?? English.GetString(key, CultureInfo.InvariantCulture);
            if (template == null) throw new InvalidOperationException("Missing bridge translation: " + key);
            return arguments.Length == 0 ? template
                : string.Format(CultureInfo.GetCultureInfo(Language), template, arguments);
        }
    }
}
