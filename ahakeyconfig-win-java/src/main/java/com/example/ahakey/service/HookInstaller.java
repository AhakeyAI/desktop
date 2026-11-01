package com.example.ahakey.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.*;
import java.io.IOException;
import java.util.function.Consumer;
import java.util.function.IntSupplier;

/**
 * Hook 安装器 - 独立于 UI 的 Hook 管理服务
 * 负责所有平台（Claude、Cursor、Codex、Kimi）的 Hook 安装、卸载和脚本生成
 */
public class HookInstaller {

    private final IntSupplier portSupplier;
    private final Consumer<String> logger;
    private final ObjectMapper mapper = new ObjectMapper();

    // 各平台 Hook 脚本名称
    private static final String CORE_SCRIPT_NAME   = "ahakey-core.ps1";
    private static final String CLAUDE_SCRIPT_NAME = "ahakey-claude.ps1";
    private static final String CODEX_SCRIPT_NAME  = "ahakey-codex.ps1";
    private static final String KIMI_SCRIPT_NAME   = "ahakey-kimi.ps1";
    private static final String CURSOR_SCRIPT_NAME = "ahakey-cursor.ps1";

    // Hook 配置路径常量
    public static final String CODEX_SIDECAR_NAME = ".ahakey_codex_hooks_v1";
    public static final String AHAKEY_HOOK_VERSION = "wd007-native-defer-v2";
    public enum HookStatus { DETECTING, APP_NOT_FOUND, CONFIG_ONLY, UNSUPPORTED, NOT_INSTALLED, OUTDATED, LATEST, ERROR }
    private final Map<String,String> statusDetails=new java.util.concurrent.ConcurrentHashMap<>();
    public String statusDetail(String platform){return statusDetails.getOrDefault(platform,"");}
    public record HookWriteResult(boolean success, String reason) {}
    public static final String CODEX_HOOK_BLOCK_START = "# BEGIN AhaKey Codex Hooks";
    public static final String CODEX_HOOK_BLOCK_END = "# END AhaKey Codex Hooks";
    public static final String KIMI_HOOK_BLOCK_START = "# BEGIN AhaKey Kimi Hooks";
    public static final String KIMI_HOOK_BLOCK_END = "# END AhaKey Kimi Hooks";

    // Claude: 9 个事件
    private static final String[][] CLAUDE_EVENTS = {
        {"SessionStart", "10"}, {"SessionEnd", "10"}, {"PreToolUse", "10"},
        {"PostToolUse", "10"}, {"PermissionRequest", "60"}, {"Notification", "10"},
        {"TaskCompleted", "10"}, {"Stop", "10"}, {"UserPromptSubmit", "10"}
    };

    // Cursor lifecycle events retain native approval; preToolUse alone is not evidence of waiting.
    private static final String[][] CURSOR_EVENTS = {
        {"sessionStart", "10"}, {"sessionEnd", "10"}, {"preToolUse", "120"},
        {"postToolUse", "10"}, {"stop", "10"}
    };

    // Codex: 6 个事件（与 Python CODEX_HOOK_EVENTS 完全一致）
    private static final String[][] CODEX_EVENTS = {
        {"SessionStart", "CodexSessionStart", "10"},
        {"SessionEnd", "CodexSessionEnd", "10"},
        {"PostToolUse", "CodexPostToolUse", "10"},
        {"PreToolUse", "CodexPreToolUse", "20"},
        {"PermissionRequest", "CodexPermissionRequest", "20"},
        {"TaskCompleted", "CodexTaskCompleted", "10"},
        {"UserPromptSubmit", "CodexUserPromptSubmit", "10"},
        {"Stop", "CodexStop", "10"}
    };

    // Kimi: 7 个事件（与 TopBar.java 及 HookDispatchServer.java 保持一致）
    // 第一列：标准事件名（写入 Kimi 配置文件，必须是 Kimi CLI 支持的值）
    // 第二列：内部事件名（传递给 HookDispatchServer，用于映射到 IDEState）
    private static final String[][] KIMI_EVENTS = {
        {"Notification", "KimiNotification", "10"},
        {"SessionStart", "KimiSessionStart", "10"},
        {"SessionEnd", "KimiSessionEnd", "10"},
        {"PreToolUse", "KimiPreToolUse", "20"},
        {"PostToolUse", "KimiPostToolUse", "10"},
        {"UserPromptSubmit", "KimiUserPromptSubmit", "10"},
        {"Stop", "KimiStop", "10"}
    };

