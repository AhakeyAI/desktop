package com.example.ahakey.wd009;

import com.example.ahakey.service.HookInstaller;
import com.fasterxml.jackson.databind.*;
import com.fasterxml.jackson.databind.node.*;
import java.nio.file.*;
import java.util.*;
import java.io.IOException;

/** Isolated filesystem checks. Never points at the actual user's Hook directories. */
public class HookManagementChecks {
    private static int checks;
    private static Path root, home;
    private static final ObjectMapper JSON = new ObjectMapper();
    private static final List<String> PLATFORMS = List.of("Claude", "Cursor", "Codex", "Kimi");
    private static HookInstaller installer;
    private static final List<String> messages = new ArrayList<>();
    private static void ok(boolean value, String label) { checks++; if (!value) throw new AssertionError(label); }
    private static void fixture(String name) throws Exception {
        home = root.resolve(name); Files.createDirectories(home); System.setProperty("user.home", home.toString());
        for (String dir : List.of(".claude", ".cursor", ".codex", ".config/kimi-cli")) Files.createDirectories(home.resolve(dir));
        messages.clear(); installer = new HookInstaller(18999, messages::add);
    }
    private static Path script(String platform) { return home.resolve(".ahakey/hooks/ahakey-" + platform.toLowerCase() + ".ps1"); }
    private static Path config(String platform) { return platform.equals("Codex") ? home.resolve(".codex/hooks.json") : installer.getHookConfigPath(platform); }
    private static void install(String platform) { var result = installer.installOrUpdate(platform); ok(result.success(), platform + " install: " + result.reason()); }
    private static void latest(String platform) { var result = installer.inspectHook(platform); ok(result.status() == HookInstaller.HookStatus.LATEST, platform + " latest: " + result.reason()); }
    private static ObjectNode json(String platform) throws Exception { return (ObjectNode)JSON.readTree(config(platform).toFile()); }
    private static void save(String platform, ObjectNode json) throws Exception { JSON.writeValue(config(platform).toFile(), json); }
    private static void write(Path path, String value) throws Exception { Files.createDirectories(path.getParent()); Files.writeString(path,value); }
    private static Map<String,byte[]> files() throws Exception {
        Map<String,byte[]> result=new TreeMap<>(); try(var all=Files.walk(home)){ for(Path p:all.filter(Files::isRegularFile).toList())result.put(home.relativize(p).toString(),Files.readAllBytes(p)); } return result;
    }
    private static boolean same(Map<String,byte[]> a,Map<String,byte[]> b){return a.keySet().equals(b.keySet())&&a.keySet().stream().allMatch(k->Arrays.equals(a.get(k),b.get(k)));}
    private static void failureUnchanged(String platform, String text) throws Exception {
        write(config(platform),text); var before=files(); var result=installer.installOrUpdate(platform);
        ok(!result.success(),"reject malformed "+text); ok(same(before,files()),"no write before validating "+text);
        ok(installer.inspectHook(platform).status()==HookInstaller.HookStatus.ERROR,"malformed inspection ERROR");
    }
    public static void main(String[] args)throws Exception {
        root=Path.of(System.getProperty("user.home")).toAbsolutePath();
        if(!root.toString().contains("wd009-hook-r3"))throw new IllegalStateException("isolated home required");
        if(args.length>0&&args[0].equals("reopen")){installer=new HookInstaller(18999,s->{});latest("Codex");System.out.println("PASS fresh process inspection");return;}
        fixture("sidecar"); install("Codex");
        Path marker=home.resolve(".codex/"+HookInstaller.CODEX_SIDECAR_NAME);
        Files.writeString(marker,"ws3-cp1-v1");latest("Codex");ok(installer.inspectHook("Codex").reason().contains("无需"),"old marker explained");
        Files.delete(marker);latest("Codex");latest("Codex");
        var before=files();new HookInstaller(18999,s->{}).inspectHook("Codex");ok(same(before,files()),"inspection never writes");
        String core=Files.readString(script("core"));Files.writeString(script("core"),core+"\n# altered");ok(installer.getHookStatus("Codex")==HookInstaller.HookStatus.OUTDATED,"core differing despite marker");
        install("Codex");Files.delete(script("core"));ok(installer.inspectHook("Codex").reason().contains("缺少脚本"),"missing core specific");install("Codex");
        Files.writeString(script("Codex"),Files.readString(script("Codex"))+"\n# changed");ok(installer.getHookStatus("Codex")==HookInstaller.HookStatus.OUTDATED,"same marker script change");install("Codex");
        Files.writeString(script("Codex"),Files.readString(script("Codex")).replace("\n","\r\n"));latest("Codex");
        ObjectNode settings=json("Codex");ObjectNode event=(ObjectNode)settings.at("/hooks/PreToolUse/0/hooks/0");
        event.put("command",event.get("command").asText().replace('/', '\\'));save("Codex",settings);latest("Codex");
        event.put("timeout",999);save("Codex",settings);ok(installer.getHookStatus("Codex")==HookInstaller.HookStatus.OUTDATED,"timeout mismatch");install("Codex");
        settings=json("Codex");((ObjectNode)settings.get("hooks")).remove("Stop");save("Codex",settings);ok(installer.getHookStatus("Codex")==HookInstaller.HookStatus.OUTDATED,"missing event");install("Codex");
        ok(new HookInstaller(-1,s->{}).getHookStatus("Codex")==HookInstaller.HookStatus.ERROR,"invalid port ERROR");before=files();ok(!new HookInstaller(-1,s->{}).installOrUpdate("Codex").success(),"invalid port rejected");ok(same(before,files()),"invalid port no write");
        ok(new HookInstaller(19000,s->{}).inspectHook("Codex").reason().contains("端口"),"changed port explained");

        fixture("isolation");for(String platform:PLATFORMS)install(platform);
        Map<String,byte[]> untouched=new TreeMap<>();for(String p:List.of("Claude","Cursor","Kimi")){untouched.put(script(p).toString(),Files.readAllBytes(script(p)));untouched.put(config(p).toString(),Files.readAllBytes(config(p)));}
        Files.writeString(script("Codex"),"old");install("Codex");for(var e:untouched.entrySet())ok(Arrays.equals(e.getValue(),Files.readAllBytes(Path.of(e.getKey()))),"other platform unchanged");
        Path corePath=script("core");var coreTime=Files.getLastModifiedTime(corePath);install("Codex");ok(coreTime.equals(Files.getLastModifiedTime(corePath)),"matching shared core not rewritten");
        ok(java.util.HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(script("Claude")))).equals("a868a87ca280a7a0556269bc3a9d2a0b89c2bd4b29a8f68e2ae150722231f3e4"),"R2 generated bytes unchanged Claude");
        ok(java.util.HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(script("Cursor")))).equals("64d48ca9ad345eacac5046d85127078ece773373f0155c3a0f1b797e3e908937"),"R2 generated bytes unchanged Cursor");
        ok(java.util.HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(script("Codex")))).equals("72289eea88653de29c2c3c070b87fc8b0c789abbba6060c46646f54369b59cbf"),"R2 generated bytes unchanged Codex");
        ok(java.util.HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(script("Kimi")))).equals("4d9a4c9ab3a82ccbc17b3b8d438be5e9a488ce55603e584925a47ad6582c46c9"),"R2 generated bytes unchanged Kimi");
        ok(java.util.HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(script("core")))).equals("788dc150ce3b38c4e123490f39dfb469312fe4dbb2159c279cef47c7f26c8c3b"),"R2 generated bytes unchanged core");


        fixture("mixed");install("Codex");settings=json("Codex");ObjectNode wrapper=(ObjectNode)settings.at("/hooks/PreToolUse/0");wrapper.put("thirdPartyMetadata","keep");
        ArrayNode commands=(ArrayNode)wrapper.get("hooks");commands.addObject().put("command","echo ahakey-codex.ps1 ahakey-other");commands.addObject().put("command","powershell -File D:/Other/ahakey-codex.ps1 PreToolUse");
        save("Codex",settings);install("Codex");settings=json("Codex");JsonNode kept=settings.at("/hooks/PreToolUse/0");ok(kept.path("thirdPartyMetadata").asText().equals("keep"),"wrapper metadata retained");ok(kept.path("hooks").size()==2,"both thirdparty commands retained");latest("Codex");
        long backupCount;try(var paths=Files.list(config("Codex").getParent())){backupCount=paths.filter(p->p.toString().endsWith(".bak")).count();}ok(backupCount>0,"unique backups created");
        String invalid="{\"hooks\":{},\"hooks\":{}}";failureUnchanged("Codex",invalid);failureUnchanged("Codex","{} {}");failureUnchanged("Codex","[]");failureUnchanged("Codex","{");failureUnchanged("Codex","{\"hooks\":[]}");failureUnchanged("Codex","{\"hooks\":{\"Stop\":{}}}");failureUnchanged("Codex","{\"hooks\":{\"Stop\":[{\"hooks\":false}]}}");failureUnchanged("Cursor","{\"hooks\":{\"stop\":[1]}}");

        fixture("toml");String original="# hooks appears in comment\r\n[other]\r\nhooks = false\r\nnotify = [\r\n  \"cmd\", # item\r\n  \"arg\"\r\n]\r\ntext = '''\r\n[features]\r\nhooks = false\r\n'''\r\n[features] # enabled features\r\nhooks = false # intentional\r\n[after]\r\nname = \"value\"\r\n";
        Path toml=home.resolve(".codex/config.toml");write(toml,original);install("Codex");String changed=Files.readString(toml);ok(changed.equals(original.replace("hooks = false # intentional","hooks = true # intentional")),"only exact features key changed; multiline preserved");latest("Codex");
        write(toml,"[other]\nhooks = false\n[features]\nother = true\n[after]\nx = 1\n");install("Codex");ok(Files.readString(toml).contains("[features]\nhooks = true\nother = true\n[after]"),"features key inserted in correct section");ok(Files.readString(toml).contains("[other]\nhooks = false"),"unrelated hooks left false");
        for(String supported:List.of(
            "model_providers.\"local-dev\".base_url = \"http://localhost\"\n[features]\nhooks = false\n",
            "features.hooks = false\n", "features = { hooks = false, foo = 1 }\n",
            "features = { foo = 1 }\n", "features = {}\n", "features.foo = 1\n", "[features.child]\nx=1\n",
            "['features']\n'hooks' = false # comment\n", "[ features ]\nfoo = 1\n")) {
            write(toml,supported);install("Codex");latest("Codex");
            ok(Boolean.TRUE.equals(org.tomlj.Toml.parse(Files.readString(toml)).get("features.hooks")),"TOML semantic hooks true");
        }
        for(String bad:List.of("[features]\nhooks = false\nhooks = true\n","[features\nhooks = false\n","[features]\nhooks = maybe\n","x = [\n", "x = \"unterminated\n", "x =\n", "[features]\nhooks=true\n\"hooks\"=false\n", "x=[1 2]\n")){write(toml,bad);before=files();ok(!installer.installOrUpdate("Codex").success(),"bad TOML rejected");ok(same(before,files()),"bad TOML untouched");}

        fixture("kimi");String prefix="# user heading\n[custom]\nvalue = 5\n\n";write(config("Kimi"),prefix);install("Kimi");String first=Files.readString(config("Kimi"));ok(first.startsWith(prefix),"Kimi prefix exact");String suffix="\n# user suffix\n[tail]\nvalue = 2\n";Files.writeString(config("Kimi"),first+suffix);install("Kimi");ok(Files.readString(config("Kimi")).endsWith(suffix),"Kimi suffix exact");latest("Kimi");
        write(config("Kimi"),prefix+HookInstaller.KIMI_HOOK_BLOCK_START+"\n");before=files();ok(!installer.installOrUpdate("Kimi").success(),"partial Kimi block rejected");ok(same(before,files()),"partial Kimi unchanged");

        fixture("kimi-marker-string");String example="text = \"\"\"\n# BEGIN AhaKey Kimi Hooks\n# END AhaKey Kimi Hooks\n\"\"\"\n";write(config("Kimi"),example);install("Kimi");ok(Files.readString(config("Kimi")).startsWith(example),"marker example in multiline string untouched");latest("Kimi");

        fixture("failures");HookInstaller failing=new HookInstaller(18999,messages::add){@Override protected void writeManagedFile(Path p,byte[] b)throws Exception{throw new IOException("injected access failure");}};
        var result=failing.installOrUpdate("Cursor");ok(!result.success()&&result.reason().contains("写入"),"write failure explicit");ok(messages.stream().noneMatch(s->s.startsWith("[成功]")),"no false write success");
        messages.clear();HookInstaller corrupt=new HookInstaller(18999,messages::add){@Override protected void writeManagedFile(Path p,byte[] b)throws Exception{super.writeManagedFile(p,b);Files.writeString(p,"corrupt after write");}};
        result=corrupt.installOrUpdate("Claude");ok(!result.success()&&result.reason().contains("回读"),"readback corruption rejected");ok(messages.stream().noneMatch(s->s.startsWith("[成功]")),"no false readback success");
        fixture("batch");write(config("Cursor"),"[]");Map<String,HookInstaller.HookWriteResult> batch=installer.installOrUpdateAll(List.of("Cursor","Codex"));ok(batch.size()==2&&!batch.get("Cursor").success()&&batch.get("Codex").success(),"batch reports each and continues");latest("Codex");
        System.out.println("PASS HookManagementChecks "+checks+" assertions; no actual user Hook touched");
    }
}
