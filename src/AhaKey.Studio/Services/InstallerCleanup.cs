using System.IO;
using System.Windows;
using AhaKey.Services;
namespace AhaKey.Studio.Services;
public static class InstallerCleanup
{
    public static int Run(bool interactive)
    {
        var store=new SettingsStore();var l=new LocalizationService();l.Apply(store.Load().Language);
        using var owner=new SingleInstanceOwner(store.Root);
        if(!owner.IsPrimary)
        {
            if(interactive)MessageBox.Show(l["InstallerCloseStudio"],"AhaKey Studio",MessageBoxButton.OK,MessageBoxImage.Information);
            return 1602; // Windows Installer cancels; never force-kill a tray or flash owner.
        }
        WindowsStartup.SetEnabled(false);
        bool remove=interactive && MessageBox.Show(l["InstallerRemoveData"],"AhaKey Studio",MessageBoxButton.YesNo,MessageBoxImage.Question,MessageBoxResult.No)==MessageBoxResult.Yes;
        if(remove)
        {
            var root=Path.GetFullPath(store.Root);
            if((File.GetAttributes(root)&FileAttributes.ReparsePoint)!=0)throw new IOException("User data root is a link.");
            var entries=Directory.EnumerateFileSystemEntries(root).Where(p=>Path.GetFileName(p)!="instance.lock").ToArray();
            foreach(var path in entries)
            {
                // Never traverse redirected user directories during uninstall.
                if((File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0)throw new IOException("User data contains a link; remove manually.");
                if(Directory.Exists(path))ValidateDirectory(path);
            }
            foreach(var path in entries){if(Directory.Exists(path))Directory.Delete(path,true);else File.Delete(path);}
        }
        return 0;
    }
    private static void ValidateDirectory(string directory)
    {
        foreach(var entry in Directory.EnumerateFileSystemEntries(directory))
        {
            var attributes=File.GetAttributes(entry);
            if((attributes&FileAttributes.ReparsePoint)!=0)throw new IOException("User data contains a link; remove manually.");
            if((attributes&FileAttributes.Directory)!=0)ValidateDirectory(entry);
        }
    }
}