    public HookInstaller(int dispatchPort, Consumer<String> logger) {
        this(() -> dispatchPort, logger);
    }

    public HookInstaller(IntSupplier portSupplier, Consumer<String> logger) {
        this.portSupplier = portSupplier;
        this.logger = logger;
    }

    /** Only exact prior generated wrappers are migrated. User edits and all platform configuration stay untouched. */
    public void migrateOwnedApprovalScripts() {
        Path hooks=Paths.get(System.getProperty("user.home"),".ahakey","hooks");
        if(!Files.isDirectory(hooks))return;
        String[] names={CLAUDE_SCRIPT_NAME,CODEX_SCRIPT_NAME};
        String[] known={"0d90c6a7e5fc68e97efb6cec57fda74cafba2699b351003663ff9ea1a37f9c30","aa5c340af397050f746d977a02ab8c4cf58b42c9d4bf4cd5dcd548835ee56075"};
        for(int i=0;i<names.length;i++) {
            Path file=hooks.resolve(names[i]);Path staging=null;
            try {
                if(!Files.isRegularFile(file) || Files.isSymbolicLink(file))continue;
                byte[] before=Files.readAllBytes(file);
                String hash=java.util.HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(before));
                if(!hash.equals(known[i]))continue;
                staging=Files.createTempDirectory(hooks,"approval-migration-");
                if(i==0)generateClaudeScript(staging);else generateCodexScript(staging);
                if(!Arrays.equals(before,Files.readAllBytes(file)))throw new java.io.IOException("Hook changed during migration");
                Files.write(hooks.resolve(names[i]+".wd007-"+java.util.UUID.randomUUID()+".bak"),before,java.nio.file.StandardOpenOption.CREATE_NEW);
                Files.move(staging.resolve(names[i]),file,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);
                log("已备份并迁移自有审批脚本："+names[i]);
            } catch(Exception failure){log("审批脚本未迁移："+names[i]+"，"+failure.getMessage());}
            finally{if(staging!=null)try{Files.deleteIfExists(staging.resolve(names[i]));Files.deleteIfExists(staging);}catch(Exception ignored){}}
        }
    }

    private int currentPort() {
        return portSupplier.getAsInt();
    }

    /**
     * 生成所有 Hook 脚本（core + 各平台专属）
     */
    public void generateAllScripts() {
        String home = System.getProperty("user.home");
        Path hooksDir = Paths.get(home, ".ahakey", "hooks");
        try {
            Files.createDirectories(hooksDir);
            generateCoreScript(hooksDir);
            generateClaudeScript(hooksDir);
            generateCodexScript(hooksDir);
            generateKimiScript(hooksDir);
            generateCursorScript(hooksDir);
            log("[安装] 已生成所有 Hook 脚本");
        } catch (Exception e) {
            log("[警告] 生成 Hook 脚本失败: " + e.getMessage());
        }
    }

    /**
     * 安装指定平台的 Hook
     */
    public void install(String platform) {
        installOrUpdate(platform);
    }

    public HookWriteResult installOrUpdate(String platform) {
        log("[安装] 开始安装 " + platform + " Hook...");
        try {
            if(!isAppDetected(platform))return new HookWriteResult(false,"未检测到应用启动入口；配置目录本身不能证明应用已安装。");
            if(platform.equals("Kimi")&&!kimiSupported())return new HookWriteResult(false,statusDetail(platform));
            if(getHookStatus(platform)==HookStatus.LATEST)return new HookWriteResult(true,"脚本与注册已是最新，无需重复写入；客户端需重新加载配置。");
            Map<Path,PlannedFile> plan=configurationPlan(platform,false);
            Path scripts=scriptsDirectory();
            plan.put(scripts.resolve(CORE_SCRIPT_NAME),planned(scripts.resolve(CORE_SCRIPT_NAME),coreScript()));
            plan.put(scripts.resolve(scriptName(platform)),planned(scripts.resolve(scriptName(platform)),scriptContent(platform)));
            applyPlan(plan);
            HookStatus after=getHookStatus(platform);
            if(after!=HookStatus.LATEST)return new HookWriteResult(false,"文件已备份并写入，但重检未就绪："+statusDetail(platform));
            return new HookWriteResult(true,"已更新并验证脚本与注册；请重启对应客户端使配置生效。"+(platform.equals("Kimi")?"生命周期 Hook 已就绪；独立拨轮审批适配未在此项验证。":""));
        } catch (Exception e) {
            String reason = classifyFailure(e)+"："+(e.getMessage()==null?"请检查配置文件":e.getMessage());
            log("[错误] " + platform + " 安装失败: " + reason + " - " + e.getMessage());
            return new HookWriteResult(false, reason);
        }
    }

    /**
     * 卸载指定平台的 Hook
     */
    public void uninstall(String platform) {
        try{applyPlan(configurationPlan(platform,true));log("已移除 "+platform+" 的 AhaKey 注册，其他 Hook 保留。");}
        catch(Exception failure){log("卸载未完成："+failure.getMessage());}
    }

    /**
     * 检查指定平台的 Hook 是否已安装
     */
    public boolean isInstalled(String platform) {
        try {
            String text=readOptional(getHookConfigPath(platform));
            HookConfigEditor editor=new HookConfigEditor(scriptsDirectory());
            return platform.equals("Kimi")?editor.kimiRegistered(text,expectedCommands(platform))
                    :editor.jsonRegistered(text,platform,registrations(platform),!platform.equals("Cursor"));
        }catch(Exception invalid){return false;}
    }

    public HookStatus getHookStatus(String platform) {
        try {
            statusDetails.remove(platform);
            if (!isAppDetected(platform)) {
                boolean trace=Files.exists(getHookConfigPath(platform))||Files.isDirectory(getHookConfigPath(platform).getParent());
                statusDetails.put(platform,trace?"仅发现配置痕迹，未检测到应用启动入口；不会据此安装 Hook。":"未检测到应用启动入口，请先安装对应应用后重新检测。");
                return trace?HookStatus.CONFIG_ONLY:HookStatus.APP_NOT_FOUND;
            }
            if(platform.equals("Kimi")&&!kimiSupported())return HookStatus.UNSUPPORTED;
            Path config=getHookConfigPath(platform);String text=readOptional(config);
            HookConfigEditor editor=new HookConfigEditor(scriptsDirectory());
            boolean registered;
            if(platform.equals("Kimi")) {
                editor.mergeKimi(text,""); // Reject invalid unrelated entries; owned obsolete events remain repairable.
                try{registered=editor.kimiRegistered(text,expectedCommands(platform));}catch(IOException obsolete){registered=false;}
            } else registered=editor.jsonRegistered(text,platform,registrations(platform),!platform.equals("Cursor"));
            boolean scripts=readOptional(scriptsDirectory().resolve(scriptName(platform))).replace("\r\n","\n").equals(scriptContent(platform))
                    &&readOptional(scriptsDirectory().resolve(CORE_SCRIPT_NAME)).replace("\r\n","\n").equals(coreScript());
            if(platform.equals("Codex"))registered&=HookConfigEditor.codexEnabled(readOptional(config.resolveSibling("config.toml")));
            statusDetails.put(platform,registered&&scripts?"脚本内容与正式配置中的事件注册一致；客户端需重新加载配置。":"脚本或正式事件注册缺失/不匹配，可显式安装或更新修复。");
            return registered&&scripts?HookStatus.LATEST:Files.exists(config)?HookStatus.OUTDATED:HookStatus.NOT_INSTALLED;
        } catch (Exception e) {
            log("[错误] 检查 " + platform + " Hook 状态失败: " + e.getMessage());
            statusDetails.put(platform,"配置检测失败："+e.getMessage()+" 请修复配置后重新检测。");
            return HookStatus.ERROR;
        }
    }

    // ==================== 脚本生成 ====================

    private Path scriptsDirectory(){return Paths.get(System.getProperty("user.home"),".ahakey","hooks");}
    private String scriptName(String platform){return switch(platform){case "Claude"->CLAUDE_SCRIPT_NAME;case "Cursor"->CURSOR_SCRIPT_NAME;case "Codex"->CODEX_SCRIPT_NAME;case "Kimi"->KIMI_SCRIPT_NAME;default->throw new IllegalArgumentException("未知平台："+platform);};}
    private String scriptContent(String platform){return switch(platform){case "Claude"->claudeScript();case "Cursor"->cursorScript();case "Codex"->codexScript();case "Kimi"->kimiScript();default->throw new IllegalArgumentException("未知平台："+platform);};}
    private String[][] events(String platform){return switch(platform){case "Claude"->CLAUDE_EVENTS;case "Cursor"->CURSOR_EVENTS;case "Codex"->CODEX_EVENTS;case "Kimi"->KIMI_EVENTS;default->throw new IllegalArgumentException("未知平台："+platform);};}
    private Map<String,String> expectedCommands(String platform) {
        Map<String,String> commands=new LinkedHashMap<>();
        for(String[] event:events(platform))commands.put(event[0],buildHookCommand(scriptName(platform),event.length==3?event[1]:event[0]));
        return commands;
    }
    private static String readOptional(Path path)throws IOException{return Files.exists(path)?Files.readString(path):"";}
    private Map<String,ObjectNode> registrations(String platform) {
            Map<String,ObjectNode> replacements=new LinkedHashMap<>();
            for(String[] event:events(platform)) {
                ObjectNode command=mapper.createObjectNode();command.put("command",expectedCommands(platform).get(event[0]));
                command.put("timeout",Integer.parseInt(event[event.length-1]));
                if(platform.equals("Cursor"))replacements.put(event[0],command);
                else {
                    command.put("type","command");ObjectNode group=mapper.createObjectNode();
                    if(platform.equals("Claude"))group.put("matcher","");
                    else if(event[0].equals("SessionStart"))group.put("matcher","startup|resume|clear");
                    else if(!event[0].equals("Stop")&&!event[0].equals("UserPromptSubmit"))group.put("matcher","*");
                    group.set("hooks",mapper.createArrayNode().add(command));replacements.put(event[0],group);
                }
            }
        return replacements;
    }
    private record PlannedFile(byte[] before,byte[] after) {}
    private static byte[] readBytes(Path path)throws IOException{return Files.exists(path)?Files.readAllBytes(path):null;}
    private static String decode(byte[] bytes)throws IOException{return bytes==null?"":java.nio.charset.StandardCharsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(bytes)).toString();}
    private static PlannedFile planned(Path path,String next)throws IOException{return new PlannedFile(readBytes(path),next.getBytes(java.nio.charset.StandardCharsets.UTF_8));}
    private Map<Path,PlannedFile> configurationPlan(String platform,boolean remove)throws Exception {
        Path path=getHookConfigPath(platform);byte[] original=readBytes(path);String existing=decode(original);String next;
        HookConfigEditor editor=new HookConfigEditor(scriptsDirectory());Map<Path,PlannedFile> plan=new LinkedHashMap<>();
        if(platform.equals("Kimi"))next=editor.mergeKimi(existing,remove?"":buildKimiHookBlock());
        else {
            Map<String,ObjectNode> replacements=remove?Map.of():registrations(platform);
            ObjectNode root=editor.mergeJson(existing,platform,replacements,!platform.equals("Cursor"));
            if(platform.equals("Cursor")&&!remove)root.put("version",1);
            next=mapper.writerWithDefaultPrettyPrinter().writeValueAsString(root)+"\n";
        }
        plan.put(path,new PlannedFile(original,next.getBytes(java.nio.charset.StandardCharsets.UTF_8)));
        if(platform.equals("Codex")&&!remove) {
            Path toml=path.resolveSibling("config.toml");
            byte[] oldToml=readBytes(toml);
            plan.put(toml,new PlannedFile(oldToml,HookConfigEditor.enableCodex(decode(oldToml)).getBytes(java.nio.charset.StandardCharsets.UTF_8)));
            Path sidecar=path.resolveSibling(CODEX_SIDECAR_NAME);plan.put(sidecar,planned(sidecar,AHAKEY_HOOK_VERSION+"\n"));
        }
        return plan;
    }
    private static void atomicWrite(Path path,byte[] bytes)throws IOException {
        Files.createDirectories(path.getParent());Path temporary=Files.createTempFile(path.getParent(),".ahakey-write-",".tmp");
        try {
            Files.write(temporary,bytes);
            try{Files.move(temporary,path,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);}
            catch(java.nio.file.AtomicMoveNotSupportedException unsupported){Files.move(temporary,path,StandardCopyOption.REPLACE_EXISTING);}
        }finally{Files.deleteIfExists(temporary);}
    }
    private void applyPlan(Map<Path,PlannedFile> plan)throws IOException {
        List<Path> written=new ArrayList<>();
        // Validate and back up every existing input before replacing any of them.
        for(Path path:plan.keySet()) {
            if(Files.isSymbolicLink(path))throw new IOException("不覆盖符号链接："+path.getFileName());
            byte[] bytes=readBytes(path);
            if(!Arrays.equals(bytes,plan.get(path).before()))throw new IOException("配置在生成更新方案后已被其他程序更改："+path.getFileName());
            if(bytes!=null&&!Arrays.equals(bytes,plan.get(path).after()))Files.write(path.resolveSibling(path.getFileName()+".ahakey-"+UUID.randomUUID()+".bak"),bytes,java.nio.file.StandardOpenOption.CREATE_NEW);
        }
        try {
            for(var entry:plan.entrySet()) {
                Path path=entry.getKey();byte[] current=Files.exists(path)?Files.readAllBytes(path):null;
                if(!Arrays.equals(entry.getValue().before(),current))throw new IOException("配置在更新期间已被其他程序更改："+path.getFileName());
                if(!Arrays.equals(current,entry.getValue().after())){atomicWrite(path,entry.getValue().after());written.add(path);}
            }
        }catch(IOException failure) {
            Collections.reverse(written);
            for(Path path:written)try {
                if(!Arrays.equals(Files.readAllBytes(path),plan.get(path).after()))throw new IOException("回滚前文件已被其他程序更改");
                if(plan.get(path).before()==null)Files.delete(path);else atomicWrite(path,plan.get(path).before());
            }catch(IOException rollback){failure.addSuppressed(rollback);log("更新未完成，请使用保留备份恢复 "+path.getFileName()+"："+rollback.getMessage());}
            throw failure;
        }
    }

    private void generateCoreScript(Path hooksDir) throws Exception {
        Files.writeString(hooksDir.resolve(CORE_SCRIPT_NAME), coreScript());
    }

    private String coreScript() {
        String content =
            "# AhaKey Core - Auto-generated, do not edit\n" +
            "# ahakey-hook-version: " + AHAKEY_HOOK_VERSION + "\n" +
            "# Contains TCP connection logic, to be dot-sourced by platform-specific scripts\n" +
            "try {\n" +
            "    $stdinText = $null\n" +
            "    if ([Console]::IsInputRedirected) { $stdinText = [Console]::In.ReadToEnd() }\n" +
            "} catch { }\n" +
            "$payload = [ordered]@{ cmd = $EventName; ahakeyHookVersion = '" + AHAKEY_HOOK_VERSION + "'; cwd = (Get-Location).Path }\n" +
            "function Add-AhaKeyField([string]$Name) {\n" +
            "    $m = [regex]::Match($stdinText, '\"' + $Name + '\"\\s*:\\s*\"([^\"]*)\"')\n" +
            "    if ($m.Success) { $payload[$Name] = $m.Groups[1].Value }\n" +
            "}\n" +
            "if ($stdinText -and $stdinText.Trim().Length -gt 0) {\n" +
            "    try { $payload.hookInput = ($stdinText | ConvertFrom-Json) } catch {\n" +
            "        Add-AhaKeyField 'conversation_id'\n" +
            "        Add-AhaKeyField 'conversationId'\n" +
            "        Add-AhaKeyField 'session_id'\n" +
            "        Add-AhaKeyField 'sessionId'\n" +
            "        Add-AhaKeyField 'composerId'\n" +
            "        Add-AhaKeyField 'composer_id'\n" +
            "        Add-AhaKeyField 'transcript_path'\n" +
            "        Add-AhaKeyField 'transcriptPath'\n" +
            "        $payload.hookInputRawBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($stdinText))\n" +
            "    }\n" +
            "}\n" +
            "$jsonLine = ($payload | ConvertTo-Json -Depth 20 -Compress)\n" +
            "try {\n" +
            "    $tcp = New-Object System.Net.Sockets.TcpClient\n" +
            "    $tcp.Connect('127.0.0.1', " + currentPort() + ")\n" +
            "    $writer = New-Object System.IO.StreamWriter($tcp.GetStream())\n" +
            "    $writer.WriteLine($jsonLine)\n" +
            "    $writer.Flush()\n" +
            "    $reader = New-Object System.IO.StreamReader($tcp.GetStream())\n" +
            "    $response = $reader.ReadLine()\n" +
            "    $tcp.Close()\n" +
            "} catch {\n" +
            "    $response = $null\n" +
            "}\n";
        return content;
    }

    private void generateClaudeScript(Path hooksDir) throws Exception {
        Files.writeString(hooksDir.resolve(CLAUDE_SCRIPT_NAME), claudeScript());
    }

    private String claudeScript() {
        String content =
            "# AhaKey Claude Hook - Auto-generated, do not edit\n" +
            "# ahakey-hook-version: " + AHAKEY_HOOK_VERSION + "\n" +
            "param([Parameter(Position=0)][string]$EventName)\n" +
            ". (Join-Path $env:USERPROFILE '.ahakey\\hooks\\ahakey-core.ps1')\n" +
            "# Claude PermissionRequest: output hookSpecificOutput in Claude format\n" +
            "if ($EventName -eq 'PermissionRequest') {\n" +
            "    $isAuto = $response -match '\"autoApproved\"\\s*:\\s*true'\n" +
            "    if ($isAuto) {\n" +
            "        [Console]::WriteLine('{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"allow\"}}}')\n" +
            "    } else {\n" +
            "        [Console]::WriteLine('{}')\n" +
            "    }\n" +
            "    exit 0\n" +
            "}\n" +
            "# Claude lifecycle events: pass through server response\n" +
            "if ($response) { [Console]::WriteLine($response) } else { [Console]::WriteLine('{\"ok\":true}') }\n" +
            "exit 0\n";
        return content;
    }

    private void generateCodexScript(Path hooksDir) throws Exception {
        Files.writeString(hooksDir.resolve(CODEX_SCRIPT_NAME), codexScript());
    }

    private String codexScript() {
        String content =
            "# AhaKey Codex Hook - Auto-generated, do not edit\n" +
            "# ahakey-hook-version: " + AHAKEY_HOOK_VERSION + "\n" +
            "param([Parameter(Position=0)][string]$EventName)\n" +
            ". (Join-Path $env:USERPROFILE '.ahakey\\hooks\\ahakey-core.ps1')\n" +
            "# Codex PreToolUse: 未确认 AUTO 时由平台自身审批\n" +
            "if ($EventName -eq 'CodexPreToolUse') {\n" +
            "    if ($response -match '\"autoApproved\"\\s*:\\s*true') {\n" +
            "        [Console]::WriteLine('{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"decision\":{\"behavior\":\"allow\"}}}')\n" +
            "    } else {\n" +
            "        [Console]::WriteLine('{}')\n" +
            "    }\n" +
            "    exit 0\n" +
            "}\n" +
            "# Codex PermissionRequest: 未确认 AUTO 时由平台自身审批\n" +
            "if ($EventName -eq 'CodexPermissionRequest') {\n" +
            "    if ($response -match '\"autoApproved\"\\s*:\\s*true') {\n" +
            "        [Console]::WriteLine('{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"allow\"}}}')\n" +
            "    } else {\n" +
            "        [Console]::WriteLine('{}')\n" +
            "    }\n" +
            "    exit 0\n" +
            "}\n" +
            "# Codex 其他 lifecycle hooks must output exactly {} (Codex validates JSON schema)\n" +
            "[Console]::WriteLine('{}')\n" +
            "exit 0\n";
        return content;
    }

    private void generateKimiScript(Path hooksDir) throws Exception {
        Files.writeString(hooksDir.resolve(KIMI_SCRIPT_NAME), kimiScript());
    }

    private String kimiScript() {
        String content =
            "# AhaKey Kimi Hook - Auto-generated, do not edit\n" +
            "# ahakey-hook-version: " + AHAKEY_HOOK_VERSION + "\n" +
            "param([Parameter(Position=0)][string]$EventName)\n" +
            ". (Join-Path $env:USERPROFILE '.ahakey\\hooks\\ahakey-core.ps1')\n" +
            "# Kimi: pass through server response (Kimi 特有格式)\n" +
            "if ($response) { [Console]::WriteLine($response) } else { [Console]::WriteLine('{\"ok\":true}') }\n" +
            "exit 0\n";
        return content;
    }

    private void generateCursorScript(Path hooksDir) throws Exception {
        Files.writeString(hooksDir.resolve(CURSOR_SCRIPT_NAME), cursorScript());
    }

    private String cursorScript() {
        String content =
            "# AhaKey Cursor Hook - Auto-generated, do not edit\n" +
            "# ahakey-hook-version: " + AHAKEY_HOOK_VERSION + "\n" +
            "param([Parameter(Position=0)][string]$EventName)\n" +
            ". (Join-Path $env:USERPROFILE '.ahakey\\hooks\\ahakey-core.ps1')\n" +
            "# Cursor: only explicit auto-approval outputs allow; otherwise Cursor keeps native behavior\n" +
            "if ($response -and $response -match '\"permission\"\\s*:\\s*\"allow\"') {\n" +
            "    [Console]::WriteLine('{\"permission\":\"allow\"}')\n" +
            "}\n" +
            "exit 0\n";
        return content;
    }

    // ==================== 辅助方法 ====================

    private String buildHookCommand(String scriptName, String agentEvent) {
        String home = System.getProperty("user.home");
        Path scriptPath = Paths.get(home, ".ahakey", "hooks", scriptName);
        String ps = scriptPath.toString().replace("\\", "/");
        return "powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File \"" + ps + "\" " + agentEvent;
    }

    public Path getHookConfigPath(String hookName) {
        String home = System.getProperty("user.home");
        return switch (hookName) {
            case "Claude" -> Paths.get(home, ".claude", "settings.json");
            case "Cursor" -> Paths.get(home, ".cursor", "hooks.json");
            case "Codex" -> Paths.get(home, ".codex", "hooks.json");
            case "Kimi" -> kimiShareDirectory().resolve("config.toml");
            default -> Paths.get(home, ".ahakey", "hooks", "ahakey-" + hookName.toLowerCase() + ".ps1");
        };
    }

    public boolean isAppDetected(String hookName) {
        return findLauncher(hookName)!=null;
    }

    protected Path kimiShareDirectory() {
        String configured=System.getenv("KIMI_SHARE_DIR");
        return configured==null||configured.isBlank()?Path.of(System.getProperty("user.home"),".kimi"):Path.of(configured).toAbsolutePath().normalize();
    }
    protected Path findLauncher(String platform) {
        String name=platform.toLowerCase(Locale.ROOT);Path home=Path.of(System.getProperty("user.home"));
        List<Path> directories=new ArrayList<>(List.of(home.resolve(".local/bin"),home.resolve("AppData/Roaming/npm"),home.resolve("AppData/Local/Programs/"+name)));
        String path=System.getenv("PATH");if(path!=null)for(String directory:path.split(java.util.regex.Pattern.quote(java.io.File.pathSeparator)))try{directories.add(Path.of(directory.replace("\"","")));}catch(RuntimeException ignored){}
        for(Path directory:directories)for(String suffix:List.of(".exe",".cmd",".bat")) {
            Path candidate=directory.resolve(name+suffix);if(Files.isRegularFile(candidate))return candidate;
        }
        if(platform.equals("Cursor")) {
            for(var root:List.of(com.sun.jna.platform.win32.WinReg.HKEY_CURRENT_USER,com.sun.jna.platform.win32.WinReg.HKEY_LOCAL_MACHINE))try {
                String key="Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall";
                for(String child:com.sun.jna.platform.win32.Advapi32Util.registryGetKeys(root,key))try {
                    String item=key+"\\"+child;
                    if(!com.sun.jna.platform.win32.Advapi32Util.registryGetStringValue(root,item,"DisplayName").startsWith("Cursor"))continue;
                    Path install=Path.of(com.sun.jna.platform.win32.Advapi32Util.registryGetStringValue(root,item,"InstallLocation"));
                    for(Path candidate:List.of(install.resolve("Cursor.exe"),install.resolve("_/Cursor.exe")))if(Files.isRegularFile(candidate))return candidate;
                }catch(RuntimeException ignored){}
            }catch(RuntimeException|UnsatisfiedLinkError ignored){}
        }
        return null;
    }
    protected String kimiVersion()throws Exception {
        Path launcher=findLauncher("Kimi");
        if(launcher==null||!launcher.toString().toLowerCase(Locale.ROOT).endsWith(".exe"))return "";
        Process probe=new ProcessBuilder(launcher.toString(),"--version").redirectErrorStream(true).start();
        var output=new java.io.ByteArrayOutputStream();
        Thread reader=new Thread(()->{try(var in=probe.getInputStream()){byte[] b=new byte[1024];int n;while((n=in.read(b))!=-1){if(output.size()+n<=8192)output.write(b,0,n);}}catch(IOException ignored){}},"kimi-version-read");reader.setDaemon(true);reader.start();
        try {
            if(!probe.waitFor(4,java.util.concurrent.TimeUnit.SECONDS))return "";
            reader.join(500);if(probe.exitValue()!=0||reader.isAlive())return "";
            var version=java.util.regex.Pattern.compile("(?i)kimi(?:[- ]cli)?(?:,?\\s+version)?[, :v]+(\\d+\\.\\d+\\.\\d+)").matcher(output.toString(java.nio.charset.StandardCharsets.UTF_8));
            return version.find()?version.group(1):"";
        }finally{if(probe.isAlive())probe.destroyForcibly();}
    }
    private boolean kimiSupported()throws Exception {
        String version=kimiVersion();boolean supported=version.equals("1.44.0");
        if(!supported)statusDetails.put("Kimi","已检测启动入口，但"+(version.isBlank()?"无法确认 Kimi CLI 版本":"Kimi "+version+" 的 Hook 能力尚未确认")+"；当前仅验证 kimi-cli 1.44.0，不会写入未经确认的配置。");
        return supported;
    }

    private String classifyFailure(Exception e) {
        Throwable root = e;
        while (root.getCause() != null) {
            root = root.getCause();
        }
        String message = root.getMessage() == null ? "" : root.getMessage();
        if (root instanceof java.nio.file.AccessDeniedException || message.contains("being used by another process")) {
            return "文件不可写";
        }
        if (root instanceof com.fasterxml.jackson.core.JsonProcessingException) {
            return "配置无法读取";
        }
        if (message.contains(".bak") || message.contains("copy")) {
            return "备份失败";
        }
        return "未知错误";
    }

    private String buildKimiHookBlock() {
        StringBuilder sb = new StringBuilder();
        sb.append(KIMI_HOOK_BLOCK_START).append("\n");
        sb.append("# Managed by AhaKey. Kimi CLI hooks run this installer with Kimi* event names.\n");
        for (String[] ev : KIMI_EVENTS) {
            sb.append("\n[[hooks]]\n");
            sb.append("event = \"").append(ev[0]).append("\"\n");
            sb.append("matcher = \"\"\n");
            sb.append("command = \"").append(tomlEscape(buildHookCommand(KIMI_SCRIPT_NAME, ev[1]))).append("\"\n");
            sb.append("timeout = ").append(ev[2]).append("\n");
        }
        sb.append("\n").append(KIMI_HOOK_BLOCK_END).append("\n");
        return sb.toString();
    }

    private String tomlEscape(String s) {
        return s.replace("\\", "\\\\").replace("\"", "\\\"");
    }

    private void log(String message) {
        if (logger != null) {
            logger.accept(message);
        }
    }
}
