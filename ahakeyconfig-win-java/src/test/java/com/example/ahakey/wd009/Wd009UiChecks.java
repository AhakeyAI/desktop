package com.example.ahakey.wd009;

import com.example.ahakey.model.KeyConfig;
import com.example.ahakey.service.KeySimulationService;
import com.example.ahakey.update.InstalledAppIdentity;
import com.example.ahakey.view.TopBar;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

/** No native input, application launch, device I/O or user files. */
public final class Wd009UiChecks {
    private static int checks;
    private static void check(String message, boolean result) {
        if (!result) throw new AssertionError(message);
        checks++; System.out.println("PASS " + message);
    }
    private static List<String> run(KeySimulationService.Plan plan) throws Exception {
        List<String> events = new ArrayList<>();
        KeySimulationService.execute(plan, (hid, up) -> events.add((up ? "up:" : "down:") + hid),
                ms -> events.add("delay:" + ms));
        return events;
    }
    public static void main(String[] args) throws Exception {
        KeyConfig key = new KeyConfig(0x200 | 0x06, "Ctrl+C");
        var shortcut = KeySimulationService.snapshot(key);
        check("shortcut preserves Ctrl+C and release order", run(shortcut).equals(List.of("down:224", "down:6", "up:6", "up:224")));
        key.addMacroStep("DOWN_KEY", 0x04);
        key.addMacroStep("DELAY", 7);
        key.addMacroStep("UP_KEY", 0x04);
        var macro = KeySimulationService.snapshot(key);
        check("macro supersedes previous shortcut and preserves delay ticks", run(macro).equals(List.of("down:4", "delay:21", "up:4")));
        key.updateMacroStep(0, "DOWN_KEY", 0x05);
        check("snapshot cannot be changed by subsequent editor edits", run(macro).get(0).equals("down:4"));
        check("next click snapshots new draft", run(KeySimulationService.snapshot(key)).get(0).equals("down:5"));
        check("old shortcut plan is also immutable", run(shortcut).get(1).equals("down:6"));
        while (key.getMacroStepCount() > 0) key.removeMacroStep(0);
        check("deleting last macro step uses same shortcut mode as editor rebuild", !key.usesMacro()
                && run(KeySimulationService.snapshot(key)).equals(run(shortcut)));
        key = new KeyConfig(0xF000 | 0x6D, "right modifiers and F18");
        check("all right modifiers retained", run(KeySimulationService.snapshot(key)).equals(List.of("down:229", "down:228", "down:230", "down:231", "down:109", "up:109", "up:231", "up:230", "up:228", "up:229")));
        key = new KeyConfig(0x300, "modifiers only");
        check("modifier-only shortcut supported", run(KeySimulationService.snapshot(key)).equals(List.of("down:225", "down:224", "up:224", "up:225")));
        key = new KeyConfig(); key.addMacroStep("DOWN_KEY", 0xE0); key.addMacroStep("DOWN_KEY", 0x04);
        check("unbalanced macro releases all keys in finally", run(KeySimulationService.snapshot(key)).equals(List.of("down:224", "down:4", "up:4", "up:224")));
        List<String> failure = new ArrayList<>();
        try {
            KeySimulationService.execute(KeySimulationService.snapshot(key), (hid, up) -> {
                failure.add((up ? "up:" : "down:") + hid);
                if (!up && hid == 4) throw new IllegalStateException("injected");
            }, ms -> {});
            throw new AssertionError("expected failure");
        } catch (IllegalStateException expected) { check("input failure is surfaced", expected.getMessage().equals("injected")); }
        check("input failure releases even potentially partially sent key", failure.equals(List.of("down:224", "down:4", "up:4", "up:224")));
        key.addMacroStep("DELAY", 1);
        List<String> cancelled = new ArrayList<>();
        try {
            KeySimulationService.execute(KeySimulationService.snapshot(key), (hid, up) -> cancelled.add((up ? "up:" : "down:") + hid),
                    ms -> { throw new InterruptedException("cancel"); });
            throw new AssertionError("expected cancellation");
        } catch (InterruptedException expected) { check("cancellation is surfaced", true); }
        check("cancellation releases held keys", cancelled.equals(List.of("down:224", "down:4", "up:4", "up:224")));
        List<Integer> releaseAttempts = new ArrayList<>();
        try {
            KeySimulationService.execute(KeySimulationService.snapshot(key), (hid, up) -> {
                if (up) { releaseAttempts.add(hid); if (hid == 4) throw new IllegalStateException("release"); }
            }, ms -> {});
            throw new AssertionError("expected release failure");
        } catch (IllegalStateException expected) { check("release failure reported", true); }
        check("one failed release does not skip other held keys", releaseAttempts.equals(List.of(4, 224)));
        for (int code : new int[]{0, 0xFF}) {
            try { KeySimulationService.snapshot(new KeyConfig(code, "")); throw new AssertionError("invalid key accepted"); }
            catch (IllegalArgumentException expected) { check("invalid/empty snapshot rejected " + code, true); }
        }
        check("F18 maps to VK_F18, not F24", KeySimulationService.virtualKey(0x6D) == 0x81);
        check("right Ctrl uses extended flag", KeySimulationService.extendedKey(0xE4));
        check("keypad Enter uses extended flag", KeySimulationService.extendedKey(0x58));
        check("regular Enter has no extended flag", !KeySimulationService.extendedKey(0x28));
        var installed = new InstalledAppIdentity("1.0.18", "local-model", "x64", InstalledAppIdentity.PRODUCT, InstalledAppIdentity.UPGRADE_CODE, "test", true);
        check("version is from same install identity as updater", TopBar.displayApplicationVersion(installed).equals("1.0.18"));
        var missing = new InstalledAppIdentity("0.0.0", "development", "unknown", InstalledAppIdentity.PRODUCT, "", "invalid-metadata", false);
        check("missing metadata shown unknown", TopBar.displayApplicationVersion(missing).startsWith("未知"));
        check("null metadata shown unknown", TopBar.displayApplicationVersion(null).startsWith("未知"));

        java.util.List<String> released = java.util.Collections.synchronizedList(new java.util.ArrayList<>());
        var down = new java.util.concurrent.CountDownLatch(1);
        Thread worker = new Thread(() -> {
            try {
                KeySimulationService.execute(new KeySimulationService.Plan(java.util.List.of(
                    new KeySimulationService.Step("DOWN_KEY", 6), new KeySimulationService.Step("DELAY", 255))),
                    (hid, up) -> { released.add(hid + ":" + up); if (!up) down.countDown(); }, ms -> Thread.sleep(30000));
            } catch (InterruptedException expected) { }
            catch (Exception unexpected) { throw new AssertionError(unexpected); }
        });
        worker.start();
        check("exit fixture reached held key", down.await(2, java.util.concurrent.TimeUnit.SECONDS));
        check("menu exit bounded cancellation waits for key release", KeySimulationService.cancelAndAwait(worker, 1000)
                && released.equals(java.util.List.of("6:false", "6:true")));

        // Wiring checks supplement execution tests; they are not rendered UI acceptance.
        Path sourceRoot = Path.of(System.getProperty("ahakey.test.sourceRoot", "."));
        String inspector = Files.readString(sourceRoot.resolve("src/main/java/com/example/ahakey/view/InspectorPane.java")).replace("\r\n", "\n");
        String top = Files.readString(sourceRoot.resolve("src/main/java/com/example/ahakey/view/TopBar.java")).replace("\r\n", "\n");
        check("shortcut selector uses shared F18 promotion", inspector.contains("configureLocalVoiceKeyLabel(keySelector)"));
        check("macro step selector uses shared F18 promotion", inspector.contains("configureLocalVoiceKeyLabel(keyCombo)"));
        check("shared promotion is before model-only labeling", inspector.indexOf("selector.getItems().add(0, f18)") < inspector.indexOf("if (!com.example.ahakey.config.ModelConfig"));
        check("non-K1 keys expose current-draft simulation", inspector.contains("} else if (part.isKey()) {\n            body.getChildren().add(createKeyBindingGroup(part));\n            body.getChildren().add(createSimulateKeyGroup(part));"));
        check("simulate no longer calls stale HID-only voice helper", !inspector.contains("simulateKeyByHid"));
        check("snapshot is created inside click handler", inspector.indexOf("simulate.setOnAction") < inspector.indexOf("KeySimulationService.snapshot(studioState.getKeyConfig(part))"));
        check("simulation is off FX thread and cancellable", inspector.contains("simulationThread.start()") && inspector.contains("simulationThread.interrupt()"));
        check("reconnect and clear OLED menu entries removed", !top.contains("\"menu.reconnect\"") && !top.contains("\"menu.clear-oled\""));
        String menu = top.substring(top.indexOf("if (modelEnabled) {", top.indexOf("Menu moreMenu")), top.indexOf("MenuItem updateCenter"));
        check("cloud entries retain model guard and precede main menu", menu.indexOf("cloudAccount") < menu.indexOf("restoreDefaults") && menu.contains("} else {"));
        check("language and exit remain final pair in both variants", menu.split("languageMenuItem,\\s*exitApp", -1).length == 3);
        check("app version has no guessed fallback", !top.contains("version = \"1.0.0\""));
        check("unsaved switch marker reads dirty state", inspector.contains("studioState.isDirty(StudioPart.TOGGLE_SWITCH)"));
        check("legacy switch view does not equate non-auto with manual", !inspector.contains("() -> !deviceStatus.isAutoApproval()"));
        check("switch editor position uses live status, not draft position", inspector.contains("sideSwitchPhysicalLabel(deviceStatus.getSwitchState())") && !inspector.contains("sideSwitchPhysicalLabel(config.physicalPosition())"));
        check("pending editable delay is committed before snapshot", inspector.indexOf("commitSimulationEditors(body)") < inspector.indexOf("KeySimulationService.snapshot(studioState.getKeyConfig(part))"));
        check("macro deletion rebuilds editor type and visible content", inspector.contains("key.removeMacroStep(index);\n            studioState.markDirty(part);\n            rebuild();"));
        System.out.println("WD009 UI checks passed: " + checks + " (native input and device I/O not executed)");
    }
}
