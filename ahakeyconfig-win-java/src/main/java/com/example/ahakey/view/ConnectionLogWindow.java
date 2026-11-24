package com.example.ahakey.view;

import static com.example.ahakey.util.LanguageManager.text;

import com.example.ahakey.diagnostics.ConnectionLog;
import com.example.ahakey.diagnostics.ConnectionLog.Entry;
import javafx.animation.KeyFrame;
import javafx.animation.Timeline;
import javafx.collections.FXCollections;
import javafx.collections.ObservableList;
import javafx.collections.transformation.FilteredList;
import javafx.geometry.Insets;
import javafx.geometry.Orientation;
import javafx.geometry.Pos;
import javafx.scene.Node;
import javafx.scene.Scene;
import javafx.scene.control.Alert;
import javafx.scene.control.Button;
import javafx.scene.control.CheckBox;
import javafx.scene.control.ComboBox;
import javafx.scene.control.Label;
import javafx.scene.control.ListCell;
import javafx.scene.control.ListView;
import javafx.scene.control.SplitPane;
import javafx.scene.control.TextArea;
import javafx.scene.control.TextField;
import javafx.scene.control.ToggleButton;
import javafx.scene.input.Clipboard;
import javafx.scene.input.ClipboardContent;
import javafx.scene.layout.BorderPane;
import javafx.scene.layout.HBox;
import javafx.scene.layout.Priority;
import javafx.scene.layout.VBox;
import javafx.stage.FileChooser;
import javafx.stage.Stage;
import javafx.stage.Window;
import javafx.util.Duration;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.function.Consumer;

/**
 * Connection log: app events, BLE driver events and every frame sent to or received
 * from the keyboard, newest at the bottom. Opened from More → Connection Log.
 */
public final class ConnectionLogWindow {
    private static final DateTimeFormatter TIME =
        DateTimeFormatter.ofPattern("HH:mm:ss.SSS").withZone(ZoneId.systemDefault());
    private static final String MONOSPACE =
        "-fx-font-family: Consolas, 'Microsoft YaHei', monospace; -fx-font-size: 12px;";
    private static final int MAX_ROWS = 20_000;
    private static Stage open;

    private enum Detail {
        IMPORTANT, DETAILED, RAW;

        @Override public String toString() {
            return switch (this) {
                case IMPORTANT -> text("connection-log.detail.important");
                case DETAILED -> text("connection-log.detail.detailed");
                case RAW -> text("connection-log.detail.raw");
            };
        }
    }

    private final ObservableList<Entry> rows = FXCollections.observableArrayList();
    private final FilteredList<Entry> visible = new FilteredList<>(rows);
    private final ConcurrentLinkedQueue<Entry> pending = new ConcurrentLinkedQueue<>();
    private final Consumer<Entry> listener = pending::add;
    private final ComboBox<Detail> detail = new ComboBox<>(FXCollections.observableArrayList(Detail.values()));
    private final CheckBox hidePolls = new CheckBox(text("connection-log.filter.hide-polls"));
    private final CheckBox showApp = new CheckBox(text("connection-log.filter.app"));
    private final CheckBox showDriver = new CheckBox(text("connection-log.filter.driver"));
    private final CheckBox showFrames = new CheckBox(text("connection-log.filter.frames"));
    private final TextField search = new TextField();
    private final ToggleButton pause = new ToggleButton(text("connection-log.button.pause"));
    private final Label status = new Label();
    private final Label counts = new Label();
    private final ListView<Entry> list = new ListView<>(visible);
    private final TextArea details = new TextArea();

    /** Shows the window, reusing it when it is already open. */
    public static void show(Window owner) {
        if (open != null) {
            open.show();
            open.toFront();
            return;
        }
        open = new ConnectionLogWindow().build(owner);
        open.show();
    }

