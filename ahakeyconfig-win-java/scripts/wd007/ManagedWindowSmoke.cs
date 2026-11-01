using System;
using System.Collections.Generic;
using System.Drawing;
using System.Reflection;
using System.Windows.Forms;

// Loads the actual compiled window, without constructing ManagedBridge or any Bluetooth object.
public static class ManagedWindowSmoke {
    [STAThread] public static int Main(string[] args) {
        Application.EnableVisualStyles();
        var assembly=Assembly.LoadFrom(args[0]);
        var type=assembly.GetType("BLE_tcp_driver.ManagedBridgeWindow",true);
        int requests=0,phase=0;Exception failure=null;
        Action<string,Dictionary<string,object>> intent=(name,fields)=>{requests++;if(name=="selectionRequested" && ((string)fields["selectedTargetId"]!="B" || (string)fields["address"]!="AA:02" || (string)fields["selectionAuthority"]!="observed-A"))throw new Exception("selection lost observed authority/address");};
        var form=(Form)Activator.CreateInstance(type,BindingFlags.Public|BindingFlags.NonPublic|BindingFlags.Instance,null,new object[]{intent},null);
        var timer=new Timer {Interval=120};
        timer.Tick+=(s,e)=>{
            try {
                if(phase==0) {
                    if(!form.Visible || !form.IsHandleCreated)throw new Exception("window not created and visible");
                    type.GetMethod("SetChoices").Invoke(form,new object[]{new List<Dictionary<string,object>>{
                        new Dictionary<string,object>{{"targetId","A"},{"name","AhaKey"},{"address","AA:01"}},
                        new Dictionary<string,object>{{"targetId","B"},{"name","AhaKey"},{"address","AA:02"}}}});
                    type.GetMethod("SetStatus").Invoke(form,new object[]{"离线窗口测试：同名不同地址；未访问设备。"});
                    using(var bitmap=new Bitmap(form.Width,form.Height)){form.DrawToBitmap(bitmap,new Rectangle(0,0,bitmap.Width,bitmap.Height));bitmap.Save(args[1]);}
                    form.Close();
                    if(form.IsDisposed || form.Visible)throw new Exception("X did not hide live window");
                } else if(phase==1) {
                    type.GetMethod("Reveal").Invoke(form,null);
                    if(!form.Visible || form.IsDisposed)throw new Exception("existing window not restored");
                    foreach(Control control in form.Controls)if(control is FlowLayoutPanel)
                        foreach(Control button in control.Controls)if(button.Text=="刷新设备")((Button)button).PerformClick();
                    if(requests!=1)throw new Exception("UI did not emit exactly one refresh intent");
                    type.GetMethod("SetAuthority").Invoke(form,new object[]{"observed-A"});
                    foreach(Control control in form.Controls)if(control is ListBox)((ListBox)control).SelectedIndex=1;
                    foreach(Control control in form.Controls)if(control is FlowLayoutPanel)
                        foreach(Control button in control.Controls)if(button.Text=="连接所选键盘")((Button)button).PerformClick();
                    if(requests!=2)throw new Exception("current window did not emit selected address/authority");
                } else {timer.Stop();type.GetMethod("ExitOwner").Invoke(form,null);}
                phase++;
            }catch(Exception error){failure=error;timer.Stop();type.GetMethod("ExitOwner").Invoke(form,null);}
        };
        form.Shown+=(s,e)=>timer.Start();Application.Run(form);timer.Dispose();
        if(failure!=null){Console.Error.WriteLine(failure);return 1;}
        if(phase!=3 || !form.IsDisposed)throw new Exception("owner exit did not dispose window");
        Console.WriteLine("PASS actual compiled WinForms: create/show, two addresses, close-hide, same-window reveal, intent, owner exit; no Bluetooth");return 0;
    }
}
