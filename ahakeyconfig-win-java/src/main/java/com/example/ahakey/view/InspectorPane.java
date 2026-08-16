package com.example.ahakey.view;

import com.example.ahakey.app.StudioController;
import com.example.ahakey.model.DeviceStatus;
import com.example.ahakey.model.KeyConfig;
import com.example.ahakey.model.IDEState;
import com.example.ahakey.model.LightBarPreviewState;
import com.example.ahakey.model.LightEffectStyle;
import com.example.ahakey.model.ModeSlot;
import com.example.ahakey.model.OledModeDraft;
import com.example.ahakey.model.StudioPart;
import com.example.ahakey.model.StudioState;
import com.example.ahakey.util.LanguageManager;
import javafx.scene.control.Spinner;
import javafx.stage.Window;
import com.example.ahakey.service.AgentManager;
import javafx.beans.binding.Bindings;
import javafx.geometry.Insets;
import javafx.geometry.Pos;
import javafx.scene.control.Button;
import javafx.scene.control.ComboBox;
import javafx.scene.control.Label;
import javafx.scene.control.ScrollPane;
import javafx.scene.control.Separator;
import javafx.scene.control.TextField;
import javafx.scene.control.ToggleButton;
import javafx.scene.control.ToggleGroup;
import javafx.scene.control.ListView;
import javafx.scene.image.Image;
import javafx.scene.image.ImageView;
import javafx.scene.layout.FlowPane;
import javafx.scene.layout.GridPane;
import javafx.scene.layout.HBox;
import javafx.scene.layout.StackPane;
import javafx.scene.layout.Priority;
import javafx.scene.layout.VBox;
import javafx.scene.text.Text;

import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.Supplier;

public class InspectorPane extends ScrollPane {
    private final StudioController controller;
    private final DeviceStatus deviceStatus;
    private final StudioState studioState;
    private final AgentManager agentManager;
    private final LanguageManager languageManager = LanguageManager.getInstance();
    private final VBox content = new VBox(18);
    private final VBox header = new VBox(8);
    private final VBox body = new VBox(16);

    public InspectorPane(StudioController controller) {
        this.controller = controller;
        this.deviceStatus = controller.getDeviceStatus();
        this.studioState = controller.getStudioState();
        this.agentManager = controller.getAgentManager();
        init();
    }

    private void init() {
        setFitToWidth(true);
        setHbarPolicy(ScrollBarPolicy.NEVER);
        setMinWidth(500);
        setPrefWidth(560);
        setMaxWidth(720);
        HBox.setHgrow(this, Priority.NEVER);
        getStyleClass().add("inspector-pane");

        content.setPadding(new Insets(24));
        content.getChildren().addAll(header, body);
        setContent(content);

        studioState.selectedPartProperty().addListener((obs, oldValue, newValue) -> rebuild());
        studioState.selectedModeProperty().addListener((obs, oldValue, newValue) -> rebuild());
        studioState.lightBarPreviewProperty().addListener((obs, oldValue, newValue) -> rebuild());
        agentManager.bluetoothOwnerProperty().addListener((obs, oldValue, newValue) -> rebuild());
        rebuild();
    }

    private void rebuild() {
        header.getChildren().clear();
        body.getChildren().clear();

        StudioPart part = studioState.getSelectedPart();
        ModeSlot mode = studioState.getSelectedMode();

        HBox titleRow = new HBox();
        titleRow.setAlignment(Pos.CENTER_LEFT);

        Text icon = new Text(iconFor(part));
        icon.getStyleClass().add("inspector-icon");

        Label title = new Label(part.getDisplayTitle());
        title.getStyleClass().add("inspector-title");

        titleRow.getChildren().addAll(icon, new Label("   "), title);

        Label subtitle = new Label(mode.getTitle() + " · " + mode.getGuidance());
        subtitle.getStyleClass().add("inspector-subtitle");

        header.getChildren().addAll(titleRow, subtitle);
        body.disableProperty().bind(Bindings.createBooleanBinding(
            () -> !agentManager.isEditingConfiguration(),
            agentManager.bluetoothOwnerProperty()
        ));

        if (part == StudioPart.KEY1) {
            body.getChildren().add(createDualVoiceKeyGroup());
        } else if (part.isKey()) {
            body.getChildren().add(createKeyBindingGroup(part));
            body.getChildren().add(createDescriptionGroup(part));
            body.getChildren().add(createSimulateKeyGroup(part));
        } else if (part == StudioPart.LIGHT_BAR) {
            body.getChildren().add(createLightBarGroup());
        } else if (part == StudioPart.OLED) {
            body.getChildren().add(createOledGroup());
        } else if (part == StudioPart.TOGGLE_SWITCH) {
            body.getChildren().add(createToggleGroup());
        }
    }

