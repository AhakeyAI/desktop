using System.Windows;
using System.Windows.Input;
using AhaKey.Core;
using AhaKey.Protocol;
using AhaKey.Services;
using AhaKey.Studio.Services;
namespace AhaKey.Studio.Views;
public partial class PhysicalKeyTestWindow : Window
{
    public LocalizationService L {get;}
    public string Instructions {get;}
    public string ExpectedText {get;}
    public string ObservedText=>L["PhysicalWaitingKey"];
    private readonly PhysicalKeyVerification verification;
    public event Action<ShortcutGesture,bool>? Observed;
    public PhysicalKeyTestWindow(KeyWritePlan plan,PhysicalKeyVerification verification,LocalizationService l)
        :this(plan.Profile,plan.Key,plan.Value.Shortcut,verification,l){}
    public PhysicalKeyTestWindow(HardwareProfileId profile,PhysicalKey key,ShortcutGesture expected,PhysicalKeyVerification verification,LocalizationService l)
    {
        L=l;this.verification=verification;Instructions=$"{L["PhysicalPressDevice"]} · {profile} / {(int)profile} · {key}";
        ExpectedText=L["PhysicalExpected"]+": "+expected.Display;
        InitializeComponent();DataContext=this;Loaded+=(_,_)=>{Activate();CaptureBox.Focus();};
    }
    private void CaptureKey(object sender,KeyEventArgs e)
    {
        if(e.IsRepeat)return;
        var key=LocalShortcutInput.ActualKey(e);e.Handled=true;
        if(LocalShortcutInput.IsModifier(key))return;
        var name=LocalShortcutInput.Name(key);if(name is null)return;
        var gesture=new ShortcutGesture(LocalShortcutInput.Modifiers(),name);
        var matched=verification.Observe(gesture);CaptureBox.Text=gesture.Display;
        ResultText.Text=L[matched?"PhysicalBehaviorVerified":"PhysicalMismatch"];
        Observed?.Invoke(gesture,matched);
    }
    private void CloseClicked(object sender,RoutedEventArgs e)=>Close();
}
