using System;
using WixToolset.Dtf.WindowsInstaller;
using AhaKey.Installation;

public static class InstalledApplicationActions {
    [CustomAction] public static ActionResult ResolveInstalledApplication(Session session) {
        try {
            if(session["REMOVE"]=="ALL")return ActionResult.Success;
            Instance old=InstalledApplication.Resolve(null,false,String.IsNullOrEmpty(session["Installed"])?null:session["ProductCode"]);
            string initial=session["AHAKEY_INITIAL_SOURCE"];
            if(!String.IsNullOrEmpty(initial))InstalledApplication.AssertSnapshot(initial,old);
            else session["AHAKEY_INITIAL_SOURCE"]=InstalledApplication.Snapshot(old);
            if(old==null){if(session["AHAKEY_OTA"]=="1")throw new Exception("更新所需原安装不存在");session["AHAKEY_UPGRADE"]="";session["JP_UPGRADABLE_FOUND"]="";return ActionResult.Success;}
            if(Version.Parse(old.Version)>Version.Parse(session["ProductVersion"]))throw new Exception("已安装较新版本，不能降级");
            bool maintenance=InstalledApplication.Same(old.ProductCode,session["ProductCode"]);
            if(!maintenance && (InstalledApplication.RollbackDisabled() || session["RollbackDisabled"]=="1" || session["DISABLEROLLBACK"]=="1"))throw new Exception("系统已禁用安装回滚，无法安全升级");
            if(session["AHAKEY_OTA"]=="1") {
                InstalledApplication.AssertSource(old,session["AHAKEY_SOURCE_PRODUCT"],session["AHAKEY_SOURCE_DIR"],session["AHAKEY_SOURCE_VERSION"],session["AHAKEY_SOURCE_MSI"]);
                if(old.Context!=4 || old.Variant!=session["AHAKEY_VARIANT"])throw new Exception("更新安装形态不匹配");
            }
            session["INSTALLDIR"]=old.Directory+"\\";session["AHAKEY_UPGRADE"]=maintenance?"":"1";
            // Never trust a public action property as an uninstall list.
            session["JP_UPGRADABLE_FOUND"]=InstalledApplication.RemovalList(old,session["ProductCode"]);
            session["AHAKEY_RESOLVED_PRODUCT"]=old.ProductCode;session["AHAKEY_RESOLVED_DIR"]=old.Directory;
            session["AhaKeyResolvedHash"]=old.MsiSha256;session["AhaKeyResolvedVersion"]=old.Version;
            return ActionResult.Success;
        } catch(Exception e) {session.Log("AhaKey 安装检查失败: "+e);using(var r=new Record(1)){r[0]="AhaKey: "+e.Message;session.Message(InstallMessage.Error,r);}return ActionResult.Failure;}
    }
    [CustomAction] public static ActionResult VerifyInstalledApplication(Session session) {
        try {
            if(session["REMOVE"]=="ALL")return ActionResult.Success;
            Instance old=InstalledApplication.Resolve(null,false,String.IsNullOrEmpty(session["Installed"])?null:session["ProductCode"]);
            InstalledApplication.AssertSnapshot(session["AHAKEY_INITIAL_SOURCE"],old);
            if(old==null){if(session["AHAKEY_UPGRADE"]=="1" || session["AHAKEY_OTA"]=="1")throw new Exception("原安装已改变");session["JP_UPGRADABLE_FOUND"]="";return ActionResult.Success;}
            if(!InstalledApplication.Same(old.ProductCode,session["AHAKEY_RESOLVED_PRODUCT"]) || !InstalledApplication.Same(old.Directory,InstalledApplication.Normalize(session["INSTALLDIR"])) || !InstalledApplication.Same(old.Directory,session["AHAKEY_RESOLVED_DIR"]))throw new Exception("不能更改已安装应用目录");
            InstalledApplication.AssertSource(old,session["AHAKEY_RESOLVED_PRODUCT"],session["AHAKEY_RESOLVED_DIR"],session["AhaKeyResolvedVersion"],session["AhaKeyResolvedHash"]);
            bool maintenance=InstalledApplication.Same(old.ProductCode,session["ProductCode"]);
            if(!maintenance && (InstalledApplication.RollbackDisabled() || session["RollbackDisabled"]=="1" || session["DISABLEROLLBACK"]=="1"))throw new Exception("安装回滚不可用");
            session["JP_UPGRADABLE_FOUND"]=InstalledApplication.RemovalList(old,session["ProductCode"]);
            return ActionResult.Success;
        }catch(Exception e){session.Log("AhaKey 安装复验失败: "+e);return ActionResult.Failure;}
    }
}