    private VBox createDualVoiceKeyGroup() {
        return createGroupBox("语音键：短按 / 长按", () -> {
            VBox box = new VBox(16);
            Label hint = new Label(
                "全局配置，所有模式共用。短按会点击一次快捷键；按住超过 350ms 后，"
                    + "长按快捷键会保持按下，松开语音键时释放。任一列表清空即可禁用对应动作。"
            );
            hint.setWrapText(true);
            hint.getStyleClass().add("warning-note");

            Label shortLabel = new Label("短按快捷键（默认：Right Alt，用于 Typeless）");
            shortLabel.getStyleClass().add("field-label");
            Label longLabel = new Label("长按快捷键（默认：Left Ctrl + Left Win，用于微信语音输入）");
            longLabel.getStyleClass().add("field-label");

            Button testShort = new Button("测试短按");
            testShort.getStyleClass().add("button-prominent");
            testShort.setOnAction(event -> controller.getVoiceRelay()
                .simulateKeyByHid(studioState.getVoiceKeyShort().getHidCode()));

            Button testLong = new Button("按住测试长按");
            testLong.getStyleClass().add("button-prominent");
            AtomicBoolean longTestPressed = new AtomicBoolean(false);
            testLong.setOnMousePressed(event -> {
                if (event.isPrimaryButtonDown() && longTestPressed.compareAndSet(false, true)) {
                    controller.getVoiceRelay().pressKeyByHid(
                        studioState.getVoiceKeyLong().getHidCode());
                }
            });
            testLong.setOnMouseReleased(event -> {
                if (longTestPressed.compareAndSet(true, false)) {
                    controller.getVoiceRelay().releaseKeyByHid(
                        studioState.getVoiceKeyLong().getHidCode());
                }
            });
            testLong.setOnMouseExited(event -> {
                if (longTestPressed.compareAndSet(true, false)) {
                    controller.getVoiceRelay().releaseKeyByHid(
                        studioState.getVoiceKeyLong().getHidCode());
                }
            });
            testLong.focusedProperty().addListener((obs, wasFocused, isFocused) -> {
                if (!isFocused && longTestPressed.compareAndSet(true, false)) {
                    controller.getVoiceRelay().releaseKeyByHid(
                        studioState.getVoiceKeyLong().getHidCode());
                }
            });
            Label testHint = new Label();
            testHint.textProperty().bind(controller.getVoiceRelay().lastSimulateHintProperty());
            testHint.getStyleClass().add("warning-note");
            testHint.setWrapText(true);

            box.getChildren().addAll(
                hint,
                shortLabel,
                createShortcutEditor(studioState.getVoiceKeyShort(), StudioPart.KEY1),
                longLabel,
                createShortcutEditor(studioState.getVoiceKeyLong(), StudioPart.KEY1),
                new HBox(8, testShort, testLong),
                testHint
            );
            return box;
        });
    }

    private VBox createSimulateKeyGroup(StudioPart part) {
        return createGroupBox(languageManager.getString("inspector.simulate-key"), () -> {
            VBox box = new VBox(8);
            KeyConfig key = studioState.getKeyConfig(part);
            var voice = controller.getVoiceRelay();

            Button simulate = new Button("模拟按键");
            simulate.getStyleClass().add("button-prominent");
            simulate.setOnAction(e -> {
                if (!key.usesMacro()) voice.simulateKeyByHid(key.getHidCode());
            });
            simulate.setDisable(key.usesMacro());

            Label hint = new Label();
            hint.getStyleClass().add("warning-note");
            if (key.usesMacro()) {
                hint.setText("复杂宏序列暂不执行模拟；切换为单个快捷键后可在此测试。");
            } else {
                hint.textProperty().bind(voice.lastSimulateHintProperty());
            }

            box.getChildren().addAll(simulate, hint);
            return box;
        });
    }

    private VBox createKeyBindingGroup(StudioPart part) {
        return createGroupBox(languageManager.getString("inspector.key-binding"), () -> {
            VBox box = new VBox(14);
            KeyConfig key = studioState.getKeyConfig(part);
            boolean voiceLocked = part == StudioPart.KEY1 && key.getVoicePreset().locksShortcut();

            if (!voiceLocked) {
                Label typeLabel = new Label(languageManager.getString("inspector.key-type"));
                typeLabel.getStyleClass().add("field-label");
                ComboBox<String> typeCombo = new ComboBox<>();
                typeCombo.getItems().addAll(List.of(languageManager.getString("inspector.shortcut"), languageManager.getString("inspector.macro")));
                typeCombo.getStyleClass().add("combo-box");
                typeCombo.setValue(key.usesMacro() ? languageManager.getString("inspector.macro") : languageManager.getString("inspector.shortcut"));
                typeCombo.valueProperty().addListener((obs, old, newValue) -> {
                    if (languageManager.getString("inspector.shortcut").equals(newValue)) {
                        for (int i = key.getMacroStepCount() - 1; i >= 0; i--) {
                            key.removeMacroStep(i);
                        }
                    } else if (languageManager.getString("inspector.macro").equals(newValue)) {
                        // 切换到宏模式时，确保至少有一个宏步骤
                        if (key.getMacroStepCount() == 0) {
                            key.addMacroStep("DOWN_KEY", 40); // 添加一个默认步骤
                        }
                    }
                    rebuild();
                });

                box.getChildren().addAll(typeLabel, typeCombo);

                if (key.usesMacro()) {
                    box.getChildren().add(createMacroEditor(part));
                } else {
                    box.getChildren().add(createShortcutEditor(part));
                }
            } else {
                Label presetLabel = new Label(languageManager.getString("inspector.voice-preset-mode"));
                presetLabel.getStyleClass().add("key-preview-label");
                Label lockNote = new Label(languageManager.getString("inspector.voice-preset-note"));
                lockNote.getStyleClass().add("warning-note");
                lockNote.setWrapText(true);
                box.getChildren().addAll(presetLabel, lockNote);
            }
            return box;
        });
    }

    private VBox createShortcutEditor(StudioPart part) {
        return createShortcutEditor(studioState.getKeyConfig(part), part);
    }

