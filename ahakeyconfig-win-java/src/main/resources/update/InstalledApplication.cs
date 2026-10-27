using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace AhaKey.Installation {
    // Shared by the non-elevated worker and the MSI action. Never installs or repairs products.
    public sealed class Instance {
        public string ProductCode, UpgradeCode, Version, Variant, Arch, Directory, Launcher, BuildId, MsiSha256, Sid;
        public uint Context;
        public int State;
    }
    public static class InstalledApplication {
        public const string Upgrade = "{03E5A934-FFCA-3815-B455-7D49BF1CA1DC}";
        const uint MoreData = 234, NoMore = 259;
        [DllImport("msi.dll", CharSet=CharSet.Unicode)] static extern uint MsiEnumRelatedProducts(string code, uint reserved, uint index, StringBuilder product);
        [DllImport("msi.dll", CharSet=CharSet.Unicode)] static extern uint MsiEnumProductsEx(string product, string sid, uint context, uint index, StringBuilder code, out uint foundContext, StringBuilder foundSid, ref uint size);
        [DllImport("msi.dll", CharSet=CharSet.Unicode)] static extern uint MsiGetProductInfoEx(string code, string sid, uint context, string property, StringBuilder value, ref uint size);
        [DllImport("msi.dll", CharSet=CharSet.Unicode)] static extern uint MsiOpenDatabase(string file, IntPtr mode, out uint handle);
        [DllImport("msi.dll", CharSet=CharSet.Unicode)] static extern uint MsiDatabaseOpenView(uint database, string sql, out uint view);
        [DllImport("msi.dll")] static extern uint MsiViewExecute(uint view, uint record);
        [DllImport("msi.dll")] static extern uint MsiViewFetch(uint view, out uint record);
        [DllImport("msi.dll", CharSet=CharSet.Unicode)] static extern uint MsiRecordGetString(uint record, uint field, StringBuilder text, ref uint size);
        [DllImport("msi.dll")] static extern uint MsiCloseHandle(uint handle);
        [DllImport("msi.dll")] static extern uint MsiRecordReadStream(uint record,uint field,byte[] buffer,ref uint count);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr LoadLibraryEx(string file,IntPtr reserved,uint flags);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern IntPtr FindResource(IntPtr module,string name,IntPtr type);
        [DllImport("kernel32.dll")] static extern uint SizeofResource(IntPtr module,IntPtr resource);
        [DllImport("kernel32.dll")] static extern IntPtr LoadResource(IntPtr module,IntPtr resource);
        [DllImport("kernel32.dll")] static extern IntPtr LockResource(IntPtr resource);
        [DllImport("kernel32.dll")] static extern bool FreeLibrary(IntPtr module);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern Microsoft.Win32.SafeHandles.SafeFileHandle CreateFile(string path,uint access,uint share,IntPtr security,uint creation,uint flags,IntPtr template);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetFinalPathNameByHandle(Microsoft.Win32.SafeHandles.SafeFileHandle file,StringBuilder path,uint size,uint flags);
        [DllImport("msi.dll", CharSet=CharSet.Unicode)] static extern int MsiGetComponentPathEx(string product, string component, string sid, uint context, StringBuilder path, ref uint size);
        static void Check(uint code) { if (code != 0) throw new IOException("MSI 查询失败: " + code); }
        static string Info(string code, uint context, string sid, string key) {
            uint size = 0; uint result = MsiGetProductInfoEx(code, context == 4 ? null : sid, context, key, null, ref size);
            if (result != 0 && result != MoreData) Check(result);
            var text = new StringBuilder((int)size + 1); size++;
            Check(MsiGetProductInfoEx(code, context == 4 ? null : sid, context, key, text, ref size)); return text.ToString();
        }
        public static string Query(string file, string sql) {
            uint db=0, view=0, row=0;
            try {
                Check(MsiOpenDatabase(file, IntPtr.Zero, out db)); Check(MsiDatabaseOpenView(db, sql, out view)); Check(MsiViewExecute(view, 0));
                uint code = MsiViewFetch(view, out row); if (code == NoMore) return ""; Check(code);
                uint size=0; code=MsiRecordGetString(row,1,null,ref size); if(code!=0 && code!=MoreData)Check(code);
                var text=new StringBuilder((int)size+1);size++;Check(MsiRecordGetString(row,1,text,ref size));
                uint second=0; code=MsiViewFetch(view,out second); if(second!=0)MsiCloseHandle(second);
                if(code!=NoMore)throw new IOException("MSI 查询不是唯一结果"); return text.ToString();
            } finally {if(row!=0)MsiCloseHandle(row);if(view!=0)MsiCloseHandle(view);if(db!=0)MsiCloseHandle(db);}
        }
        public static string Property(string file,string key) {
            if(!System.Text.RegularExpressions.Regex.IsMatch(key,"^[A-Za-z_][A-Za-z0-9_]*$"))throw new IOException("非法 MSI 属性名");
            return Query(file,"SELECT `Value` FROM `Property` WHERE `Property`='"+key+"'");
        }
        static string LauncherComponent(string file) {
            uint db=0,view=0,row=0;string component=null;
            try {
                Check(MsiOpenDatabase(file,IntPtr.Zero,out db));Check(MsiDatabaseOpenView(db,"SELECT `FileName`,`Component_` FROM `File`",out view));Check(MsiViewExecute(view,0));
                for(;;){uint result=MsiViewFetch(view,out row);if(result==NoMore)break;Check(result);
                    try {var name=new StringBuilder(512);uint size=512;Check(MsiRecordGetString(row,1,name,ref size));
                        string[] names=name.ToString().Split('|');if(!Same(names[names.Length-1],"AhaKeyStudio.exe"))continue;
                        if(component!=null)throw new IOException("启动器组件不唯一");var id=new StringBuilder(256);size=256;Check(MsiRecordGetString(row,2,id,ref size));component=id.ToString();
                    }finally{MsiCloseHandle(row);row=0;}
                }
            }finally{if(row!=0)MsiCloseHandle(row);if(view!=0)MsiCloseHandle(view);if(db!=0)MsiCloseHandle(db);}
            if(component==null || !System.Text.RegularExpressions.Regex.IsMatch(component,"^[A-Za-z_][A-Za-z0-9_.]*$"))throw new IOException("启动器组件缺失");
            return Query(file,"SELECT `ComponentId` FROM `Component` WHERE `Component`='"+component+"'");
        }
        public static string Hash(string path) {using(var f=File.OpenRead(path))using(var h=System.Security.Cryptography.SHA256.Create())return BitConverter.ToString(h.ComputeHash(f)).Replace("-","").ToLowerInvariant();}
        public static byte[] Resource(string file,string name) {
            IntPtr module=LoadLibraryEx(file,IntPtr.Zero,0x22);if(module==IntPtr.Zero)throw new IOException("不能只读映射安装器");
            try{IntPtr resource=FindResource(module,name,new IntPtr(10));uint size=SizeofResource(module,resource);if(resource==IntPtr.Zero || size==0 || size>Int32.MaxValue)throw new IOException("安装器资源缺失");var bytes=new byte[size];Marshal.Copy(LockResource(LoadResource(module,resource)),bytes,0,(int)size);return bytes;}finally{FreeLibrary(module);}
        }
        public static string BinaryHash(string file,string name) {
            if(!System.Text.RegularExpressions.Regex.IsMatch(name,"^[A-Za-z_][A-Za-z0-9_]*$"))throw new IOException("非法 Binary 名称");
            uint db=0,view=0,row=0;
            try {Check(MsiOpenDatabase(file,IntPtr.Zero,out db));Check(MsiDatabaseOpenView(db,"SELECT `Data` FROM `Binary` WHERE `Name`='"+name+"'",out view));Check(MsiViewExecute(view,0));Check(MsiViewFetch(view,out row));
                using(var sha=System.Security.Cryptography.SHA256.Create()){var buffer=new byte[65536];for(;;){uint size=(uint)buffer.Length;Check(MsiRecordReadStream(row,1,buffer,ref size));if(size==0)break;sha.TransformBlock(buffer,0,(int)size,null,0);}sha.TransformFinalBlock(new byte[0],0,0);return BitConverter.ToString(sha.Hash).Replace("-","").ToLowerInvariant();}
            }finally{if(row!=0)MsiCloseHandle(row);if(view!=0)MsiCloseHandle(view);if(db!=0)MsiCloseHandle(db);}
        }
        public static string Normalize(string path) {
            if(String.IsNullOrWhiteSpace(path) || path.IndexOfAny(new[]{'"','\r','\n','\t','*','?'})>=0 || path.StartsWith(@"\\") || path.Length<4 || path[1]!=':' || path[2]!='\\')throw new IOException("安装目录无效");
            foreach(char c in path)if(Char.IsControl(c))throw new IOException("安装目录包含控制字符");
            string full=Path.GetFullPath(path).TrimEnd('\\');
            if(full.Length<=3 || full.IndexOf(':',2)>=0)throw new IOException("安装目录不能是磁盘根或设备路径");return full;
        }
        public static bool Same(string a,string b) {return String.Equals(a,b,StringComparison.OrdinalIgnoreCase);}
        public static void CheckDisk(string directory,string launcher) {CheckDisk(directory,launcher,false);}
        public static void CheckDisk(string directory,string launcher,bool repair) {
            if(!Same(Normalize(directory),Normalize(Path.GetDirectoryName(launcher))) || !Same(Path.GetFileName(launcher),"AhaKeyStudio.exe") || (!repair && !File.Exists(launcher)))throw new IOException("安装启动器与已登记目录不一致");
            // Refuse redirects, including any ancestor; do not silently follow a junction into another installation.
            for(var d=new DirectoryInfo(directory);d!=null;d=d.Parent)if(d.Exists && (d.Attributes&FileAttributes.ReparsePoint)!=0)throw new IOException("安装路径包含重解析点");
            if(File.Exists(launcher)) {
                if((File.GetAttributes(launcher)&FileAttributes.ReparsePoint)!=0)throw new IOException("安装启动器包含重解析点");
                using(var handle=CreateFile(launcher,0,7,IntPtr.Zero,3,0,IntPtr.Zero)) {
                    if(handle.IsInvalid)throw new IOException("无法核对启动器文件句柄");var final=new StringBuilder(32768);
                    uint length=GetFinalPathNameByHandle(handle,final,32768,0);if(length==0 || length>=32768)throw new IOException("无法解析启动器最终路径");
                    string path=final.ToString();if(path.StartsWith(@"\\?\"))path=path.Substring(4);
                    if(!Same(Normalize(path),Normalize(launcher)))throw new IOException("启动器最终路径与登记不一致");
                }
            }
        }
        public static Instance Select(IList<Instance> records,string currentLauncher,bool required) {
            if(records.Count==0){if(required)throw new IOException("没有可核实的 MSI 安装记录");return null;}
            if(records.Count!=1)throw new IOException("发现多个安装实例，无法安全选择原目录");
            Instance item=records[0];Guid guid;
            if(item.State!=5 || item.Context!=4 || !Guid.TryParse(item.ProductCode,out guid) || !Same(item.UpgradeCode,Upgrade) || item.Arch!="x64" || (item.Variant!="local-model"&&item.Variant!="lite"))throw new IOException("安装范围或身份不受支持");
            Version.Parse(item.Version);item.Directory=Normalize(item.Directory);
            if(!Same(Path.Combine(item.Directory,"AhaKeyStudio.exe"),item.Launcher))throw new IOException("MSI 组件启动器与目录不一致");
            if(!String.IsNullOrEmpty(currentLauncher) && !Same(Normalize(currentLauncher),Normalize(item.Launcher)))throw new IOException("当前应用不是该 MSI 登记的启动器");
            return item;
        }
        public static Instance Resolve(string currentLauncher,bool required) {return Resolve(currentLauncher,required,null);}
        public static Instance Resolve(string currentLauncher,bool required,string maintenanceProduct) {
            var records=new List<Instance>();
            for(uint i=0;;i++) {
                var code=new StringBuilder(39); uint result=MsiEnumRelatedProducts(Upgrade,0,i,code);
                if(result==NoMore)break;Check(result);
                bool found=false;
                for(uint j=0;;j++) {
                    var product=new StringBuilder(39);var sid=new StringBuilder(256);uint count=256,context;
                    result=MsiEnumProductsEx(code.ToString(),null,7,j,product,out context,sid,ref count);
                    if(result==NoMore)break;Check(result);found=true;
                    string user=sid.ToString(), id=product.ToString();
                    if(Info(id,context,user,"State")!="5")throw new IOException("相关产品不是完整已安装实例");
                    string cache=Info(id,context,user,"LocalPackage");
                    if(!File.Exists(cache))throw new IOException("已安装 MSI 缓存缺失");
                    if(Property(cache,"ProductName")!="AhaKeyStudio" || !Same(Property(cache,"ProductCode"),id))throw new IOException("缓存产品身份不匹配");
                    string component=LauncherComponent(cache);
                    if(String.IsNullOrEmpty(component))throw new IOException("无法核对启动器组件");
                    var path=new StringBuilder(32768);uint length=32768;
                    int componentState=MsiGetComponentPathEx(id,component,context==4?null:user,context,path,ref length);
                    if(componentState!=3 && !Same(id,maintenanceProduct))throw new IOException("启动器组件未本地安装");
                    if(path.Length==0 && Same(id,maintenanceProduct))path.Append(Path.Combine(Info(id,context,user,"InstallLocation"),"AhaKeyStudio.exe"));
                    var item=new Instance{ProductCode=id,UpgradeCode=Property(cache,"UpgradeCode"),Version=Info(id,context,user,"VersionString"),Variant=Property(cache,"AHAKEY_VARIANT"),Arch=Property(cache,"AHAKEY_ARCH"),Directory=Info(id,context,user,"InstallLocation"),Launcher=path.ToString(),BuildId=Property(cache,"AHAKEY_BUILD_ID"),MsiSha256=Hash(cache),Context=context,Sid=user,State=5};
                    if(item.Version!=Property(cache,"ProductVersion"))throw new IOException("登记版本与缓存版本不匹配");records.Add(item);
                }
                if(!found)throw new IOException("相关产品的安装上下文不可查询");
            }
            Instance selected=Select(records,currentLauncher,required);if(selected!=null)CheckDisk(selected.Directory,selected.Launcher,Same(selected.ProductCode,maintenanceProduct));return selected;
        }
        public static string Snapshot(Instance item) {
            if(item==null)return "none";
            string content=String.Join("\0",new[]{item.ProductCode.ToUpperInvariant(),item.UpgradeCode.ToUpperInvariant(),item.Version,item.Variant,item.Arch,Normalize(item.Directory).ToUpperInvariant(),item.Launcher.ToUpperInvariant(),item.BuildId,item.MsiSha256,item.Context.ToString(),item.Sid});
            using(var sha=System.Security.Cryptography.SHA256.Create())return BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(content))).Replace("-","");
        }
        public static void AssertSnapshot(string initial,Instance current) {if(initial!=Snapshot(current))throw new IOException("安装会话期间源实例已改变");}
        public static string RemovalList(Instance source,string target) {return source==null || Same(source.ProductCode,target)?"":source.ProductCode;}
        public static void AssertSource(Instance actual,string product,string directory,string version,string msiHash) {
            if(actual==null || !Same(actual.ProductCode,product) || !Same(actual.Directory,Normalize(directory)) || actual.Version!=version || actual.MsiSha256!=msiHash)throw new IOException("源安装在更新期间改变");
        }
        public static bool RollbackDisabled() {
            foreach(var hive in new[]{RegistryHive.LocalMachine,RegistryHive.CurrentUser})
            using(var root=RegistryKey.OpenBaseKey(hive,RegistryView.Registry64))
            using(var key=root.OpenSubKey(@"Software\Policies\Microsoft\Windows\Installer")) {
                object value=key==null?null:key.GetValue("DisableRollback");if(value!=null && Convert.ToInt32(value)!=0)return true;
            }
            return false;
        }
        public static string Quote(string arg) {
            if(arg==null || arg.IndexOfAny(new[]{'\0','\r','\n'})>=0)throw new IOException("非法启动参数");
            var output=new StringBuilder("\"");int slashes=0;
            foreach(char c in arg){if(c=='\\'){slashes++;continue;}if(c=='"'){output.Append('\\',slashes*2+1).Append(c);slashes=0;continue;}output.Append('\\',slashes).Append(c);slashes=0;}
            return output.Append('\\',slashes*2).Append('"').ToString();
        }
    }
}
