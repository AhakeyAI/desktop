package com.example.ahakey.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.file.*;
import java.util.*;
import static com.example.ahakey.service.Wd007BehaviorChecks.*;

/** Explicit installs into a temporary home; no real user Hook configuration is touched. */
public final class Wd007HookManagementChecks {
    static class Installed extends HookInstaller {
        String version="1.44.0";
        Installed(){super(8765,System.out::println);}
        @Override public boolean isAppDetected(String platform){return true;}
        @Override protected String kimiVersion(){return version;}
        @Override protected Path kimiShareDirectory(){return Path.of(System.getProperty("user.home"),".kimi");}
    }
    static void concurrentEdits(Installed installer,Path home)throws Exception {
        var make=HookInstaller.class.getDeclaredMethod("configurationPlan",String.class,boolean.class);make.setAccessible(true);
        var apply=HookInstaller.class.getDeclaredMethod("applyPlan",Map.class);apply.setAccessible(true);
        Path config=installer.getHookConfigPath("Claude");Files.writeString(config,"{\"external\":1}");
        Object plan=make.invoke(installer,"Claude",false);String external="{\"external\":2}";Files.writeString(config,external);
        try{apply.invoke(installer,plan);throw new AssertionError("stale plan overwrote external changes");}catch(java.lang.reflect.InvocationTargetException expected){}
        check(Files.readString(config).equals(external),"planning-to-commit race preserves external edits");
        Path codex=installer.getHookConfigPath("Codex"),toml=codex.resolveSibling("config.toml");Files.createDirectories(toml.getParent());Files.writeString(toml,"model='before'\n");
        Object multi=make.invoke(installer,"Codex",false);Files.writeString(toml,"model='external'\n");
        try{apply.invoke(installer,multi);throw new AssertionError("stale TOML plan accepted");}catch(java.lang.reflect.InvocationTargetException expected){}
        check(!Files.exists(codex)&&Files.readString(toml).equals("model='external'\n"),"all multi-file snapshots checked before first write");
        @SuppressWarnings("unchecked") Map<Path,Object> rollback=(Map<Path,Object>)make.invoke(installer,"Claude",false);
        var planned=Class.forName("com.example.ahakey.service.HookInstaller$PlannedFile").getDeclaredConstructor(byte[].class,byte[].class);planned.setAccessible(true);
        Path blocker=home.resolve("not-a-directory");Files.writeString(blocker,"unchanged");
        rollback.put(blocker.resolve("fail.txt"),planned.newInstance(null,"fail".getBytes()));
        try{apply.invoke(installer,rollback);throw new AssertionError("write failure expected");}catch(java.lang.reflect.InvocationTargetException expected){}
        check(Files.readString(config).equals(external),"later file failure restores earlier config and leaves backup");
    }
    static void kimi(Installed installer,Path home)throws Exception {
        Path config=installer.getHookConfigPath("Kimi");Files.createDirectories(config.getParent());
        String foreign="# Keep my comment\n[[hooks]]\nevent='Stop'\ncommand='foreign-command'\ntimeout=14\n\n[other]\nvalue='preserve exactly'\n";
        String old="[[hooks]]\nevent='PermissionRequest'\ncommand='powershell -File \""+home.resolve(".ahakey/hooks/ahakey-hook.ps1").toString().replace("\\","/")+"\" KimiPermissionRequest'\ntimeout=10\n";
        Files.writeString(config,old+foreign);
        check(installer.getHookStatus("Kimi")==HookInstaller.HookStatus.OUTDATED,"unsupported owned legacy event remains repairable");
        check(installer.installOrUpdate("Kimi").success(),"Kimi migrates canonical config and current consumer events");
        String first=Files.readString(config);check(first.contains(foreign)&&!first.contains("PermissionRequest"),"foreign TOML bytes survive while owned invalid event removed");
        check(installer.getHookStatus("Kimi")==HookInstaller.HookStatus.LATEST,"Kimi scanner verifies generated registration");
        check(installer.installOrUpdate("Kimi").success()&&Files.readString(config).equals(first),"second same-version update writes nothing");
        Path evidence=Path.of(System.getProperty("wd007.artifacts",home.resolve("schema-evidence").toString()));Files.createDirectories(evidence);
        Files.writeString(evidence.resolve("generated-kimi.toml"),first,StandardOpenOption.CREATE_NEW);
        System.out.println("GENERATED_KIMI_CONFIG="+evidence.resolve("generated-kimi.toml"));
        Files.writeString(config,first.replace("timeout = 20","timeout = 19"));check(installer.getHookStatus("Kimi")!=HookInstaller.HookStatus.LATEST,"Kimi wrong timeout is not latest");
        check(installer.installOrUpdate("Kimi").success(),"repair incorrect registered timeout");
        installer.uninstall("Kimi");check(Files.readString(config).contains(foreign)&&!Files.readString(config).contains("KimiPreToolUse"),"Kimi removal preserves foreign TOML");
        Files.writeString(config,"hooks = []\n# untouched\n[other]\nvalue='keep'\n");
        check(installer.installOrUpdate("Kimi").success()&&Files.readString(config).contains("# untouched\n[other]\nvalue='keep'"),"initial empty hook array can be installed safely");
        String invalid="[[hooks]]\nevent='PermissionRequest'\ncommand='foreign-command'\n";Files.writeString(config,invalid);
        check(!installer.installOrUpdate("Kimi").success()&&Files.readString(config).equals(invalid),"invalid foreign Kimi event is reported, never deleted");
        installer.version="9.0.0";check(installer.getHookStatus("Kimi")==HookInstaller.HookStatus.UNSUPPORTED&&!installer.installOrUpdate("Kimi").success(),"unknown Kimi capability cannot be certified or installed");
    }
    public static void main(String[] args)throws Exception {
        Path home=Files.createTempDirectory("wd007-hook-management-");System.setProperty("user.home",home.toString());
        Installed installer=new Installed();
        Path canonical=home.resolve(".claude/settings.json");Files.createDirectories(canonical.getParent());
        String mixed="{\"keep\":42,\"hooks\":{\"PreToolUse\":[{\"matcher\":\"Bash\",\"hooks\":[{\"type\":\"command\",\"command\":\"foreign-command\"},{\"type\":\"command\",\"command\":\"powershell -File \\\""+home.resolve(".ahakey/hooks/ahakey-hook.ps1").toString().replace("\\","/")+"\\\" PreToolUse\"}]}]}}";
        Files.writeString(canonical,mixed);
        Path unrelated=home.resolve(".ahakey/hooks/ahakey-kimi.ps1");Files.createDirectories(unrelated.getParent());Files.writeString(unrelated,"# another platform's custom script\n");
        for(int i=0;i<2;i++) {
            var result=installer.installOrUpdate("Claude");
            System.out.println("Claude update="+result+" status="+installer.getHookStatus("Claude"));
            check(result.success()&&installer.getHookStatus("Claude")==HookInstaller.HookStatus.LATEST,"explicit update followed by rescan must stabilize at latest");
        }
        check(installer.getHookConfigPath("Claude").equals(canonical),"Claude uses actual settings entry");
        var json=new ObjectMapper().readTree(Files.readString(canonical));
        check(json.path("keep").asInt()==42&&json.toString().contains("foreign-command"),"mixed wrapper preserves unrelated command and configuration");
        check(!json.toString().contains("ahakey-hook.ps1"),"legacy owned wrapper migrated");
        check(Files.readString(unrelated).equals("# another platform's custom script\n"),"single-platform update does not rewrite other platform scripts");
        String correct=Files.readString(canonical);
        for(String broken:List.of(correct.replace("\"matcher\" : \"\"","\"matcher\" : \"NeverMatches\""),correct.replace("\"type\" : \"command\"","\"type\" : \"prompt\""),correct.replace("\"timeout\" : 10","\"timeout\" : 1"))) {
            Files.writeString(canonical,broken);check(installer.getHookStatus("Claude")!=HookInstaller.HookStatus.LATEST,"command alone cannot certify trigger/type/timeout");
        }
        Files.writeString(canonical,correct);
        Path core=home.resolve(".ahakey/hooks/ahakey-core.ps1");Files.writeString(core,"# broken core with "+HookInstaller.AHAKEY_HOOK_VERSION);
        check(installer.getHookStatus("Claude")!=HookInstaller.HookStatus.LATEST,"version marker alone cannot certify invalid core");
        check(installer.installOrUpdate("Claude").success(),"explicit repair restores core");
        installer.uninstall("Claude");
        json=new ObjectMapper().readTree(Files.readString(canonical));
        check(json.path("keep").asInt()==42&&json.toString().contains("foreign-command")&&!json.toString().contains("ahakey-claude.ps1"),"uninstall removes only owned commands");
        Files.writeString(canonical,"{bad json");
        check(!installer.installOrUpdate("Claude").success()&&Files.readString(canonical).equals("{bad json"),"malformed user config fails without replacement");
        for(String invalid:List.of("{} trailing garbage","{} {}","{\"hooks\":{},\"hooks\":{}}")) {
            Files.writeString(canonical,invalid);
            check(!installer.installOrUpdate("Claude").success()&&Files.readString(canonical).equals(invalid),"whole JSON document must be valid and unique: "+invalid);
        }
        byte[] invalidUtf8=new byte[]{'{','"','x','"',':','"',(byte)0xff,'"','}'};Files.write(canonical,invalidUtf8);
        check(!installer.installOrUpdate("Claude").success()&&Arrays.equals(Files.readAllBytes(canonical),invalidUtf8),"invalid UTF-8 bytes never get silently replaced");
        concurrentEdits(installer,home);kimi(installer,home);
        HookInstaller absent=new HookInstaller(8765,s->{}){@Override protected Path findLauncher(String name){return null;}};
        check(absent.getHookStatus("Claude")==HookInstaller.HookStatus.CONFIG_ONLY&&!absent.installOrUpdate("Claude").success(),"configuration residue does not impersonate installed application");
        System.out.println("PASS explicit Hook update/rescan, registration, core integrity and mixed ownership");
    }
}