    private VBox createShortcutEditor(KeyConfig key, StudioPart dirtyPart) {
        VBox box = new VBox(12);

        Label listLabel = new Label(languageManager.getString("inspector.key-code-list"));
        listLabel.getStyleClass().add("field-label");

        javafx.scene.control.ListView<String> keyListView = new javafx.scene.control.ListView<>();
        keyListView.setPrefHeight(100);
        keyListView.getStyleClass().add("list-view");

        java.util.List<String> keyCodes = new java.util.ArrayList<>();
        int hidCode = key.getHidCode();
        
        if (hidCode != 0) {
            // 修饰键：区分 Left/Right（新编码 0xNN00 + 旧编码 0x0N00 兼容）
            if (((hidCode & 0x100) != 0) && ((hidCode & 0x1000) == 0)) keyCodes.add("Left Shift (0xE1)");
            else if ((hidCode & 0x1000) != 0) keyCodes.add("Right Shift (0xE5)");
            if (((hidCode & 0x200) != 0) && ((hidCode & 0x2000) == 0)) keyCodes.add("Left Ctrl (0xE0)");
            else if ((hidCode & 0x2000) != 0) keyCodes.add("Right Ctrl (0xE4)");
            if (((hidCode & 0x400) != 0) && ((hidCode & 0x4000) == 0)) keyCodes.add("Left Alt (0xE2)");
            else if ((hidCode & 0x4000) != 0) keyCodes.add("Right Alt (0xE6)");
            if (((hidCode & 0x800) != 0) && ((hidCode & 0x8000) == 0)) keyCodes.add("Left Win (0xE3)");
            else if ((hidCode & 0x8000) != 0) keyCodes.add("Right Win (0xE7)");
            
            int baseCode = hidCode & 0xFF;
            if (baseCode != 0) {
                String name = com.example.ahakey.model.HIDUsage.getName(baseCode);
                keyCodes.add(name + " (0x" + String.format("%02X", baseCode) + ")");
            }
        }
        
        keyListView.getItems().addAll(keyCodes);

        HBox buttonRow = new HBox(8);

        ComboBox<String> keySelector = new ComboBox<>();
        java.util.List<String> keyItems = new java.util.ArrayList<>();
        
        // 修饰键 (modifier)
        keyItems.add("--- 修饰键 ---");
        keyItems.add("Left Ctrl (0xE0)");
        keyItems.add("Left Shift (0xE1)");
        keyItems.add("Left Alt (0xE2)");
        keyItems.add("Left Win (0xE3)");
        keyItems.add("Right Ctrl (0xE4)");
        keyItems.add("Right Shift (0xE5)");
        keyItems.add("Right Alt (0xE6)");
        keyItems.add("Right Win (0xE7)");
        
        // 字母键 (alpha)
        keyItems.add("--- 字母 ---");
        String[] letters = {"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
                           "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"};
        int[] letterCodes = {0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 
                            0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 
                            0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D};
        for (int i = 0; i < letters.length; i++) {
            keyItems.add(letters[i] + " (0x" + String.format("%02X", letterCodes[i]) + ")");
        }
        
        // 数字键 (number)
        keyItems.add("--- 数字 ---");
        keyItems.add("1 (0x1E)");
        keyItems.add("2 (0x1F)");
        keyItems.add("3 (0x20)");
        keyItems.add("4 (0x21)");
        keyItems.add("5 (0x22)");
        keyItems.add("6 (0x23)");
        keyItems.add("7 (0x24)");
        keyItems.add("8 (0x25)");
        keyItems.add("9 (0x26)");
        keyItems.add("0 (0x27)");
        
        // 基础键 (basic)
        keyItems.add("--- 基础键 ---");
        keyItems.add("Enter (0x28)");
        keyItems.add("Escape (0x29)");
        keyItems.add("Backspace (0x2A)");
        keyItems.add("Tab (0x2B)");
        keyItems.add("Space (0x2C)");
        keyItems.add("Minus (0x2D)");
        keyItems.add("Equal (0x2E)");
        keyItems.add("Left Bracket (0x2F)");
        keyItems.add("Right Bracket (0x30)");
        keyItems.add("Backslash (0x31)");
        keyItems.add("Semicolon (0x33)");
        keyItems.add("Quote (0x34)");
        keyItems.add("Grave (0x35)");
        keyItems.add("Comma (0x36)");
        keyItems.add("Period (0x37)");
        keyItems.add("Slash (0x38)");
        keyItems.add("Caps Lock (0x39)");
        
        // 功能键 (function)
        keyItems.add("--- 功能键 ---");
        keyItems.add("F1 (0x3A)");
        keyItems.add("F2 (0x3B)");
        keyItems.add("F3 (0x3C)");
        keyItems.add("F4 (0x3D)");
        keyItems.add("F5 (0x3E)");
        keyItems.add("F6 (0x3F)");
        keyItems.add("F7 (0x40)");
        keyItems.add("F8 (0x41)");
        keyItems.add("F9 (0x42)");
        keyItems.add("F10 (0x43)");
        keyItems.add("F11 (0x44)");
        keyItems.add("F12 (0x45)");
        keyItems.add("F13 (0x68)");
        keyItems.add("F14 (0x69)");
        keyItems.add("F15 (0x6A)");
        keyItems.add("F16 (0x6B)");
        keyItems.add("F17 (0x6C)");
        keyItems.add("F18 (0x6D)");
        keyItems.add("F19 (0x6E)");
        keyItems.add("F20 (0x6F)");
        keyItems.add("F21 (0x70)");
        keyItems.add("F22 (0x71)");
        keyItems.add("F23 (0x72)");
        keyItems.add("F24 (0x73)");
        
        // 控制键 (control)
        keyItems.add("--- 控制键 ---");
        keyItems.add("Print Screen (0x46)");
        keyItems.add("Scroll Lock (0x47)");
        keyItems.add("Pause (0x48)");
        keyItems.add("Insert (0x49)");
        keyItems.add("Home (0x4A)");
        keyItems.add("Page Up (0x4B)");
        keyItems.add("Delete (0x4C)");
        keyItems.add("End (0x4D)");
        keyItems.add("Page Down (0x4E)");
        
        // 方向键 (arrow)
        keyItems.add("--- 方向键 ---");
        keyItems.add("Right (0x4F)");
        keyItems.add("Left (0x50)");
        keyItems.add("Down (0x51)");
        keyItems.add("Up (0x52)");
        
        // 小键盘 (numpad)
        keyItems.add("--- 小键盘 ---");
        keyItems.add("Num Lock (0x53)");
        keyItems.add("KP / (0x54)");
        keyItems.add("KP * (0x55)");
        keyItems.add("KP - (0x56)");
        keyItems.add("KP + (0x57)");
        keyItems.add("KP Enter (0x58)");
        keyItems.add("KP 1 (0x59)");
        keyItems.add("KP 2 (0x5A)");
        keyItems.add("KP 3 (0x5B)");
        keyItems.add("KP 4 (0x5C)");
        keyItems.add("KP 5 (0x5D)");
        keyItems.add("KP 6 (0x5E)");
        keyItems.add("KP 7 (0x5F)");
        keyItems.add("KP 8 (0x60)");
        keyItems.add("KP 9 (0x61)");
        keyItems.add("KP 0 (0x62)");
        keyItems.add("KP . (0x63)");
        
        keySelector.getItems().addAll(keyItems);
        keySelector.getStyleClass().addAll("combo-box", "combo-box-small");
        keySelector.setValue("--- 修饰键 ---");

        Button addBtn = new Button(languageManager.getString("inspector.add"));
        addBtn.getStyleClass().add("btn-secondary");
        addBtn.setOnAction(e -> {
            String selected = keySelector.getValue();
            if (selected != null && !selected.startsWith("---")) {
                // 提取按键名称和键码
                String keyName = selected.split("\\s*\\(")[0].trim();
                int codeToAdd = 0;
                
                // 尝试从字符串中提取键码
                java.util.regex.Matcher matcher = java.util.regex.Pattern.compile("0x([0-9A-Fa-f]+)").matcher(selected);
                if (matcher.find()) {
                    codeToAdd = Integer.parseInt(matcher.group(1), 16);
                }
                
                // 如果没有提取到键码，尝试通过名称查找
                if (codeToAdd == 0) {
                    codeToAdd = switch (keyName) {
                        case "Shift" -> 0xE1;  // 使用实际的HID码
                        case "Ctrl" -> 0xE0;
                        case "Alt" -> 0xE2;
                        case "Win" -> 0xE3;
                        default -> com.example.ahakey.model.HIDUsage.getCode(keyName);
                    };
                    
                    // 如果还是没找到，检查是否是十六进制格式
                    if (codeToAdd == 0 && keyName.startsWith("0x")) {
                        try {
                            codeToAdd = Integer.parseInt(keyName.substring(2), 16);
                        } catch (NumberFormatException ex) {
                            codeToAdd = 0;
                        }
                    }
                }
                
                // 如果找到了有效的键码，进行累加
                if (codeToAdd != 0) {
                    int currentCode = key.getHidCode();
                    int modifiers = currentCode & 0xFF00;  // 保留所有修饰键位（含 Right 高位）
                    int baseCode = currentCode & 0xFF;    // 保留基础键位
                    
                    // 处理修饰键（0xE0-0xE7），每个具体键映射到独立位
                    if (codeToAdd >= 0xE0 && codeToAdd <= 0xE7) {
                        switch (codeToAdd) {
                            case 0xE0 -> modifiers |= 0x200;   // Left Ctrl
                            case 0xE4 -> modifiers |= 0x2000;  // Right Ctrl
                            case 0xE1 -> modifiers |= 0x100;   // Left Shift
                            case 0xE5 -> modifiers |= 0x1000;  // Right Shift
                            case 0xE2 -> modifiers |= 0x400;   // Left Alt
                            case 0xE6 -> modifiers |= 0x4000;  // Right Alt
                            case 0xE3 -> modifiers |= 0x800;   // Left Win
                            case 0xE7 -> modifiers |= 0x8000;  // Right Win
                        }
                        key.setHidCode(modifiers | baseCode);
                    } else {
                        // 处理普通键（设置为基础键位）
                        key.setHidCode(modifiers | codeToAdd);
                    }
                    studioState.markDirty(dirtyPart);
                }
                rebuild();
            }
        });

        Button deleteBtn = new Button(languageManager.getString("inspector.delete"));
        deleteBtn.getStyleClass().add("btn-secondary");
        deleteBtn.setDisable(keyListView.getSelectionModel().getSelectedIndex() < 0);
        deleteBtn.setOnAction(e -> {
            int selectedIndex = keyListView.getSelectionModel().getSelectedIndex();
            if (selectedIndex >= 0) {
                String selectedItem = keyListView.getItems().get(selectedIndex);
                
                // 尝试从字符串中提取键码
                int codeToRemove = 0;
                java.util.regex.Matcher matcher = java.util.regex.Pattern.compile("0x([0-9A-Fa-f]+)").matcher(selectedItem);
                if (matcher.find()) {
                    codeToRemove = Integer.parseInt(matcher.group(1), 16);
                }
                
                // 如果没有提取到键码，尝试通过名称查找
                if (codeToRemove == 0) {
                    String keyName = selectedItem.split("\\s*\\(")[0].trim();
                    codeToRemove = switch (keyName) {
                        case "Shift" -> 0x100;
                        case "Ctrl" -> 0x200;
                        case "Alt" -> 0x400;
                        case "Win" -> 0x800;
                        default -> com.example.ahakey.model.HIDUsage.getCode(keyName);
                    };
                }
                
                int currentCode = key.getHidCode();
                
                // 处理修饰键（存储在高位，区分 Left/Right）
                if (codeToRemove >= 0xE0 && codeToRemove <= 0xE7) {
                    int modifierToRemove = switch (codeToRemove) {
                        case 0xE0 -> 0x200;    // Left Ctrl
                        case 0xE4 -> 0x2000;   // Right Ctrl
                        case 0xE1 -> 0x100;    // Left Shift
                        case 0xE5 -> 0x1000;   // Right Shift
                        case 0xE2 -> 0x400;    // Left Alt
                        case 0xE6 -> 0x4000;   // Right Alt
                        case 0xE3 -> 0x800;    // Left Win
                        case 0xE7 -> 0x8000;   // Right Win
                        default -> 0;
                    };
                    int modifiers = currentCode & 0xFF00;
                    int baseCode = currentCode & 0xFF;
                    modifiers &= ~modifierToRemove;
                    key.setHidCode(modifiers | baseCode);
                } else {
                    // 处理普通键（存储在低位）
                    int modifiers = currentCode & 0xFF00;
                    key.setHidCode(modifiers);
                }
                
                studioState.markDirty(dirtyPart);
                rebuild();
            }
        });

        keyListView.getSelectionModel().selectedIndexProperty().addListener((obs, old, newVal) -> {
            deleteBtn.setDisable(newVal.intValue() < 0);
        });

        buttonRow.getChildren().addAll(keySelector, addBtn, deleteBtn);

        box.getChildren().addAll(listLabel, keyListView, buttonRow);
        return box;
    }

