package com.example.ahakey.view;

import com.example.ahakey.app.StudioController;
import com.example.ahakey.service.AgentManager;
import com.example.ahakey.util.LanguageManager;
import com.example.ahakey.util.StudioStore;
import javafx.application.Platform;
import javafx.scene.Node;
import javafx.scene.Parent;
import javafx.scene.Scene;
import javafx.scene.control.*;
import javafx.scene.image.PixelFormat;
import javafx.scene.layout.*;
import java.nio.file.*;
import java.util.List;
import java.util.stream.Stream;
import java.awt.image.BufferedImage;
import javax.imageio.ImageIO;

/** Explicit Windows/JavaFX smoke run; isolated draft, no device connection. */
public final class ShortcutEditorUiSmoke {
    private static StudioController controller;
    private static InspectorPane inspector;

    public static void main(String[] args) throws Exception {
        if (!"1".equals(System.getenv("AHAKEY_STUDIO_SIMULATE_BLE"))) {
            throw new IllegalStateException("Run with AHAKEY_STUDIO_SIMULATE_BLE=1");
        }
        Path output = Path.of(args[0]);
        Files.createDirectories(output);
        System.setProperty("user.home", Files.createTempDirectory("ahakey-ui-smoke-").toString());
        System.setProperty("ahakey.defaultLanguage", "ru");
        Platform.startup(() -> {
            try {
                controller = new StudioController();
                controller.shutdown();
                controller.getAgentManager().setBluetoothOwner(AgentManager.BluetoothOwner.AHAKEY_STUDIO);
                inspector = new InspectorPane(controller);
                var state = controller.getStudioState();
                var editor = editor();
                list(editor).getSelectionModel().select("H (0x0B)");
                button(editor, "inspector.delete").fire();
                check(state.getVoiceShortCustomShortcutHid() == 0x800, "Delete H");
                button(editor(), "inspector.clear").fire();
                check(state.getVoiceShortCustomShortcutHid() == 0, "Clear all");
                for (String key : List.of("Left Shift (0xE1)", "Left Ctrl (0xE0)", "D (0x07)")) add(key);
                check(state.getVoiceShortCustomShortcutHid() == 0x307, "Shift Ctrl D");
                add("Right Ctrl (0xE4)");
                check(list(editor()).getItems().containsAll(List.of("Left Ctrl (0xE0)", "Right Ctrl (0xE4)")),
                    "Both modifier sides visible");
                editor = editor();
                list(editor).getSelectionModel().select("Right Ctrl (0xE4)");
                button(editor, "inspector.delete").fire();
                check(state.getVoiceShortCustomShortcutHid() == 0x307, "Delete right Ctrl only");
                check(!controller.getDeviceStatus().isConnected(), "Save test must be disconnected");
                controller.finishEditingConfiguration();
                check(!controller.hasUnsyncedChanges(), "Local save clears dirty state");
                check(StudioStore.loadOrDefault().voiceShortCustomShortcutHid == 0x307, "Saved draft");
                check(state.syncStatusProperty().get().equals(LanguageManager.text("sync.local-saved")), "Success visible");
                state.setVoiceShortCustomShortcutHid(0x300);
                controller.finishEditingConfiguration();
                check(controller.hasUnsyncedChanges(), "Incomplete shortcut stays dirty");
                check(state.syncStatusProperty().get().equals(LanguageManager.text("sync.incomplete-shortcut")), "Validation visible");
                state.setVoiceShortCustomShortcutHid(0x307);
                controller.getAgentManager().setBluetoothOwner(AgentManager.BluetoothOwner.AHAKEY_STUDIO);

                TopBar top = new TopBar(controller, controller.getDeviceStatus(), state, controller.getAgentManager());
                BorderPane root = new BorderPane();
                root.getStyleClass().add("root");
                root.setTop(top);
                var canvas = new CanvasPane(controller);
                canvas.setPrefWidth(480);
                ScrollPane center = new ScrollPane(new HBox(canvas, inspector));
                center.setFitToHeight(true);
                center.setVbarPolicy(ScrollPane.ScrollBarPolicy.NEVER);
                canvas.prefWidthProperty().bind(javafx.beans.binding.Bindings.createDoubleBinding(
                    () -> Math.max(460, center.getViewportBounds().getWidth() * .52), center.viewportBoundsProperty()));
                inspector.prefWidthProperty().bind(javafx.beans.binding.Bindings.createDoubleBinding(
                    () -> Math.max(520, center.getViewportBounds().getWidth() * .48), center.viewportBoundsProperty()));
                root.setCenter(center);
                root.setBottom(new StatusBar(controller.getDeviceStatus(), state));
                Scene scene = new Scene(root, 1280, 820);
                scene.getStylesheets().add(ShortcutEditorUiSmoke.class.getResource("/style.css").toExternalForm());
                for (int width : new int[]{1024, 1280}) {
                    root.applyCss(); root.resize(width, 820); root.layout();
                    check(nodes(top).noneMatch(ScrollPane.class::isInstance), "Toolbar must not scroll horizontally");
                    for (Node node : nodes(top).filter(n -> n instanceof Button || n instanceof ToggleButton || n instanceof MenuBar).toList()) {
                        var bounds = node.localToScene(node.getLayoutBounds());
                        check(bounds.getMinX() >= 0 && bounds.getMaxX() <= width, "Toolbar control outside window: " + node);
                    }
                    var image = root.snapshot(null, null);
                    int w = (int)image.getWidth(), h = (int)image.getHeight();
                    int[] pixels = new int[w * h];
                    image.getPixelReader().getPixels(0, 0, w, h, PixelFormat.getIntArgbInstance(), pixels, 0, w);
                    BufferedImage bitmap = new BufferedImage(w, h, BufferedImage.TYPE_INT_ARGB);
                    bitmap.setRGB(0, 0, w, h, pixels, 0, w);
                    ImageIO.write(bitmap, "png", output.resolve("shortcuts-" + width + ".png").toFile());
                }
                System.out.println("SHORTCUT_UI_SMOKE=PASS (delete, clear, modifier order, local save, incomplete validation, toolbar 1024/1280)");
                System.exit(0);
            } catch (Throwable failure) {
                failure.printStackTrace();
                System.exit(1);
            }
        });
    }

    private static Parent editor() throws Exception {
        var method = InspectorPane.class.getDeclaredMethod("createVoiceShortcutEditor", boolean.class);
        method.setAccessible(true);
        return (Parent)method.invoke(inspector, true);
    }
    private static Stream<Node> nodes(Node node) {
        return Stream.concat(Stream.of(node), node instanceof Parent parent
            ? parent.getChildrenUnmodifiable().stream().flatMap(ShortcutEditorUiSmoke::nodes) : Stream.empty());
    }
    @SuppressWarnings("unchecked")
    private static ListView<String> list(Parent editor) {
        return (ListView<String>)nodes(editor).filter(ListView.class::isInstance).findFirst().orElseThrow();
    }
    private static Button button(Parent editor, String key) {
        return nodes(editor).filter(Button.class::isInstance).map(Button.class::cast)
            .filter(b -> b.getText().equals(LanguageManager.text(key))).findFirst().orElseThrow();
    }
    @SuppressWarnings("unchecked")
    private static void add(String key) throws Exception {
        Parent editor = editor();
        var selector = (ComboBox<String>)nodes(editor).filter(ComboBox.class::isInstance).findFirst().orElseThrow();
        selector.setValue(key);
        button(editor, "inspector.add").fire();
    }
    private static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }
}
