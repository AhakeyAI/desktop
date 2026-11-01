package com.example.ahakey.service;

import com.fasterxml.jackson.databind.*;
import com.fasterxml.jackson.databind.node.*;
import org.tomlj.*;
import java.io.IOException;
import java.nio.file.Path;
import java.util.*;
import java.util.regex.Pattern;

/** Validated edits to AhaKey-owned registrations; unrelated entries and TOML text survive. */
final class HookConfigEditor {
    private static final ObjectMapper JSON=new ObjectMapper()
            .enable(com.fasterxml.jackson.core.JsonParser.Feature.STRICT_DUPLICATE_DETECTION)
            .enable(DeserializationFeature.FAIL_ON_TRAILING_TOKENS);
    private static final Set<String> KIMI_EVENTS=Set.of("PreToolUse","PostToolUse","PostToolUseFailure",
            "UserPromptSubmit","Stop","StopFailure","SessionStart","SessionEnd","SubagentStart",
            "SubagentStop","PreCompact","PostCompact","Notification");
    private static final Pattern FILE_ARGUMENT=Pattern.compile("(?i)(?:^|\\s)-File\\s+(?:\"([^\"]+)\"|'([^']+)'|(\\S+))");
    private final Path scripts;
    HookConfigEditor(Path scripts){this.scripts=scripts.toAbsolutePath().normalize();}