    private void updateKeyCodeFromList(StudioPart part, java.util.List<String> keyCodes) {
        KeyConfig key = studioState.getKeyConfig(part);
        int hidCode = 0;

        for (String code : keyCodes) {
            // 提取按键名称（去掉括号和键码）
            String keyName = code.split("\\s*\\(")[0].trim();
            
            switch (keyName) {
                case "Shift" -> hidCode |= 0x100;
                case "Ctrl" -> hidCode |= 0x200;
                case "Alt" -> hidCode |= 0x400;
                case "Win" -> hidCode |= 0x800;
                default -> hidCode |= com.example.ahakey.model.HIDUsage.getCode(keyName);
            }
        }

        key.setHidCode(hidCode);
        studioState.markDirty(part);
    }

    private VBox createMacroEditor(StudioPart part) {
        VBox box = new VBox(10);
        KeyConfig key = studioState.getKeyConfig(part);

        VBox stepsBox = new VBox(4);

        if (key.getMacroStepCount() == 0) {
            key.addMacroStep("DOWN_KEY", 40);
        }

        for (int i = 0; i < key.getMacroStepCount(); i++) {
            HBox stepRow = createMacroStepRow(part, i);
            stepsBox.getChildren().add(stepRow);
        }

        HBox buttonRow = new HBox(8);
        Button addStepBtn = new Button(languageManager.getString("inspector.add-step"));
        addStepBtn.getStyleClass().add("btn-primary");
        addStepBtn.setOnAction(e -> {
            key.addMacroStep("DOWN_KEY", 40);
            studioState.markDirty(part);
            rebuild();
        });

        Button clearBtn = new Button(languageManager.getString("inspector.clear"));
        clearBtn.getStyleClass().add("btn-secondary");
        clearBtn.setOnAction(e -> {
            for (int i = key.getMacroStepCount() - 1; i >= 0; i--) {
                key.removeMacroStep(i);
            }
            studioState.markDirty(part);
            rebuild();
        });

        buttonRow.getChildren().addAll(addStepBtn, clearBtn);

        Label previewLabel = new Label(languageManager.getString("inspector.preview") + key.formatMacroPreview());
        previewLabel.getStyleClass().add("group-note");

        Label note = new Label(languageManager.getString("inspector.macro-note"));
        note.getStyleClass().add("warning-note");
        note.setWrapText(true);

        box.getChildren().addAll(stepsBox, buttonRow, previewLabel, note);
        return box;
    }

