using System.Windows;
using AhaKey.Studio.ViewModels;
using AhaKey.Protocol;
using AhaKey.Services;
namespace AhaKey.Studio.Views;
public partial class DisplayOverwriteWindow:Window
{
    public LocalizationService L {get;}
    public string Details {get;}
    public DisplayOverwriteWindow(StaticDisplayPlan plan,LocalizationService l)
    {L=l;Details=Describe(plan,l);InitializeComponent();DataContext=this;}
    public static string Describe(StaticDisplayPlan plan,LocalizationService l)=>
        $"Codex / 2 · {l["Default"]} · {l["DisplayTargetSlot"]} 9 / 292\n160×80 · RGB565 · 1 {l["DisplayFrames"]} · 25,600 bytes · 100 ms\n"+
        $"0x{plan.StartAddress:X6}–0x{plan.PixelEnd:X6}\n{l["DisplayEraseRange"]}: 0x{plan.StartAddress:X6}–0x{plan.EraseEnd:X6}\n"+
        $"{l["DisplaySectors"]}: 63–69 · A2: {plan.A2ReportCount} × 65 bytes\nSHA-256: {plan.Sha256}\n\n"+
        string.Join("\n",plan.Blocks.Select(b=>$"{b.Sector}: {b.Length} bytes · {Convert.ToHexString(b.Prepare.AsSpan()).ChunkText()}"))+
        $"\nRX: AA BB 80 00 CC DD → A2 → AA BB 81 00 CC DD\n82: {Convert.ToHexString(plan.Binding.AsSpan()).ChunkText()}\n04: AA BB 04 CC DD\n83: AA BB 83 02 CC DD\n{l["DisplayNoRetries"]}";
    private void Accept(object sender,RoutedEventArgs e)=>DialogResult=true;
}
