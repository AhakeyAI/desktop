using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using System.Windows.Media;
using System.Windows.Input;
using AhaKey.Studio.ViewModels;
namespace AhaKey.Studio.Views;
public partial class IntegrationsPage : UserControl
{
    private Button? detailsOrigin;
    public IntegrationsPage() {InitializeComponent();PreviewMouseWheel+=ScrollPage;}
    private void ScrollPage(object sender,MouseWheelEventArgs e)
    {
        // This page has one scroll owner, including wheel input over buttons and read-only details.
        DependencyObject? parent=VisualTreeHelper.GetParent(this);
        while(parent is not null && parent is not ScrollViewer)parent=VisualTreeHelper.GetParent(parent);
        if(parent is ScrollViewer scroll && scroll.ScrollableHeight>0)
        {scroll.ScrollToVerticalOffset(scroll.VerticalOffset-e.Delta);e.Handled=true;}
    }
    private void PrimaryClicked(object sender,RoutedEventArgs e)
    {
        var button=(Button)sender;
        if(button.DataContext is IntegrationRow {PrimaryAction:"Install" or "Repair"})DetailsClicked(sender,e);
    }
    private void MaintenanceClicked(object sender,RoutedEventArgs e)
    {
        if(sender is not Button {DataContext:IntegrationRow row} button || DataContext is not IntegrationsViewModel vm)return;
        var menu=new ContextMenu();
        foreach(var action in row.CanConfigure?new[]{"Configure","Repair"}:Array.Empty<string>())Add(action,()=>{vm.PrepareFor(row,action);DetailsClicked(button,e);});
        if(row.CanRemove)Add("Remove",()=>{vm.PrepareFor(row,"Remove");DetailsClicked(button,e);});
        Add("OpenLocation",()=>vm.OpenConfiguration(row));
        void Add(string action,Action execute){var item=new MenuItem{Header=vm.L["Integration"+action]};item.Click+=(_,_)=>execute();menu.Items.Add(item);}
        menu.PlacementTarget=button;menu.IsOpen=true;
    }
    private void DetailsClicked(object sender, RoutedEventArgs e)
    {
        detailsOrigin = (Button)sender;
        Dispatcher.BeginInvoke(() =>
        {
            DetailsSection.UpdateLayout();
            DependencyObject? parent = this;
            while (parent is not null && parent is not ScrollViewer) parent = VisualTreeHelper.GetParent(parent);
            if (parent is ScrollViewer scroll)
                scroll.ScrollToVerticalOffset(scroll.VerticalOffset + DetailsSection.TransformToAncestor(scroll).Transform(new Point()).Y);
            DetailsBack.Focus();
        }, DispatcherPriority.Loaded);
    }
    private void BackClicked(object sender, RoutedEventArgs e)
    {
        Dispatcher.BeginInvoke(() => { detailsOrigin?.BringIntoView(); detailsOrigin?.Focus(); }, DispatcherPriority.Loaded);
    }
}