    private HBox createMacroStepRow(StudioPart part, int index) {
        HBox row = new HBox(6);
        row.setAlignment(Pos.CENTER_LEFT);
        KeyConfig key = studioState.getKeyConfig(part);

        Label indexLabel = new Label((index + 1) + ".");
        indexLabel.setMinWidth(30);

        ComboBox<String> actionCombo = new ComboBox<>();
        actionCombo.getItems().addAll(List.of(languageManager.getString("inspector.press"), languageManager.getString("inspector.release"), languageManager.getString("inspector.delay")));
        actionCombo.getStyleClass().add("combo-box-small");
        
        String actionType = key.getMacroStepAction(index);
        String actionText = switch (actionType) {
            case "DOWN_KEY" -> languageManager.getString("inspector.press");
            case "UP_KEY" -> languageManager.getString("inspector.release");
            case "DELAY" -> languageManager.getString("inspector.delay");
            default -> languageManager.getString("inspector.press");
        };
        actionCombo.setValue(actionText);
        actionCombo.valueProperty().addListener((obs, old, newValue) -> {
            String newActionType;
            if (languageManager.getString("inspector.press").equals(newValue)) {
                newActionType = "DOWN_KEY";
            } else if (languageManager.getString("inspector.release").equals(newValue)) {
                newActionType = "UP_KEY";
            } else if (languageManager.getString("inspector.delay").equals(newValue)) {
                newActionType = "DELAY";
            } else {
                newActionType = "DOWN_KEY";
            }
            int currentParam = key.getMacroStepParam(index);
            key.updateMacroStep(index, newActionType, currentParam);
            studioState.markDirty(part);
            rebuild();
        });

        if ("DELAY".equals(actionType)) {
            Spinner<Integer> delaySpinner = new Spinner<>(1, 255, key.getMacroStepParam(index), 1);
            delaySpinner.setEditable(true);
            delaySpinner.setPrefWidth(80);
            delaySpinner.valueProperty().addListener((obs, old, newValue) -> {
                key.updateMacroStep(index, "DELAY", newValue);
                studioState.markDirty(part);
            });
            Label msLabel = new Label("ms");

            row.getChildren().addAll(indexLabel, actionCombo, delaySpinner, msLabel);
        } else {
            ComboBox<String> keyCombo = new ComboBox<>();
            java.util.List<String> keyItems = new java.util.ArrayList<>();
            keyItems.add("--- 修饰键 ---");
            keyItems.add("Shift");
            keyItems.add("Ctrl");
            keyItems.add("Alt");
            keyItems.add("Win");
            keyItems.add("--- 功能键 ---");
            keyItems.add("F1");
            keyItems.add("F2");
            keyItems.add("F3");
            keyItems.add("F4");
            keyItems.add("F5");
            keyItems.add("F6");
            keyItems.add("F7");
            keyItems.add("F8");
            keyItems.add("F9");
            keyItems.add("F10");
            keyItems.add("F11");
            keyItems.add("F12");
            keyItems.add("F13");
            keyItems.add("F14");
            keyItems.add("F15");
            keyItems.add("F16");
            keyItems.add("F17");
            keyItems.add("F18");
            keyItems.add("--- 字母键 ---");
            String[] letters = {"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
                               "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"};
            for (String letter : letters) {
                keyItems.add(letter);
            }
            keyItems.add("--- 数字键 ---");
            for (int i = 1; i <= 9; i++) {
                keyItems.add(String.valueOf(i));
            }
            keyItems.add("0");
            keyItems.add("--- 其他键 ---");
            keyItems.add("Enter");
            keyItems.add("Escape");
            keyItems.add("Backspace");
            keyItems.add("Tab");
            keyItems.add("Space");
            keyItems.add("CapsLock");
            keyItems.add("Delete");
            keyItems.add("Up");
            keyItems.add("Down");
            keyItems.add("Left");
            keyItems.add("Right");
            keyCombo.getItems().addAll(keyItems);
            keyCombo.getStyleClass().add("combo-box-small");
            keyCombo.setValue(com.example.ahakey.model.HIDUsage.getName(key.getMacroStepParam(index)));
            keyCombo.valueProperty().addListener((obs, old, newValue) -> {
                if (newValue != null && !newValue.startsWith("---")) {
                    String currentAction = key.getMacroStepAction(index);
                    int code = switch (newValue) {
                        case "Shift" -> 0xE1;
                        case "Ctrl" -> 0xE0;
                        case "Alt" -> 0xE2;
                        case "Win" -> 0xE3;
                        default -> com.example.ahakey.model.HIDUsage.getCode(newValue);
                    };
                    key.updateMacroStep(index, currentAction, code);
                    studioState.markDirty(part);
                }
            });

            row.getChildren().addAll(indexLabel, actionCombo, keyCombo);
        }

        Button upBtn = new Button("↑");
        upBtn.getStyleClass().add("small-btn");
        upBtn.setDisable(index == 0);
        upBtn.setOnAction(e -> {
            key.moveMacroStep(index, index - 1);
            studioState.markDirty(part);
            rebuild();
        });

        Button downBtn = new Button("↓");
        downBtn.getStyleClass().add("small-btn");
        downBtn.setDisable(index == key.getMacroStepCount() - 1);
        downBtn.setOnAction(e -> {
            key.moveMacroStep(index, index + 1);
            studioState.markDirty(part);
            rebuild();
        });

        Button deleteBtn = new Button("×");
        deleteBtn.getStyleClass().add("small-btn");
        deleteBtn.getStyleClass().add("delete-btn");
        deleteBtn.setOnAction(e -> {
            key.removeMacroStep(index);
            studioState.markDirty(part);
            rebuild();
        });

        row.getChildren().addAll(upBtn, downBtn, deleteBtn);
        return row;
    }

