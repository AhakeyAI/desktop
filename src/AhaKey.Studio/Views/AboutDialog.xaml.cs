using System.Windows;
using AhaKey.Services;
namespace AhaKey.Studio.Views;
public partial class AboutDialog : Window
{
    public AppVersionService Version=>AppVersionService.Current;
    public AboutDialog(LocalizationService l) { InitializeComponent(); DataContext = new {L=l,Version}; }
    private void CloseDialog(object sender, RoutedEventArgs e) => Close();
}