    boolean owned(String command,String platform) {
        var match=FILE_ARGUMENT.matcher(command);
        if(!match.find())return false;
        String value=match.group(1)!=null?match.group(1):match.group(2)!=null?match.group(2):match.group(3);
        try {
            Path path=Path.of(value).toAbsolutePath().normalize();
            return path.equals(scripts.resolve("ahakey-"+platform.toLowerCase(Locale.ROOT)+".ps1"))
                    || path.equals(scripts.resolve("ahakey-hook.ps1"));
        }catch(RuntimeException invalid){return false;}
    }
    ObjectNode json(String text)throws IOException {
        if(text.isBlank())return JSON.createObjectNode();
        JsonNode value=JSON.readTree(stripBom(text));
        if(!(value instanceof ObjectNode root))throw new IOException("配置根必须是 JSON 对象，原文件未修改。");
        JsonNode hooks=root.get("hooks");
        if(hooks!=null&&!hooks.isObject())throw new IOException("hooks 必须是对象，原配置未修改。");
        return root;
    }
    ObjectNode mergeJson(String text,String platform,Map<String,ObjectNode> replacements,boolean nested)throws IOException {
        ObjectNode root=json(text);ObjectNode hooks=root.has("hooks")?(ObjectNode)root.get("hooks"):JSON.createObjectNode();
        for(String event:new ArrayList<>(java.util.stream.StreamSupport.stream(
                Spliterators.spliteratorUnknownSize(hooks.fieldNames(),0),false).toList())) {
            if(!hooks.get(event).isArray())throw new IOException("Hook 事件列表格式无效："+event);
            ArrayNode kept=JSON.createArrayNode();
            for(JsonNode entry:hooks.get(event)) {
                if(!entry.isObject())throw new IOException("Hook 条目格式无效："+event);
                if(!nested){if(!owned(entry.path("command").asText(""),platform))kept.add(entry);continue;}
                if(!entry.path("hooks").isArray())throw new IOException("Hook 命令列表格式无效："+event);
                ObjectNode group=((ObjectNode)entry).deepCopy();ArrayNode commands=JSON.createArrayNode();boolean removed=false;
                for(JsonNode command:entry.get("hooks")) {
                    if(owned(command.path("command").asText(""),platform))removed=true;else commands.add(command);
                }
                if(!removed||!commands.isEmpty()){group.set("hooks",commands);kept.add(group);}
            }
            if(kept.isEmpty())hooks.remove(event);else hooks.set(event,kept);
        }
        replacements.forEach((event,entry)->{
            ArrayNode array=hooks.has(event)?(ArrayNode)hooks.get(event):JSON.createArrayNode();array.add(entry);hooks.set(event,array);
        });
        if(hooks.isEmpty())root.remove("hooks");else root.set("hooks",hooks);
        return root;
    }
    boolean jsonRegistered(String text,String platform,Map<String,ObjectNode> expected,boolean nested)throws IOException {
        ObjectNode root=json(text);Map<String,List<JsonNode>> found=new HashMap<>();
        // Validate the same structure used for edits even when registrations are incomplete.
        mergeJson(text,platform,Map.of(),nested);
        if(platform.equals("Cursor")&&(!root.path("version").isIntegralNumber()||root.path("version").asInt()!=1))return false;
        var events=root.path("hooks").fields();
        while(events.hasNext()) {
            var event=events.next();
            for(JsonNode group:event.getValue())for(JsonNode item:nested?group.path("hooks"):List.of(group)) {
                String command=item.path("command").asText("");
                if(owned(command,platform)) {
                    ObjectNode registration=((ObjectNode)group).deepCopy();
                    if(nested)registration.set("hooks",JSON.createArrayNode().add(item));
                    found.computeIfAbsent(event.getKey(),x->new ArrayList<>()).add(registration);
                }
            }
        }
        return found.size()==expected.size()&&expected.entrySet().stream().allMatch(e->List.of(e.getValue()).equals(found.get(e.getKey())));
    }
    private static String stripBom(String s){return s.startsWith("\uFEFF")?s.substring(1):s;}
    private static TomlParseResult toml(String text)throws IOException {
        TomlParseResult result=Toml.parse(stripBom(text));
        if(result.hasErrors())throw new IOException("TOML 配置无法解析，原文件未修改（"+result.errors().get(0).position()+"）。");
        return result;
    }
    private static TomlArray hooks(TomlParseResult root)throws IOException {
        if(!root.contains("hooks"))return null;
        if(!root.isArray("hooks")||!root.getArray("hooks").containsTables())throw new IOException("Kimi hooks 必须是表数组。");
        return root.getArray("hooks");
    }
    String mergeKimi(String text,String replacement)throws IOException {
        var parsed=toml(text);var hooks=hooks(parsed);String[] lines=text.split("(?<=\n)",-1);Set<Integer> remove=new HashSet<>();
        if(hooks!=null&&hooks.isEmpty()&&!replacement.isEmpty()) {
            int line=parsed.inputPositionOf("hooks").line()-1;
            if(!lines[line].strip().matches("hooks\\s*=\\s*\\[\\s*]\\s*(?:#.*)?"))throw new IOException("Kimi 空 hooks 数组使用复杂表达式，原文件未修改。");
            remove.add(line);
        }
        if(hooks!=null)for(int i=0;i<hooks.size();i++) {
            TomlTable hook=hooks.getTable(i);
            if(!hook.isString("command")||!owned(hook.getString("command"),"Kimi"))continue;
            int line=hooks.inputPositionOf(i).line()-1;
            // Inline arrays/nested custom tables are deliberately not rewritten with regex.
            if(!lines[line].strip().matches("\\[\\[\\s*hooks\\s*]]\\s*(?:#.*)?"))throw new IOException("Kimi 自有 Hook 使用复杂 TOML 表达式，无法安全迁移，原文件未修改。");
            remove.add(line);
            for(String key:hook.keySet()) {
                int at=hook.inputPositionOf(key).line()-1;
                TomlParseResult single=Toml.parse(stripBom(lines[at]));
                if(single.hasErrors()||single.size()!=1||!single.contains(List.of(key))
                        ||!Objects.equals(single.get(List.of(key)),hook.get(List.of(key))))
                    throw new IOException("Kimi 自有 Hook 含多行或嵌套字段，无法安全迁移，原文件未修改。");
                remove.add(at);
            }
        }
        StringBuilder kept=new StringBuilder();
        for(int i=0;i<lines.length;i++) {
            String line=lines[i].strip();
            if(!remove.contains(i)&&!line.equals(HookInstaller.KIMI_HOOK_BLOCK_START)&&!line.equals(HookInstaller.KIMI_HOOK_BLOCK_END))kept.append(lines[i]);
        }
        String result=kept+ (kept.length()>0&&!kept.toString().endsWith("\n")?"\n":"")+replacement;
        validateKimiHooks(toml(result));return result;
    }
    private static void validateKimiHooks(TomlParseResult root)throws IOException {
        var hooks=hooks(root);if(hooks==null)return;
        for(int i=0;i<hooks.size();i++) {
            var hook=hooks.getTable(i);
            if(!hook.isString("event")||!KIMI_EVENTS.contains(hook.getString("event"))||!hook.isString("command")
                    ||(hook.contains("matcher")&&!hook.isString("matcher"))
                    ||(hook.contains("timeout")&&(!hook.isLong("timeout")||hook.getLong("timeout")<1||hook.getLong("timeout")>600)))
                throw new IOException("Kimi 1.44.0 不支持 hooks["+i+"] 的事件或字段；第三方条目未修改。");
        }
    }
    boolean kimiRegistered(String text,Map<String,String> expected)throws IOException {
        var root=toml(text);validateKimiHooks(root);var hooks=hooks(root);if(hooks==null)return false;
        Map<String,List<String>> found=new HashMap<>();
        for(int i=0;i<hooks.size();i++) {
            var hook=hooks.getTable(i);String command=hook.getString("command");
            if(owned(command,"Kimi")) {
                String event=hook.getString("event");
                if(!hook.getString("matcher",()->"").isEmpty()||hook.getLong("timeout",()->30)!=(event.equals("PreToolUse")?20:10))return false;
                found.computeIfAbsent(event,x->new ArrayList<>()).add(command);
            }
        }
        return found.size()==expected.size()&&expected.entrySet().stream().allMatch(e->List.of(e.getValue()).equals(found.get(e.getKey())));
    }
    static boolean codexEnabled(String text)throws IOException {
        var root=toml(text);return root.isBoolean("features.hooks")&&root.getBoolean("features.hooks");
    }
    static String enableCodex(String text)throws IOException {
        var root=toml(text);String[] lines=text.split("(?<=\n)",-1);
        if(root.contains("features.hooks")) {
            if(!root.isBoolean("features.hooks"))throw new IOException("Codex features.hooks 必须是布尔值。");
            if(root.getBoolean("features.hooks"))return text;
            int at=root.inputPositionOf("features.hooks").line()-1;
            if(!lines[at].strip().matches("hooks\\s*=\\s*false\\s*(?:#.*)?"))throw new IOException("Codex hooks 开关使用复杂表达式，无法安全修改。");
            lines[at]=lines[at].replaceFirst("false","true");return String.join("",lines);
        }
        if(root.contains("features")) {
            int at=root.inputPositionOf("features").line()-1;
            if(!lines[at].strip().matches("\\[features]\\s*(?:#.*)?"))throw new IOException("Codex features 使用复杂表达式，无法安全修改。");
            lines[at]=lines[at]+(lines[at].endsWith("\n")?"":"\n")+"hooks = true\n";
            return String.join("",lines);
        }
        return text+"\n[features]\nhooks = true\n";
    }
}