    private VBox createDescriptionGroup(StudioPart part) {
        return createGroupBox(languageManager.getString("inspector.key-description"), () -> {
            VBox box = new VBox(8);

            TextField descField = new TextField(studioState.getKeyConfig(part).getDescription());
            descField.setPromptText(languageManager.getString("inspector.desc-placeholder"));
            descField.getStyleClass().add("text-field");
            descField.textProperty().addListener((obs, oldValue, newValue) -> studioState.updateKeyDescription(part, newValue));

            Label warning = new Label(languageManager.getString("inspector.desc-warning"));
            warning.getStyleClass().add("warning-note");

            Label actual = new Label(languageManager.getString("inspector.device-write") + studioState.getKeyConfig(part).getDescription());
            actual.getStyleClass().add("group-note");

            box.getChildren().addAll(descField, warning, actual);
            return box;
        });
    }

    private VBox createLightBarGroup() {
        VBox root = new VBox(16);
        ModeSlot mode = studioState.getSelectedMode();

        VBox brightnessBox = createGroupBox(languageManager.getString("inspector.light-brightness"), () -> {
            VBox box = new VBox(10);
            HBox row = new HBox(10);
            row.setAlignment(Pos.CENTER_LEFT);

            Spinner<Integer> spinner = new Spinner<>(1, 100, studioState.getLightBrightness());
            spinner.setEditable(true);
            spinner.setPrefWidth(96);
            spinner.valueProperty().addListener((obs, oldValue, newValue) -> {
                if (newValue != null) {
                    studioState.setLightBrightness(newValue);
                }
            });

            Button test = new Button(languageManager.getString("inspector.test-brightness"));
            test.setDisable(!deviceStatus.isConnected());
            test.setOnAction(e -> controller.sendLightBrightnessToDevice());

            row.getChildren().addAll(new Label(languageManager.getString("inspector.brightness")), spinner, test);
            Label note = new Label(languageManager.getString("inspector.brightness-note"));
            note.getStyleClass().add("group-note");
            note.setWrapText(true);
            box.getChildren().addAll(row, note);
            return box;
        });

        VBox statesBox = createGroupBox(mode.getTitle() + " " + languageManager.getString("inspector.ai-light-effects"), () -> {
            VBox box = new VBox(12);
            for (IDEState ideState : IDEState.values()) {
                VBox row = new VBox(6);
                HBox top = new HBox(8);
                top.setAlignment(Pos.CENTER_LEFT);

                Label title = new Label(ideState.getLabel());
                title.getStyleClass().add("mapping-title");
                title.setMinWidth(112);
                title.setPrefWidth(112);
                Label help = new Label("?");
                help.getStyleClass().add("mapping-hw");
                help.setMinWidth(18);
                javafx.scene.control.Tooltip.install(help, new javafx.scene.control.Tooltip(ideState.getDescription()));
                HBox spacer = new HBox();
                HBox.setHgrow(spacer, Priority.ALWAYS);

                ComboBox<LightEffectStyle> combo = new ComboBox<>();
                combo.getItems().addAll(LightEffectStyle.values());
                combo.setValue(studioState.getAiLightEffect(mode, ideState));
                combo.setMinWidth(180);
                combo.setPrefWidth(210);
                combo.valueProperty().addListener((obs, oldValue, newValue) -> {
                    if (newValue != null) {
                        studioState.setAiLightEffect(mode, ideState, newValue);
                    }
                });

                Button test = new Button(languageManager.getString("inspector.test"));
                test.setDisable(!deviceStatus.isConnected());
                test.setOnAction(e -> controller.previewLightEffectOnDevice(combo.getValue()));

                top.getChildren().addAll(title, help, spacer, combo, test);
                Label desc = new Label(ideState.getDescription());
                desc.getStyleClass().add("group-note");
                desc.setWrapText(true);
                row.getChildren().addAll(top, desc);
                box.getChildren().add(row);
                box.getChildren().add(new Separator());
            }

            HBox actions = new HBox(10);
            actions.setAlignment(Pos.CENTER_LEFT);
            Button sync = new Button(languageManager.getString("inspector.save-light-config"));
            sync.getStyleClass().add("button-prominent");
            sync.setDisable(!deviceStatus.isConnected());
            sync.setOnAction(e -> controller.syncCurrentModeLightConfig());
            actions.getChildren().add(sync);

            Label note = new Label(languageManager.getString("inspector.light-note") + " " + mode.getTitle());
            note.getStyleClass().add("group-note");
            note.setWrapText(true);
            box.getChildren().addAll(actions, note);
            return box;
        });

        root.getChildren().addAll(brightnessBox, statesBox);
        return root;
    }
    private Label caption(String text) {
        Label label = new Label(text);
        label.getStyleClass().add("group-note");
        label.setWrapText(true);
        return label;
    }