    private Stage build(Window owner) {
        Stage stage = new Stage();
        if (owner != null) stage.initOwner(owner);
        stage.setTitle(text("connection-log.title"));

        detail.setValue(Detail.DETAILED);
        hidePolls.setSelected(true);
        for (CheckBox box : List.of(showApp, showDriver, showFrames)) box.setSelected(true);
        search.setPromptText(text("connection-log.search.prompt"));
        HBox.setHgrow(search, Priority.ALWAYS);
        for (var control : List.of(detail.valueProperty(), hidePolls.selectedProperty(),
                showApp.selectedProperty(), showDriver.selectedProperty(),
                showFrames.selectedProperty(), search.textProperty())) {
            control.addListener((observable, before, after) -> applyFilter());
        }

        Button clear = new Button(text("connection-log.button.clear"));
        clear.setOnAction(event -> { rows.clear(); ConnectionLog.get().clear(); details.clear(); });
        Button copy = new Button(text("connection-log.button.copy"));
        copy.setOnAction(event -> {
            ClipboardContent content = new ClipboardContent();
            content.putString(String.join("\n", visible.stream().map(ConnectionLog::format).toList()));
            Clipboard.getSystemClipboard().setContent(content);
        });
        Button save = new Button(text("connection-log.button.save"));
        save.setOnAction(event -> saveVisible(stage));
        Button folder = new Button(text("connection-log.button.open-folder"));
        folder.setOnAction(event -> openFolder());

        Label viewLabel = new Label(text("connection-log.filter.view"));
        HBox filters = row(viewLabel, detail, showApp, showDriver, showFrames, hidePolls);
        HBox actions = row(search, pause, clear, copy, save, folder);
        status.setWrapText(true);
        status.setStyle("-fx-font-weight: 700;");
        counts.setStyle("-fx-text-fill: #6b7280;");
        Label help = new Label(text("connection-log.help", ConnectionLog.logDirectory().toString()));
        help.setWrapText(true);
        help.setStyle("-fx-text-fill: #6b7280;");
        VBox top = new VBox(8, status, filters, actions, help);
        top.setPadding(new Insets(12));

        list.setCellFactory(view -> new EntryCell());
        list.getSelectionModel().selectedItemProperty().addListener((observable, before, entry) -> showDetails(entry));
        details.setEditable(false);
        details.setWrapText(false);
        details.setStyle(MONOSPACE);
        details.setPromptText(text("connection-log.details.prompt"));

        SplitPane split = new SplitPane(list, details);
        split.setOrientation(Orientation.VERTICAL);
        split.setDividerPositions(0.72);

        HBox bottom = new HBox(counts);
        bottom.setPadding(new Insets(6, 12, 8, 12));
        BorderPane root = new BorderPane(split, top, null, bottom, null);
        stage.setScene(new Scene(root, 1040, 720));

        rows.addAll(ConnectionLog.get().snapshot());
        applyFilter();
        list.scrollTo(visible.size() - 1);
        ConnectionLog.get().addListener(listener);

        Timeline refresh = new Timeline(new KeyFrame(Duration.millis(300), event -> flush()));
        refresh.setCycleCount(Timeline.INDEFINITE);
        refresh.play();
        stage.setOnHidden(event -> {
            refresh.stop();
            ConnectionLog.get().removeListener(listener);
            open = null;
        });
        flush();
        return stage;
    }

    private static HBox row(Node... nodes) {
        HBox box = new HBox(10, nodes);
        box.setAlignment(Pos.CENTER_LEFT);
        return box;
    }

    private void flush() {
        String summary = ConnectionLog.statusSummary();
        status.setText(summary.isBlank() ? text("connection-log.status.unknown") : summary);
        if (!pause.isSelected()) {
            List<Entry> batch = new ArrayList<>();
            for (Entry entry; (entry = pending.poll()) != null; ) batch.add(entry);
            if (!batch.isEmpty()) {
                boolean atEnd = isAtEnd();
                rows.addAll(batch);
                if (rows.size() > MAX_ROWS) rows.remove(0, rows.size() - MAX_ROWS);
                if (atEnd) list.scrollTo(visible.size() - 1);
            }
        }
        long drops = rows.stream().filter(ConnectionLogWindow::isDisconnect).count();
        String line = text("connection-log.counts", visible.size(), rows.size(), drops);
        if (pause.isSelected()) line += " · " + text("connection-log.counts.paused", pending.size());
        counts.setText(line);
    }

    private boolean isAtEnd() {
        int selected = list.getSelectionModel().getSelectedIndex();
        return selected < 0 || selected >= visible.size() - 1;
    }

    private void applyFilter() {
        Detail level = detail.getValue();
        String query = search.getText() == null ? "" : search.getText().trim().toLowerCase(Locale.ROOT);
        visible.setPredicate(entry -> {
            switch (entry.source()) {
                case APP -> { if (!showApp.isSelected()) return false; }
                case BRIDGE -> { if (!showDriver.isSelected()) return false; }
                case TX, RX -> {
                    if (!showFrames.isSelected() || level != Detail.RAW) return false;
                    if (hidePolls.isSelected() && ConnectionLog.isStatusPoll(entry)) return false;
                }
            }
            if (level == Detail.IMPORTANT && entry.level() == ConnectionLog.Level.DEBUG
                && !entry.isConnectionChange()) {
                return false;
            }
            if (query.isEmpty()) return true;
            return ConnectionLog.format(entry).toLowerCase(Locale.ROOT).contains(query);
        });
    }

