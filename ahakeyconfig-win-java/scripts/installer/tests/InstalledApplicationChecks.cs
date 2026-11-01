using System;
using System.Collections.Generic;
using System.IO;
using AhaKey.Installation;

class InstalledApplicationChecks {
    static int checks;
    static void Check(string name,bool value){if(!value)throw new Exception(name);checks++;Console.WriteLine("PASS "+name);}
    static void Reject(string name,Action action){try{action();}catch(Exception){Check(name,true);return;}throw new Exception("Accepted invalid case: "+name);}
    static Instance Valid(){return new Instance{ProductCode="{11111111-1111-4111-8111-111111111111}",UpgradeCode=InstalledApplication.Upgrade,Version="1.0.11",Variant="local-model",Arch="x64",Directory=@"D:\我的 软件 (A)&B\AhaKey\",Launcher=@"D:\我的 软件 (A)&B\AhaKey\AhaKeyStudio.exe",State=5,Context=4,MsiSha256=new string('a',64),BuildId=new string('b',64)};}
    static void Main(string[] args){
        if(args.Length>0 && args[0]=="--echo"){File.WriteAllLines(args[1],new ArraySegment<string>(args,2,args.Length-2));return;}
        var v=Valid();Check("unique custom Unicode/spaces path",InstalledApplication.Select(new[]{v},v.Launcher,true)==v);
        Check("first install only",InstalledApplication.Select(new Instance[0],null,false)==null);
        Reject("OTA needs installed record",()=>InstalledApplication.Select(new Instance[0],null,true));
        Reject("ambiguous instances",()=>InstalledApplication.Select(new[]{Valid(),Valid()},null,true));
        Reject("wrong current launcher",()=>InstalledApplication.Select(new[]{Valid()},@"C:\Other\AhaKeyStudio.exe",true));
        foreach(int state in new[]{1,2,0}){var x=Valid();x.State=state;Reject("not installed "+state,()=>InstalledApplication.Select(new[]{x},null,true));}
        foreach(uint context in new uint[]{1,2,7}){var x=Valid();x.Context=context;Reject("unsupported context "+context,()=>InstalledApplication.Select(new[]{x},null,true));}
        var bad=Valid();bad.UpgradeCode=Guid.NewGuid().ToString();Reject("wrong family",()=>InstalledApplication.Select(new[]{bad},null,true));
        bad=Valid();bad.Arch="arm64";Reject("wrong arch",()=>InstalledApplication.Select(new[]{bad},null,true));
        bad=Valid();bad.Launcher=@"D:\other\AhaKeyStudio.exe";Reject("component differs",()=>InstalledApplication.Select(new[]{bad},null,true));
        foreach(string path in new[]{"",@"D:\",@"\\server\app",@"\\?\C:\app","C:\\bad\"name","C:\\bad\nname",@"C:\app:stream",@"D:relative"})Reject("unsafe path "+path,()=>InstalledApplication.Normalize(path));
        Check("case and trailing slash equivalent",InstalledApplication.Same(InstalledApplication.Normalize(@"d:\AhaKey\"),InstalledApplication.Normalize(@"D:\ahakey")));
        var source=Valid();source.Directory=InstalledApplication.Normalize(source.Directory);
        InstalledApplication.AssertSource(source,source.ProductCode,source.Directory,source.Version,source.MsiSha256);Check("source bound",true);
        Reject("source changed",()=>InstalledApplication.AssertSource(source,Guid.NewGuid().ToString(),source.Directory,source.Version,source.MsiSha256));
        Reject("source cache changed",()=>InstalledApplication.AssertSource(source,source.ProductCode,source.Directory,source.Version,new string('f',64)));
        Check("argument trailing slash escaped",InstalledApplication.Quote(@"D:\我的 软件\").EndsWith("\\\\\""));
        Reject("argument newline",()=>InstalledApplication.Quote("a\nb"));
        string target="{99999999-9999-4999-8999-999999999999}";
        Check("first install removal list empty",InstalledApplication.RemovalList(null,target)=="");
        Check("upgrade removes only verified source",InstalledApplication.RemovalList(source,target)==source.ProductCode);
        Check("maintenance does not remove itself",InstalledApplication.RemovalList(source,source.ProductCode)=="");
        string initial=InstalledApplication.Snapshot(source);InstalledApplication.AssertSnapshot(initial,source);Check("stable initial snapshot",true);
        Reject("first install cannot adopt new instance",()=>InstalledApplication.AssertSnapshot("none",source));
        Reject("source cannot disappear",()=>InstalledApplication.AssertSnapshot(initial,null));
        var changed=Valid();changed.ProductCode=target;Reject("source A cannot become B",()=>InstalledApplication.AssertSnapshot(initial,changed));
        changed=Valid();changed.MsiSha256=new string('d',64);Reject("same product recached",()=>InstalledApplication.AssertSnapshot(initial,changed));
        string temporary=Path.Combine(Path.GetTempPath(),"ahakey-repair-check-"+Guid.NewGuid().ToString());Directory.CreateDirectory(temporary);
        string missing=Path.Combine(temporary,"AhaKeyStudio.exe");InstalledApplication.CheckDisk(temporary,missing,true);Check("own-product repair permits missing launcher",true);
        Reject("major upgrade requires launcher",()=>InstalledApplication.CheckDisk(temporary,missing,false));
        Console.WriteLine("PASS "+checks+" isolated checks; no installation or registry writes");
    }
}
