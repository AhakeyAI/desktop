using System;
using System.Collections;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Resources;
using System.Text.RegularExpressions;

internal static class LocalizationTests
{
    private static Type text;
    private static object Call(string name, params object[] arguments) =>
        text.GetMethod(name, BindingFlags.Static | BindingFlags.NonPublic).Invoke(null, arguments);
    private static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
    }
    private static string T(string key, params object[] arguments) => (string)Call("T", key, arguments);

    [STAThread]
    private static int Main(string[] args)
    {
        string temp = Path.Combine(Path.GetTempPath(), "ahakey-locale-" + Guid.NewGuid());
        Directory.CreateDirectory(temp);
        string preferences = Path.Combine(temp, "preferences.properties");
        try
        {
            var assembly = Assembly.LoadFrom(Path.GetFullPath(args[0]));
            text = assembly.GetType("BLE_tcp_driver.BridgeText", true);
            var english = new ResourceManager("BLE_tcp_driver.Messages.en", assembly)
                .GetResourceSet(CultureInfo.InvariantCulture, true, false);
            var placeholders = new Regex(@"\{\d+(?:[^}]*)\}");
            foreach (string language in new[] { "en", "ru", "zh" })
            {
                var catalog = new ResourceManager("BLE_tcp_driver.Messages." + language, assembly)
                    .GetResourceSet(CultureInfo.InvariantCulture, true, false);
                Check(catalog.Cast<DictionaryEntry>().Count() == english.Cast<DictionaryEntry>().Count(), language + " key count");
                foreach (DictionaryEntry entry in english)
                {
                    string value = catalog.GetString((string)entry.Key);
                    Check(!string.IsNullOrWhiteSpace(value), language + ": " + entry.Key);
                    Check(placeholders.Matches((string)entry.Value).Cast<Match>().Select(m => m.Value)
                        .SequenceEqual(placeholders.Matches(value).Cast<Match>().Select(m => m.Value)), "Placeholders: " + entry.Key);
                    if (language == "ru") Check(!Regex.IsMatch(value, @"[\u4e00-\u9fff]"), "Untranslated: " + entry.Key);
                    string.Format(CultureInfo.InvariantCulture, value, Enumerable.Range(0, 10).Cast<object>().ToArray());
                }
            }
            File.WriteAllText(preferences, "# Java preferences\nother.setting=keep\nAhaKeySelectedLanguage=ru\n");
            Call("Initialize", new string[0], preferences, "zh-CN");
            Check(T("connect") == "Подключить", "Shared Java preference");
            Check(T("server", "127.0.0.1", 9000, 2).Contains("9000"), "Formatted status");
            Call("Initialize", new[] { "--language=en" }, preferences, "ru-RU");
            Check(T("connect") == "Connect", "Command-line override");
            Call("Initialize", new string[0], preferences + ".missing", "ru-RU");
            Check(T("connect") == "Подключить", "System locale fallback");
            Call("Initialize", new[] { "--language=de" }, preferences, "ru-RU");
            Check(T("connect") == "Connect", "Unsupported locale fallback");
            Check(File.ReadAllText(preferences).Contains("other.setting=keep"), "Preferences must not be modified");
            if (args.Length > 1)
            {
                Call("Initialize", new[] { "--language=ru" }, preferences, "en");
                // Render our own off-screen form with its startup handler detached:
                // no BLE scan, TCP server or registry settings are touched.
                using (var form = (System.Windows.Forms.Form)Activator.CreateInstance(assembly.GetType("BLE_tcp_driver.Form1")))
                {
                    form.Load -= (EventHandler)Delegate.CreateDelegate(typeof(EventHandler), form,
                        form.GetType().GetMethod("Form1_Load", BindingFlags.Instance | BindingFlags.NonPublic));
                    form.ShowInTaskbar = false;
                    form.StartPosition = System.Windows.Forms.FormStartPosition.Manual;
                    form.Location = new System.Drawing.Point(-20000, -20000);
                    form.Show();
                    form.PerformLayout();
                    var log = (System.Windows.Forms.RichTextBox)form.Controls.Find("rtbMsg", true)[0];
                    var header = form.Controls.OfType<System.Windows.Forms.TableLayoutPanel>().Single();
                    Check(log.Top >= header.Bottom, "Log must not overlap translated controls");
                    log.Text = T("tcpStarted", 9000) + Environment.NewLine + T("status", 98, 50, 1, 0, 2, 0, 0);
                    using (var bitmap = new System.Drawing.Bitmap(form.Width, form.Height))
                    {
                        form.DrawToBitmap(bitmap, new System.Drawing.Rectangle(System.Drawing.Point.Empty, form.Size));
                        bitmap.Save(args[1], System.Drawing.Imaging.ImageFormat.Png);
                    }
                }
            }
            Console.WriteLine("BLE_LOCALIZATION_TESTS=PASS (catalogs, placeholders, preference priority, fallback)");
            return 0;
        }
        finally
        {
            File.Delete(preferences);
            Directory.Delete(temp);
        }
    }
}