    private VBox createOledGroup() {
        VBox root = new VBox(16);
        OledModeDraft draft = studioState.getOledDraft();

        root.getChildren().add(createGroupBox(languageManager.getString("inspector.oled-preview"), () -> {
            VBox box = new VBox(12);

            // OLED 预览区域
            StackPane previewArea = new StackPane();
            previewArea.getStyleClass().add("oled-preview");
            ImageView previewImage = new ImageView();
            previewImage.setFitWidth(160);
            previewImage.setFitHeight(80);
            previewImage.setPreserveRatio(true);
            
            if (draft.getLocalAssetPath() != null) {
                try {
                    Image gifImage = new Image("file:" + draft.getLocalAssetPath());
                    previewImage.setImage(gifImage);
                } catch (Exception e) {
                    previewImage.setImage(null);
                }
            }
            
            previewArea.getChildren().add(previewImage);
            box.getChildren().add(previewArea);

            Label asset = new Label(
                draft.getLocalAssetPath() != null ? draft.getLocalAssetPath() : languageManager.getString("inspector.oled-none")
            );
            asset.getStyleClass().add("group-note");
            asset.setWrapText(true);

            HBox actions = new HBox(8);
            Button pick = new Button(languageManager.getString("inspector.oled-select"));
            pick.getStyleClass().add("button-prominent");
            pick.setMinWidth(80);
            pick.setOnAction(e -> {
                Window w = getScene() != null ? getScene().getWindow() : null;
                controller.selectOledGif(w);
                rebuild();
            });
            Button upload = new Button(languageManager.getString("inspector.oled-upload"));
            upload.getStyleClass().add("button-prominent");
            upload.setMinWidth(90);
            upload.disableProperty().bind(Bindings.createBooleanBinding(
                () -> !deviceStatus.isConnected() || studioState.uploadingOledProperty().get()
                    || draft.getLocalAssetPath() == null,
                deviceStatus.isConnectedProperty(),
                studioState.uploadingOledProperty(),
                draft.localAssetPathProperty()
            ));
            upload.textProperty().bind(Bindings.createStringBinding(
                () -> studioState.uploadingOledProperty().get() ? languageManager.getString("inspector.oled-uploading") : languageManager.getString("inspector.oled-upload"),
                studioState.uploadingOledProperty()
            ));
            upload.setOnAction(e -> controller.uploadCurrentOledToDevice());
            Button clear = new Button(languageManager.getString("inspector.clear"));
            clear.setMinWidth(60);
            clear.setOnAction(e -> {
                studioState.clearOledPreview();
                rebuild();
            });
            actions.getChildren().addAll(pick, upload, clear);

            Spinner<Integer> fps = new Spinner<>(1, 30, draft.getFramesPerSecond());
            fps.setEditable(true);
            fps.valueProperty().addListener((o, a, b) -> {
                if (b != null) {
                    draft.setFramesPerSecond(b);
                }
            });
            Label progress = new Label();
            progress.textProperty().bind(studioState.oledUploadDetailProperty());
            progress.getStyleClass().add("group-note");

            Label limits = new Label(languageManager.getString("inspector.oled-limits"));
            limits.getStyleClass().add("group-note");
            limits.setWrapText(true);

            box.getChildren().addAll(asset, actions, new Label(languageManager.getString("inspector.fps")), fps, progress, limits);
            return box;
        }));

        root.getChildren().add(createGroupBox(languageManager.getString("inspector.screen-text"), () -> {
            VBox box = new VBox(10);
            TextField titleField = new TextField(studioState.getOledSummary());
            titleField.getStyleClass().add("text-field");
            titleField.textProperty().addListener((obs, o, n) -> studioState.setOledSummary(n));
            TextField captionField = new TextField(studioState.getOledCaption());
            captionField.getStyleClass().add("text-field");
            captionField.textProperty().addListener((obs, o, n) -> studioState.setOledCaption(n));
            Label note = new Label(languageManager.getString("inspector.desc-warning"));
            note.getStyleClass().add("warning-note");
            note.setWrapText(true);
            box.getChildren().addAll(new Label(languageManager.getString("inspector.main-title")), titleField, new Label(languageManager.getString("inspector.sub-title")), captionField, note);
            return box;
        }));
        return root;
    }