    private void showDetails(Entry entry) {
        if (entry == null) { details.clear(); return; }
        StringBuilder out = new StringBuilder(ConnectionLog.format(entry)).append("\n\n");
        out.append(text("connection-log.details.source", sourceName(entry))).append('\n');
        out.append(text("connection-log.details.level", entry.level())).append('\n');
        if (!entry.transport().isEmpty()) {
            out.append(text("connection-log.details.transport", entry.transport())).append('\n');
        }
        out.append(text("connection-log.details.message", entry.message())).append('\n');
        if (entry.raw() != null && entry.raw().length > 0) {
            byte[] raw = entry.raw();
            out.append('\n').append(text("connection-log.details.raw", raw.length)).append('\n');
            for (int offset = 0; offset < raw.length; offset += 16) {
                StringBuilder hex = new StringBuilder();
                StringBuilder ascii = new StringBuilder();
                for (int i = offset; i < Math.min(raw.length, offset + 16); i++) {
                    int c = raw[i] & 0xFF;
                    hex.append(String.format("%02X ", c));
                    ascii.append(c >= 32 && c < 127 ? (char) c : '.');
                }
                out.append(String.format("%04X  %-48s %s%n", offset, hex, ascii));
            }
        }
        details.setText(out.toString());
    }

    private void saveVisible(Stage stage) {
        FileChooser chooser = new FileChooser();
        chooser.setTitle(text("connection-log.save.title"));
        chooser.setInitialFileName("ahakey-connection-log.txt");
        chooser.getExtensionFilters().add(new FileChooser.ExtensionFilter(text("connection-log.save.filter"), "*.txt"));
        var file = chooser.showSaveDialog(stage);
        if (file == null) return;
        try {
            Files.writeString(file.toPath(),
                String.join(System.lineSeparator(), visible.stream().map(ConnectionLog::format).toList()),
                StandardCharsets.UTF_8);
        } catch (IOException e) {
            new Alert(Alert.AlertType.ERROR, text("connection-log.save.failed", e.getMessage())).showAndWait();
        }
    }

    private static void openFolder() {
        try {
            Files.createDirectories(ConnectionLog.logDirectory());
            new ProcessBuilder("explorer.exe", ConnectionLog.logDirectory().toString()).start();
        } catch (IOException ignored) {
            // Explorer is Windows only; the folder path is also shown in the help text.
        }
    }

    private static String sourceName(Entry entry) {
        return switch (entry.source()) {
            case APP -> text("connection-log.source.app");
            case BRIDGE -> text("connection-log.source.driver");
            case TX -> text("connection-log.source.tx", entry.transport());
            case RX -> text("connection-log.source.rx", entry.transport());
        };
    }

    private static boolean isDisconnect(Entry entry) {
        return entry.category() == ConnectionLog.Category.DISCONNECTED;
    }

    private static final class EntryCell extends ListCell<Entry> {
        @Override
        protected void updateItem(Entry entry, boolean empty) {
            super.updateItem(entry, empty);
            if (empty || entry == null) { setText(null); setGraphic(null); setStyle(""); return; }
            String tag = switch (entry.source()) {
                case APP -> text("connection-log.tag.app");
                case BRIDGE -> text("connection-log.tag.driver");
                case TX -> "→ " + entry.transport();
                case RX -> "← " + entry.transport();
            };
            String message = entry.message();
            if (entry.isFrame() && entry.raw() != null && entry.raw().length > 0) {
                String hex = ConnectionLog.hex(entry.raw());
                message += "   " + (hex.length() > 96 ? hex.substring(0, 96) + " …" : hex);
            }
            setText(TIME.format(entry.time()) + "  " + pad(tag) + "  " + message);
            String color = switch (entry.level()) {
                case ERROR -> "#b91c1c";
                case WARN -> "#b45309";
                case INFO -> entry.source() == ConnectionLog.Source.BRIDGE ? "#1d4ed8" : "#111827";
                case DEBUG -> entry.isFrame() ? "#4b5563" : "#6b7280";
            };
            String weight = entry.isConnectionChange() ? "-fx-font-weight: 700;" : "";
            setStyle("-fx-text-fill: " + color + "; " + MONOSPACE + " " + weight);
        }

        private static String pad(String tag) {
            return tag.length() >= 8 ? tag : tag + " ".repeat(8 - tag.length());
        }
    }
}
