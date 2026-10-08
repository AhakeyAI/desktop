using System.Globalization;
using System.Windows.Data;
using AhaKey.Services;
namespace AhaKey.Studio.Services;
public sealed class ResourceKeyConverter : IMultiValueConverter
{
    public object Convert(object[] values, Type targetType, object parameter, CultureInfo culture) => values.Length > 1 && values[0] is LocalizationService l && values[1] is string key ? l[key] : "";
    public object[] ConvertBack(object value, Type[] targetTypes, object parameter, CultureInfo culture) => throw new NotSupportedException();
}
