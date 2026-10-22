using System.Windows;
using System.Windows.Media;
namespace AhaKey.Studio.Controls;
// Authored 24-unit vector grammar; no font glyphs, external icon runtime or native I/O.
public sealed class NavigationIcon : FrameworkElement
{
    public static readonly DependencyProperty KindProperty = DependencyProperty.Register(nameof(Kind), typeof(string), typeof(NavigationIcon), new FrameworkPropertyMetadata("Home", FrameworkPropertyMetadataOptions.AffectsRender));
    public static readonly DependencyProperty StrokeProperty = DependencyProperty.Register(nameof(Stroke), typeof(Brush), typeof(NavigationIcon), new FrameworkPropertyMetadata(Brushes.Gray, FrameworkPropertyMetadataOptions.AffectsRender));
    public string Kind { get => (string)GetValue(KindProperty); set => SetValue(KindProperty,value); }
    public Brush Stroke { get => (Brush)GetValue(StrokeProperty); set => SetValue(StrokeProperty,value); }
    private static readonly IReadOnlyDictionary<string,Geometry> Shapes = new Dictionary<string,string>
    {
        ["Home"]="M3 5a1 1 0 0 1 1 -1h16a1 1 0 0 1 1 1v10a1 1 0 0 1 -1 1h-16a1 1 0 0 1 -1 -1l0 -10 M7 20h10 M9 16v4 M15 16v4 M7 10h2l2 3l2 -6l1 3h3",
        ["Keymap"]="M2 8a2 2 0 0 1 2 -2h16a2 2 0 0 1 2 2v8a2 2 0 0 1 -2 2h-16a2 2 0 0 1 -2 -2l0 -8 M6 10l0 .01 M10 10l0 .01 M14 10l0 .01 M18 10l0 .01 M6 14l0 .01 M18 14l0 .01 M10 14l4 .01",
        ["Display"]="M3 5a1 1 0 0 1 1 -1h16a1 1 0 0 1 1 1v10a1 1 0 0 1 -1 1h-16a1 1 0 0 1 -1 -1l0 -10 M7 20h10 M9 16v4 M15 16v4 M9 12v-4 M12 12v-1 M15 12v-2 M12 12v-1",
        ["Lighting"]="M3 12h1m8 -9v1m8 8h1m-15.4 -6.4l.7 .7m12.1 -.7l-.7 .7 M9 16a5 5 0 1 1 6 0a3.5 3.5 0 0 0 -1 3a2 2 0 0 1 -4 0a3.5 3.5 0 0 0 -1 -3 M9.7 17l4.6 0",
        ["Integrations"]="M7 12l5 5l-1.5 1.5a3.536 3.536 0 1 1 -5 -5l1.5 -1.5 M17 12l-5 -5l1.5 -1.5a3.536 3.536 0 1 1 5 5l-1.5 1.5 M3 21l2.5 -2.5 M18.5 5.5l2.5 -2.5 M10 11l-2 2 M13 14l-2 2",
        ["Device"]="M5 6a1 1 0 0 1 1 -1h12a1 1 0 0 1 1 1v12a1 1 0 0 1 -1 1h-12a1 1 0 0 1 -1 -1l0 -12 M8 10v-2h2m6 6v2h-2m-4 0h-2v-2m8 -4v-2h-2 M3 10h2 M3 14h2 M10 3v2 M14 3v2 M21 10h-2 M21 14h-2 M14 21v-2 M10 21v-2",
        ["Diagnostics"]="M13 8l-9.383 9.418a2.091 2.091 0 0 0 0 2.967a2.11 2.11 0 0 0 2.976 0l9.407 -9.385 M9 3h4.586a1 1 0 0 1 .707 .293l6.414 6.414a1 1 0 0 1 .293 .707v4.586a2 2 0 1 1 -4 0v-3l-5 -5h-3a2 2 0 1 1 0 -4",
        ["Settings"]="M12 6a2 2 0 1 0 4 0a2 2 0 1 0 -4 0 M4 6l8 0 M16 6l4 0 M6 12a2 2 0 1 0 4 0a2 2 0 1 0 -4 0 M4 12l2 0 M10 12l10 0 M15 18a2 2 0 1 0 4 0a2 2 0 1 0 -4 0 M4 18l11 0 M19 18l1 0",
        ["Claude"]="M12,2 V22 M2,12 H22 M5,5 L19,19 M5,19 L19,5 M8,2 L16,22 M2,8 L22,16 M2,16 L22,8 M8,22 L16,2",
        ["Cursor"]="M5,2 L21,13 13,14 9,22 Z",
        ["Codex"]="M8,6 L2,12 8,18 M16,6 L22,12 16,18 M14,3 L10,21",
        ["Custom"]="M4,6 H20 M4,12 H20 M4,18 H20 M8,3 V9 M16,9 V15 M10,15 V21",
        ["Battery"]="M2,6 H19 V18 H2 Z M22,10 V14 M5,9 V15 M9,9 V15 M13,9 V15",
        ["Microphone"]="M9,5 A3,3 0 0 1 15,5 V12 A3,3 0 0 1 9,12 Z M5,11 V12 A7,7 0 0 0 19,12 V11 M12,19 V23 M8,23 H16",
        ["Confirm"]="M4,12 L10,18 21,5", ["Reject"]="M5,5 L19,19 M5,19 L19,5",
        ["Return"]="M21,5 V14 H4 M10,8 L4,14 10,20"
    }.ToDictionary(p=>p.Key,p=> { var geometry=Geometry.Parse(p.Value);geometry.Freeze();return geometry; });
    protected override Size MeasureOverride(Size availableSize) => new(20,20);
    protected override void OnRender(DrawingContext context)
    {
        base.OnRender(context); if(!Shapes.TryGetValue(Kind,out var geometry)) return;
        var size=Math.Min(ActualWidth,ActualHeight);context.PushTransform(new TranslateTransform((ActualWidth-size)/2,(ActualHeight-size)/2));context.PushTransform(new ScaleTransform(size/24,size/24));
        context.DrawGeometry(null,new Pen(Stroke,1.65) { StartLineCap=PenLineCap.Round,EndLineCap=PenLineCap.Round,LineJoin=PenLineJoin.Round },geometry);
        context.Pop();context.Pop();
    }
}
