using System.Windows;
using System.Windows.Input;
using AhaKey.Core;
using AhaKey.Studio.Services;
using AhaKey.Studio.ViewModels;
namespace AhaKey.Studio;
public partial class MainWindow : Window
{
    private readonly HashSet<Key> capturedKeys=[];
    public MainWindow(ShellViewModel viewModel)
    {
        InitializeComponent(); DataContext=viewModel;
        viewModel.Keymap.CaptureRequested+=()=>{Activate();Keyboard.Focus(this);};
        PreviewKeyDown+=(_,e)=>
        {
            var key=LocalShortcutInput.ActualKey(e);
            if(capturedKeys.Contains(key)) {e.Handled=true; return;}
            if(!viewModel.Keymap.IsRecording) return;
            e.Handled=true; capturedKeys.Add(key);
            if(LocalShortcutInput.IsModifier(key)) {viewModel.Keymap.Capture.UpdateModifiers(LocalShortcutInput.Modifiers());viewModel.Keymap.Refresh();}
            else viewModel.Keymap.CaptureKey(LocalShortcutInput.Name(key) ?? "Unsupported",LocalShortcutInput.Modifiers());
        };
        PreviewKeyUp+=(_,e)=>{if(capturedKeys.Remove(LocalShortcutInput.ActualKey(e)) || viewModel.Keymap.IsRecording) e.Handled=true; if(viewModel.Keymap.IsRecording) {viewModel.Keymap.Capture.UpdateModifiers(LocalShortcutInput.Modifiers());viewModel.Keymap.Refresh();}};
        Deactivated+=(_,_)=>{viewModel.Keymap.CancelCapture();capturedKeys.Clear();};
        Closed+=(_,_)=>{viewModel.Keymap.CancelCapture();capturedKeys.Clear();};
    }
}
