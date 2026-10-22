using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
namespace AhaKey.Studio.Controls;
public partial class DisplayPreview : UserControl
{
    public static readonly DependencyProperty StateTitleProperty=DependencyProperty.Register(nameof(StateTitle),typeof(string),typeof(DisplayPreview),new PropertyMetadata(""));
    public static readonly DependencyProperty CurrentFramesProperty=DependencyProperty.Register(nameof(CurrentFrames),typeof(int),typeof(DisplayPreview),new PropertyMetadata(0));
    public static readonly DependencyProperty MaximumFramesProperty=DependencyProperty.Register(nameof(MaximumFrames),typeof(int),typeof(DisplayPreview),new PropertyMetadata(0));
    public static readonly DependencyProperty SourceNameProperty=DependencyProperty.Register(nameof(SourceName),typeof(string),typeof(DisplayPreview),new PropertyMetadata(""));
    public static readonly DependencyProperty PreviewSourceProperty=DependencyProperty.Register(nameof(PreviewSource),typeof(ImageSource),typeof(DisplayPreview));
    public string StateTitle { get=>(string)GetValue(StateTitleProperty); set=>SetValue(StateTitleProperty,value); }
    public int CurrentFrames { get=>(int)GetValue(CurrentFramesProperty); set=>SetValue(CurrentFramesProperty,value); }
    public int MaximumFrames { get=>(int)GetValue(MaximumFramesProperty); set=>SetValue(MaximumFramesProperty,value); }
    public string SourceName { get=>(string)GetValue(SourceNameProperty); set=>SetValue(SourceNameProperty,value); }
    public ImageSource? PreviewSource { get=>(ImageSource?)GetValue(PreviewSourceProperty); set=>SetValue(PreviewSourceProperty,value); }
    public DisplayPreview()=>InitializeComponent();
}
