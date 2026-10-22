using System.Windows.Controls;
using AhaKey.Studio.ViewModels;
namespace AhaKey.Studio.Views;
public partial class KeymapPage : UserControl
{
    public KeymapPage() { InitializeComponent(); IsVisibleChanged+=(_,_)=>{ if(!IsVisible && DataContext is KeymapViewModel vm) vm.CancelCapture(); }; Unloaded+=(_,_)=>{if(DataContext is KeymapViewModel vm) vm.CancelCapture();}; }
}
