using System.Windows;
using System.Windows.Controls;
using AhaKey.Studio.ViewModels;
namespace AhaKey.Studio.Views;
public partial class SettingsPage : UserControl
{
    public SettingsPage() => InitializeComponent();
    private void ShowAbout(object sender, RoutedEventArgs e)
    { var vm = (ShellViewModel)DataContext; new AboutDialog(vm.L) { Owner = Window.GetWindow(this) }.ShowDialog(); }
}
