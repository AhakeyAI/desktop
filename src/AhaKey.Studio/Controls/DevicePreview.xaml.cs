using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
namespace AhaKey.Studio.Controls;
public enum DeviceRegionId { K1, K2, K3, K4, Display, Rgb, ConfirmationSwitch }
public sealed record DeviceRegion(DeviceRegionId Id, Rect Bounds);
public partial class DevicePreview : UserControl
{
    public static readonly DependencyProperty InteractiveProperty=DependencyProperty.Register(nameof(Interactive),typeof(bool),typeof(DevicePreview),new PropertyMetadata(false));
    public bool Interactive { get=>(bool)GetValue(InteractiveProperty); set=>SetValue(InteractiveProperty,value); }
    public static readonly DependencyProperty KeyRegionsProperty=DependencyProperty.Register(nameof(KeyRegions),typeof(System.Collections.IEnumerable),typeof(DevicePreview));
    public System.Collections.IEnumerable? KeyRegions { get=>(System.Collections.IEnumerable?)GetValue(KeyRegionsProperty); set=>SetValue(KeyRegionsProperty,value); }
    public static readonly DependencyProperty SelectedRegionProperty=DependencyProperty.Register(nameof(SelectedRegion),typeof(object),typeof(DevicePreview),new FrameworkPropertyMetadata(null,FrameworkPropertyMetadataOptions.BindsTwoWayByDefault));
    public object? SelectedRegion { get=>GetValue(SelectedRegionProperty); set=>SetValue(SelectedRegionProperty,value); }
    // Coordinates refer to the exact source crop. They are geometry, not protocol or key actions.
    public static IReadOnlyList<DeviceRegion> Regions { get; } = Array.AsReadOnly(new[] {
        new DeviceRegion(DeviceRegionId.K1,new(110,258,156,164)), new DeviceRegion(DeviceRegionId.K2,new(276,258,156,164)),
        new DeviceRegion(DeviceRegionId.K3,new(440,258,156,164)), new DeviceRegion(DeviceRegionId.K4,new(604,258,156,164)),
        new DeviceRegion(DeviceRegionId.Display,new(610,88,238,128)), new DeviceRegion(DeviceRegionId.Rgb,new(123,109,452,88)),
        new DeviceRegion(DeviceRegionId.ConfirmationSwitch,new(793,300,83,115)) });
    public static ImageSource HardwareImage { get; } = CreateReference();
    private static ImageSource CreateReference()
    {
        var source=new BitmapImage(new Uri("pack://application:,,,/Assets/HardwareReference.png"));
        var crop=new CroppedBitmap(source,new Int32Rect(120,910,920,520)); crop.Freeze(); return crop;
    }
    public DevicePreview() => InitializeComponent();
}