    private VBox createToggleGroup() {
        return createGroupBox(languageManager.getString("inspector.switch-semantics"), () -> {
            VBox box = new VBox(10);

            ToggleGroup group = new ToggleGroup();
            ToggleButton autoButton = new ToggleButton(languageManager.getString("inspector.auto-approval"));
            autoButton.getStyleClass().add("binding-toggle");
            autoButton.setToggleGroup(group);

            ToggleButton manualButton = new ToggleButton(languageManager.getString("inspector.manual-approval"));
            manualButton.getStyleClass().add("binding-toggle");
            manualButton.setToggleGroup(group);

            autoButton.setOnAction(event -> controller.updateSwitchState(0));
            manualButton.setOnAction(event -> controller.updateSwitchState(1));

            // 绑定选中状态到 deviceStatus
            autoButton.selectedProperty().bind(Bindings.createBooleanBinding(
                () -> deviceStatus.isAutoApproval(),
                deviceStatus.switchStateProperty()
            ));
            manualButton.selectedProperty().bind(Bindings.createBooleanBinding(
                () -> !deviceStatus.isAutoApproval(),
                deviceStatus.switchStateProperty()
            ));

            Label note = new Label(languageManager.getString("inspector.switch-note"));
            note.getStyleClass().add("group-note");

            box.getChildren().addAll(new HBox(4, autoButton, manualButton), note);
            return box;
        });
    }

    private VBox createGroupBox(String title, Supplier<VBox> contentProvider) {
        VBox groupBox = new VBox(4);
        groupBox.getStyleClass().add("group-box");

        Label titleLabel = new Label(title);
        titleLabel.getStyleClass().add("group-box-title");

        VBox inner = contentProvider.get();
        inner.setPadding(new Insets(4, 0, 0, 0));

        groupBox.getChildren().addAll(titleLabel, inner);
        return groupBox;
    }

    private String iconFor(StudioPart part) {
        if (part.isKey()) {
            return "⌨";
        }
        return switch (part) {
            case LIGHT_BAR -> "≋";
            case OLED -> "▣";
            case TOGGLE_SWITCH -> "◫";
            default -> "⌨";
        };
    }

}

