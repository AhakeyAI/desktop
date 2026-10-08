using System.Windows;
using AhaKey.Integrations;
using AhaKey.Services;
namespace AhaKey.Studio.Views;
public partial class IntegrationApprovalWindow : Window
{
    private readonly ManualApprovalRequest request;
    public LocalizationService L { get; }
    public string ContextText => request.Context.Integration + " · " + request.Context.NativeEvent;
    public IntegrationApprovalWindow(ManualApprovalRequest request, LocalizationService l)
    {
        this.request=request;L=l;InitializeComponent();DataContext=this;
        Closed+=(_,_)=>request.Resolve(false);
    }
    private void Allow(object sender,RoutedEventArgs e) { request.Resolve(true);Close(); }
    private void Deny(object sender,RoutedEventArgs e) { request.Resolve(false);Close(); }
}
