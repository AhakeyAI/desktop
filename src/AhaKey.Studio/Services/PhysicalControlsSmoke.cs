using System.IO;
using System.Windows;
using AhaKey.Core;
using AhaKey.Protocol;
using AhaKey.Services;
using AhaKey.Studio.ViewModels;
using Microsoft.Extensions.DependencyInjection;
namespace AhaKey.Studio.Services;
public static class PhysicalControlsSmoke
{
    public static async Task RunAsync(Window window,IServiceProvider services,string output,Action<bool,string> check)
    {
        var vm=services.GetRequiredService<ShellViewModel>();
        var fixture=Path.Combine(AppContext.BaseDirectory,"DisplayFixtures");
        var native=DisplayImagePreparation.Load(Path.Combine(fixture,"native-canvas.png"),8);
        check(native.Frames[0].SequenceEqual(File.ReadAllBytes(Path.Combine(fixture,"python.rgb565"))),"WPF native canvas import matches original Python/Java bytes");
        var gif=DisplayImagePreparation.Load(Path.Combine(fixture,"timing.gif"),8);
        var widePath=Path.Combine(output,"wide-fit-crop-fixture.png");
        var pixels=Enumerable.Range(0,400*80).SelectMany(_=>new byte[]{255,0,0}).ToArray();
        var source=System.Windows.Media.Imaging.BitmapSource.Create(400,80,96,96,System.Windows.Media.PixelFormats.Rgb24,null,pixels,400*3);
        var encoder=new System.Windows.Media.Imaging.PngBitmapEncoder();encoder.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(source));using(var file=File.Create(widePath))encoder.Save(file);
        var fit=DisplayImagePreparation.Load(widePath,1,DisplayFitMode.Fit);var crop=DisplayImagePreparation.Load(widePath,1,DisplayFitMode.Crop);
        check(fit.Frames[0][0]==0 && crop.Frames[0][0]==0xF8 && crop.Frames[0][1]==0 && crop.Frames[0].Length==25600,"Fit keeps black margins; crop fills a 160x80 RGB565 canvas");
        check(crop.Preview.PixelWidth==160 && crop.Preview.PixelHeight==80,"Converted preview has exact device working dimensions");
        check(gif.Frames.Count==3 && gif.Timing.IntervalMs==200,"GIF frame count and uniform Java timing");
        for(int i=0;i<3;i++)check(gif.Frames[i].SequenceEqual(File.ReadAllBytes(Path.Combine(fixture,$"gif-{i}.rgb565"))),$"GIF composited frame {i} matches retained Python decoder");
        vm.DisplayPlanner.LoadFixture(Path.Combine(fixture,"timing.gif"));
        await vm.DisplayPlanner.Preparation;
        check(vm.DisplayPlanner.Plan is {PhysicalUploadAllowed:false,RollbackAvailable:false},"Display physical transmission unavailable");
        check(vm.Controls.Events.Count==9 && !vm.Controls.FeedbackEnabled && !vm.Controls.CanPreview,"Nine runtime events; physical feedback/preview gated by actual acceptance");
        window.Width=1024;window.Height=900;
        foreach(var language in new[]{LanguageChoice.English,LanguageChoice.Russian,LanguageChoice.Chinese})
        foreach(var theme in new[]{ThemeChoice.Light,ThemeChoice.Dark})
        {
            vm.Settings.Language=vm.Settings.Languages.Single(x=>x.Value==language);vm.Settings.Theme=vm.Settings.Themes.Single(x=>x.Value==theme);
            foreach(var page in new[]{PageId.Lighting,PageId.Display})
            {vm.NavigationSelection=vm.Navigation.Single(x=>x.Value==page);await StudioSmokeTest.Capture(window,output,$"phase4b-{page}-{language}-{theme}-1024");}
        }
        vm.Settings.Language=vm.Settings.Languages.Single(x=>x.Value==LanguageChoice.Russian);vm.Settings.Theme=vm.Settings.Themes.Single(x=>x.Value==ThemeChoice.Light);
        // Offline fixture only. Never invoke writer or synthesize a behavior observation.
        ShortcutGesture.TryParse("Ctrl+Enter",out var gesture);var plan=KeyWritePlan.Create(HardwareProfileId.Codex,PhysicalKey.K2,new(gesture!,"Send"));var verification=new PhysicalKeyVerification();verification.Begin();verification.Accept(plan.Value);
        var test=new Views.PhysicalKeyTestWindow(plan,verification,vm.L){Owner=window};test.Show();await StudioSmokeTest.Capture(test,output,"phase4b-key-test-offline-waiting");test.Close();
        vm.Settings.Language=vm.Settings.Languages.Single(x=>x.Value==LanguageChoice.English);
    }
}
