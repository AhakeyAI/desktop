using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using AhaKey.Device;
using AhaKey.Services;
using AhaKey.Studio.ViewModels;
using Forms = System.Windows.Forms;
namespace AhaKey.Studio.Services;

public sealed class TrayLifetime : IDisposable
{
    private readonly Window window;
    private readonly ShellViewModel shell;
    private readonly ProfileSelectionService preferences;
    private readonly IntegrationRuntime integrations;
    private readonly RealDeviceRuntime connections;
    private readonly Func<Task> shutdown;
    private readonly Forms.NotifyIcon icon;
    private bool exiting, seenThisRun, disposed, connected;
    private string? firmwareState;
    private LocalizationService L => shell.L;
    public TrayLifetime(Window window, ShellViewModel shell, ProfileSelectionService preferences,
        IntegrationRuntime integrations, RealDeviceRuntime connections, Func<Task> shutdown)
    {
        this.window=window; this.shell=shell; this.preferences=preferences;
        this.integrations=integrations;this.connections=connections; this.shutdown=shutdown;
        using var stream=Application.GetResourceStream(new Uri("pack://application:,,,/Assets/AhaKeyStudio.ico"))!.Stream;
        icon=new Forms.NotifyIcon { Icon=new System.Drawing.Icon(stream), Text="AhaKey Studio", Visible=true };
        icon.DoubleClick+=(_,_)=>Show();
        window.Closing+=OnClosing;
        window.IsVisibleChanged+=(_,_)=>shell.DisplayPlanner.SetPreviewVisible(window.IsVisible);
        shell.Manager.Changed+=Refresh;
        shell.L.PropertyChanged+=LanguageChanged;
        integrations.Manager.Changed+=Refresh;
        shell.Firmware.PropertyChanged+=FirmwareChanged;
        Refresh();
    }
    public void Show() { window.ShowInTaskbar=true;window.ShowActivated=true;window.Show(); if(window.WindowState==WindowState.Minimized)window.WindowState=WindowState.Normal; window.Activate(); }
    private void LanguageChanged(object? sender, PropertyChangedEventArgs e)=>Refresh();
    private void FirmwareChanged(object? sender,PropertyChangedEventArgs e)
    {
        var state=shell.Firmware.State;if(firmwareState==state)return;firmwareState=state;
        if(state==L["FirmwareStateCompleted"] || state==L["FirmwareStateFailed"] || state==L["FirmwareStateRecoveryRequired"])
            icon.ShowBalloonTip(5000,"AhaKey Studio",state,Forms.ToolTipIcon.Info);
    }
    private void Refresh()
    {
        if(disposed)return;
        if(!window.Dispatcher.CheckAccess()){window.Dispatcher.BeginInvoke(Refresh);return;}
        var live=shell.Manager.RealDevice?.Observation.IsLive==true;
        if(connected && !live && !connections.ExplicitlyDisconnected && preferences.Settings.NotifyDeviceDisconnect)
            icon.ShowBalloonTip(4000,"AhaKey Studio",L["TrayDisconnected"],Forms.ToolTipIcon.Info);
        connected=live;
        var menu=new Forms.ContextMenuStrip();
        menu.Items.Add(L["TrayOpen"],null,(_,_)=>Show());
        menu.Items.Add(L["TrayDevice"]+": "+shell.DeviceStatusLabel).Enabled=false;
        menu.Items.Add(shell.HardwareProfile).Enabled=false;
        menu.Items.Add(L["TrayFeedback"]+": "+shell.SummaryLighting).Enabled=false;
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add(L[integrations.Manager.Server.Running?"TrayPause":"TrayResume"],null,async(_,_)=>
        {
            try { if(integrations.Manager.Server.Running)await integrations.Manager.Server.DisposeAsync();else integrations.Manager.Server.Start(); }
            catch(Exception ex) { CrashEvidence.Record(ex,"Tray integrations"); }
            Refresh();
        });
        menu.Items.Add(L["Settings"],null,(_,_)=>{shell.OpenSettingsCommand.Execute(null);Show();});
        menu.Items.Add(L["TrayExit"],null,async(_,_)=>await ExitAsync());
        var old=icon.ContextMenuStrip;
        if(old?.Visible==true){menu.Dispose();return;}
        icon.ContextMenuStrip=menu;old?.Dispose();
    }
    private void OnClosing(object? sender,CancelEventArgs e)
    {
        if(exiting)return;
        e.Cancel=true;
        if(!seenThisRun && !preferences.Settings.TrayExplanationSeen)
        {
            seenThisRun=true;
            var panel=new StackPanel { Margin=new Thickness(24) };
            panel.Children.Add(new TextBlock { Text=L["TrayFirstClose"], TextWrapping=TextWrapping.Wrap, MaxWidth=430, Margin=new Thickness(0,0,0,20) });
            var remember=new CheckBox { Content=L["TrayDontShow"], IsChecked=true, Margin=new Thickness(0,0,0,20) };panel.Children.Add(remember);
            var buttons=new WrapPanel();var got=new Button { Content=L["TrayGotIt"], IsDefault=true, Margin=new Thickness(0,0,12,0) };
            var exit=new Button { Content=L["TrayExitInstead"] };buttons.Children.Add(got);buttons.Children.Add(exit);panel.Children.Add(buttons);
            var dialog=new Window { Title="AhaKey Studio", Owner=window, Content=panel, SizeToContent=SizeToContent.WidthAndHeight, ResizeMode=ResizeMode.NoResize, WindowStartupLocation=WindowStartupLocation.CenterOwner, ShowInTaskbar=false };
            dialog.SetResourceReference(Window.BackgroundProperty,"AppBackground");dialog.SetResourceReference(Window.ForegroundProperty,"TextPrimary");
            bool quit=false;got.Click+=(_,_)=>dialog.Close();exit.Click+=(_,_)=>{quit=true;dialog.Close();};dialog.ShowDialog();
            if(remember.IsChecked==true)try{preferences.Update(s=>s with{TrayExplanationSeen=true});}catch(Exception ex){CrashEvidence.Record(ex,"Tray preference");}
            if(quit){_ = ExitAsync();return;}
        }
        window.Hide();
    }
    public async Task ExitAsync()
    {
        if(exiting)return;
        // Acquire the same owner gate: no writer can start between the check and shutdown.
        if(!await shell.Manager.Operations.WaitAsync(0,default))
        {
            Show();var panel=new StackPanel{Margin=new Thickness(24)};
            panel.Children.Add(new TextBlock{Text=L["TrayBusy"],TextWrapping=TextWrapping.Wrap,MaxWidth=400});
            var buttons=new WrapPanel{Margin=new Thickness(0,20,0,0)};panel.Children.Add(buttons);
            var dialog=new Window{Owner=window,Title="AhaKey Studio",Content=panel,SizeToContent=SizeToContent.WidthAndHeight,ResizeMode=ResizeMode.NoResize,WindowStartupLocation=WindowStartupLocation.CenterOwner};
            dialog.SetResourceReference(Window.BackgroundProperty,"Surface");dialog.SetResourceReference(Window.ForegroundProperty,"TextPrimary");
            var wait=new Button{Content=L["TrayWait"],IsDefault=true};buttons.Children.Add(wait);wait.Click+=(_,_)=>dialog.Close();
            if(shell.Firmware.CanCancel){var cancel=new Button{Content=L["FirmwareCancel"],Margin=new Thickness(12,0,0,0)};buttons.Children.Add(cancel);cancel.Click+=(_,_)=>{shell.Firmware.CancelCommand.Execute(null);dialog.Close();};}
            dialog.ShowDialog();return;
        }
        exiting=true;shell.Manager.Operations.ShutdownRequested=true;shell.Manager.Operations.Describe("Application exit",null,null,false);
        shell.Manager.Operations.Release();
        window.IsEnabled=false;
        try { await shutdown(); }
        catch(Exception ex){CrashEvidence.Record(ex,"Exit");}
        finally { Dispose();Application.Current.Shutdown(); }
    }
    public void Dispose()
    {
        if(disposed)return;disposed=true;window.Closing-=OnClosing;shell.Manager.Changed-=Refresh;
        shell.L.PropertyChanged-=LanguageChanged;integrations.Manager.Changed-=Refresh;
        shell.Firmware.PropertyChanged-=FirmwareChanged;
        icon.Visible=false;icon.Icon?.Dispose();icon.ContextMenuStrip?.Dispose();icon.Dispose();
    }
}
