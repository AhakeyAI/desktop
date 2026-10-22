using System.Windows;
using AhaKey.Protocol;
using AhaKey.Services;

namespace AhaKey.Studio.Services;
public class ProductDialogs
{
    public virtual bool ConfirmKey(string preview,LocalizationService l)=>MessageBox.Show(Application.Current.MainWindow,preview,l["ProductApply"],MessageBoxButton.OKCancel,MessageBoxImage.Warning)==MessageBoxResult.OK;
    public virtual bool ConfirmDisplay(StaticDisplayPlan plan,LocalizationService l)=>new Views.DisplayOverwriteWindow(plan,l){Owner=Application.Current.MainWindow}.ShowDialog()==true;
}
