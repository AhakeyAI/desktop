package com.example.ahakey.wd009;

import com.example.ahakey.service.HookInstaller;
import com.example.ahakey.view.TopBar;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Pure presentation checks; no real Hook installation, FX window, process or device. */
public final class Wd009HookUiChecks {
    private static int checks;
    private static void check(String label, boolean ok) {
        if (!ok) throw new AssertionError(label);
        checks++;
        System.out.println("PASS " + label);
    }
    public static void main(String[] args) throws Exception {
        Method targets = TopBar.class.getDeclaredMethod("hookWriteTargets", Map.class);
        Method summary = TopBar.class.getDeclaredMethod("hookWriteSummary", Map.class);
        targets.setAccessible(true); summary.setAccessible(true);
        Map<String, HookInstaller.HookStatus> states = new LinkedHashMap<>();
        states.put("Claude", HookInstaller.HookStatus.APP_NOT_FOUND);
        states.put("Cursor", HookInstaller.HookStatus.LATEST);
        states.put("Codex", HookInstaller.HookStatus.OUTDATED);
        states.put("Kimi", HookInstaller.HookStatus.NOT_INSTALLED);
        check("batch only selects outdated platforms and excludes uninstalled hooks", targets.invoke(null, states).equals(List.of("Codex")));
        states.put("Codex", HookInstaller.HookStatus.ERROR);
        states.put("Kimi", HookInstaller.HookStatus.DETECTING);
        check("errors and in-progress scans cannot trigger writes", ((List<?>) targets.invoke(null, states)).isEmpty());
        check("empty scan cannot trigger writes", ((List<?>) targets.invoke(null, Map.of())).isEmpty());

        Map<String, HookInstaller.HookWriteResult> results = new LinkedHashMap<>();
        results.put("Cursor", new HookInstaller.HookWriteResult(true, "写后回读一致"));
        results.put("Codex", new HookInstaller.HookWriteResult(false, "配置解析失败：hooks.json 结构不合法"));
        String rendered = (String) summary.invoke(null, results);
        check("batch success includes exact platform and verified result", rendered.contains("Cursor：成功；写后回读一致"));
        check("batch failure includes concrete platform and cause", rendered.contains("Codex：失败；配置解析失败：hooks.json 结构不合法"));
        check("partial failure does not hide successful platforms", rendered.split("\n").length == 2);
        check("result rendering does not replace cause with administrator message", !rendered.contains("联系管理员"));
        check("result order remains deterministic", rendered.indexOf("Cursor") < rendered.indexOf("Codex"));
        results.clear(); results.put("Kimi", new HookInstaller.HookWriteResult(false, null));
        check("null reason does not render literal null", summary.invoke(null, results).equals("Kimi：失败"));

        Path root = Path.of(System.getProperty("ahakey.test.sourceRoot", "."));
        String source = Files.readString(root.resolve("src/main/java/com/example/ahakey/view/TopBar.java")).replace("\r\n", "\n");
        String manager = source.substring(source.indexOf("    private void showHookManagerDialog()"), source.indexOf("    private Label hookNote("));
        String card = source.substring(source.indexOf("    private void updateHookManagerCard("), source.indexOf("    private void runHookWrites("));
        String writer = source.substring(source.indexOf("    private void runHookWrites("), source.indexOf("    static List<String> hookWriteTargets("));
        check("automatic summary method and memory flag removed", !source.contains("showHookUpdateSummary") && !source.contains("hookUpdateSummaryShown"));
        check("opening manager and rescans create no nested alert/dialog", !manager.contains("new Alert") && !manager.contains("new javafx.scene.control.Dialog"));
        check("scan requests concrete inspection result", manager.contains("hookInstaller.inspectHook(name)"));
        check("scan IO is dispatched before FX rendering callback", manager.indexOf("Thread thread = new Thread") < manager.indexOf("hookInstaller.inspectHook(name)")
                && manager.indexOf("hookInstaller.inspectHook(name)") < manager.indexOf("Platform.runLater"));
        check("unexpected scan exception is shown as error", manager.contains("HookInstaller.HookStatus.ERROR") && manager.contains("hookFailureReason(ex)"));
        check("each card displays service inspection reason", card.contains("hookNote(inspection.reason())"));
        check("single action is explicitly user initiated", card.contains("action.setOnAction(event -> runHookWrites(List.of(hookName)"));
        check("batch action is explicitly user initiated", manager.contains("updateAll.setOnAction") && manager.contains("runHookWrites(targets"));
        check("scan cannot initiate a write", !manager.substring(manager.indexOf("rescan[0] ="), manager.indexOf("refresh.setOnAction")).contains("installOrUpdate"));
        check("write IO is background before FX result delivery", writer.indexOf("Thread worker = new Thread") < writer.indexOf("installOrUpdateAll(selected)")
                && writer.indexOf("installOrUpdateAll(selected)") < writer.indexOf("Platform.runLater"));
        check("writes snapshot target selection", writer.contains("List.copyOf(targets)"));
        check("results survive automatic card re-read", writer.indexOf("writeResults.setText(summary)") < writer.indexOf("rescan.run()"));
        check("duplicate manager opening reuses visible window", manager.contains("hookManagerWindow.isShowing()") && manager.contains("hookManagerWindow.toFront()"));
        check("update and scan buttons disabled during background operation", manager.contains("updateAll.disableProperty().bind(hookDialogBusy)")
                && manager.contains("refresh.disableProperty().bind(hookDialogBusy)"));
        System.out.println("WD009 Hook UI checks passed: " + checks + " (rendered UI and real user Hook writes not executed)");
    }
}
