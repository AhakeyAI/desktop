package com.example.ahakey.view;

import com.example.ahakey.app.StudioController;
import com.example.ahakey.model.DeviceStatus;
import com.example.ahakey.model.AiRuntimeDisplayMode;
import com.example.ahakey.model.AiRuntimeSession;
import com.example.ahakey.model.AiRuntimeSlotBinding;
import com.example.ahakey.model.KeyConfig;
import com.example.ahakey.model.IDEState;
import com.example.ahakey.model.LightBarPreviewState;
import com.example.ahakey.model.LightEffectStyle;
import com.example.ahakey.model.ModeSlot;
import com.example.ahakey.model.OledModeDraft;
import com.example.ahakey.model.StudioPart;
import com.example.ahakey.model.StudioState;
import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.protocol.AhaKeyResponseParser;
import com.example.ahakey.util.LanguageManager;
import javafx.scene.control.Spinner;
import javafx.stage.Window;
import com.example.ahakey.service.AgentManager;
import com.example.ahakey.service.HookInstaller;
import javafx.beans.binding.Bindings;
import javafx.concurrent.Task;
import javafx.geometry.Insets;
import javafx.geometry.Pos;
import javafx.scene.control.Button;
import javafx.scene.control.ComboBox;
import javafx.scene.control.Label;
import javafx.scene.control.OverrunStyle;
import javafx.scene.control.RadioButton;
import javafx.scene.control.ScrollPane;
import javafx.scene.control.Separator;
import javafx.scene.control.TextField;
import javafx.scene.control.Tooltip;
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

import java.util.ArrayList;
import java.util.List;
import java.util.LinkedHashMap;
import java.util.Map;
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
        studioState.displayConfig().revision.addListener((o, a, b) -> {
            if (studioState.getSelectedPart() == StudioPart.OLED) rebuild();
        });
        studioState.displayConfig().loading.addListener((o, a, b) -> {
            if (!b && studioState.getSelectedPart() == StudioPart.LIGHT_BAR) rebuild();
        });
        studioState.displayConfig().busy.addListener((o, a, b) -> {
            if (!b && studioState.getSelectedPart() == StudioPart.LIGHT_BAR) rebuild();
        });
        studioState.lightBarPreviewProperty().addListener((obs, oldValue, newValue) -> rebuild());
        studioState.cp4cInputConfigEnabledProperty().addListener((obs, oldValue, newValue) -> rebuild());
        studioState.inputBaselineRevisionProperty().addListener((obs, oldValue, newValue) -> rebuild());
        controller.getAiRuntimeDisplayService().displayModeProperty().addListener((obs, oldValue, newValue) -> rebuild());
        controller.getAiRuntimeDisplayService().getSlots().addListener((javafx.collections.ListChangeListener<AiRuntimeSlotBinding>) change -> rebuild());
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
            // KEY1 始终使用自定义快捷键模式
            KeyConfig key1 = studioState.getKeyConfig(StudioPart.KEY1);
            if (key1.getVoicePreset() != com.example.ahakey.model.VoicePreset.CUSTOM) {
                key1.setVoicePreset(com.example.ahakey.model.VoicePreset.CUSTOM);
            }
            body.getChildren().add(createKeyBindingGroup(part));
            body.getChildren().add(createSimulateKeyGroup(part));
            body.getChildren().add(createDescriptionGroup(part));
        } else if (part.isKey()) {
            body.getChildren().add(createKeyBindingGroup(part));
            body.getChildren().add(createDescriptionGroup(part));
        } else if (part == StudioPart.LIGHT_BAR) {
            body.getChildren().add(createLightBarGroup());
        } else if (part == StudioPart.OLED) {
            body.getChildren().add(createOledGroup());
        } else if (part == StudioPart.TOGGLE_SWITCH) {
            body.getChildren().add(createToggleGroup());
        }
    }

    private VBox createSimulateKeyGroup(StudioPart part) {
        return createGroupBox(languageManager.getString("inspector.simulate-key"), () -> {
            VBox box = new VBox(8);
            KeyConfig key = studioState.getKeyConfig(part);
            var voice = controller.getVoiceRelay();

            Button simulate = new Button(languageManager.getString("inspector.simulate-key1"));
            simulate.getStyleClass().add("button-prominent");
            simulate.setOnAction(e -> voice.simulateKeyByHid(key.getHidCode()));

            Label hint = new Label();
            hint.textProperty().bind(voice.lastSimulateHintProperty());
            hint.getStyleClass().add("warning-note");

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
        VBox box = new VBox(12);
        KeyConfig key = studioState.getKeyConfig(part);

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
                    studioState.markDirty(part);
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
                
                studioState.markDirty(part);
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
        var display = studioState.displayConfig();
        ModeSlot mode = studioState.getSelectedMode();

        VBox brightnessBox = createGroupBox(languageManager.getString("inspector.light-brightness"), () -> {
            VBox box = new VBox(10);
            HBox row = new HBox(10);
            row.setAlignment(Pos.CENTER_LEFT);

            Spinner<Integer> spinner = brightnessSpinner(display);

            Button test = new Button(languageManager.getString("display.preview"));
            test.disableProperty().bind(display.writeReady.not().or(display.busy)
                    .or(controller.getAiRuntimeDisplayService().modeChangePendingProperty()));
            test.setOnAction(e -> { spinner.commitValue(); controller.sendLightBrightnessToDevice(); });

            Button save = new Button(languageManager.getString("display.save-brightness"));
            save.disableProperty().bind(display.writeReady.not().or(display.busy)
                    .or(controller.getAiRuntimeDisplayService().modeChangePendingProperty()));
            save.setOnAction(e -> { spinner.commitValue(); controller.saveGlobalLightBrightness(); });
            spinner.disableProperty().bind(display.busy);
            row.getChildren().addAll(new Label(languageManager.getString("inspector.brightness")), spinner, test, save);
            Label note = new Label(languageManager.getString("display.global-brightness"));
            note.getStyleClass().add("group-note");
            note.setWrapText(true);
            box.getChildren().addAll(row, note);
            return box;
        });

        VBox statesBox = createGroupBox(mode.getTitle() + " · " + languageManager.getString("display.single-effects"), () -> {
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
                combo.setValue(LightEffectStyle.fromCodeOrNull(display.effect(mode.getIndex(), ideState.getCode())));
                combo.setPromptText(languageManager.getString("display.unknown-effect"));
                combo.setMinWidth(100);
                combo.setPrefWidth(180);
                HBox.setHgrow(combo, Priority.ALWAYS);
                combo.disableProperty().bind(display.busy);
                combo.valueProperty().addListener((obs, oldValue, newValue) -> {
                    if (newValue != null) {
                        display.editEffect(mode.getIndex(), ideState.getCode(), newValue.getCode() & 255);
                    }
                });

                Button test = new Button(languageManager.getString("display.preview"));
                test.disableProperty().bind(Bindings.createBooleanBinding(
                        () -> !display.writeReady.get() || display.busy.get() || combo.getValue() == null || combo.getValue() == LightEffectStyle.OFF,
                        display.writeReady, display.busy, combo.valueProperty()));
                test.setOnAction(e -> controller.previewLightEffectOnDevice(combo.getValue()));

                top.getChildren().addAll(title, help, spacer, combo, test);
                Label desc = new Label(ideState.getDescription());
                Label draftStatus = new Label();
                draftStatus.textProperty().bind(Bindings.createStringBinding(
                        () -> display.effectDirty(mode.getIndex(), ideState.getCode()) ? "草稿" : "",
                        display.revision));
                desc.getStyleClass().add("group-note");
                desc.setWrapText(true);
                row.getChildren().addAll(top, desc, draftStatus);
                box.getChildren().add(row);
                box.getChildren().add(new Separator());
            }

            HBox actions = new HBox(10);
            actions.setAlignment(Pos.CENTER_LEFT);
            Button sync = new Button(languageManager.getString("inspector.save-light-config"));
            sync.getStyleClass().add("button-prominent");
            sync.disableProperty().bind(display.writeReady.not().or(display.busy));
            sync.setOnAction(e -> controller.syncCurrentModeLightConfig());
            actions.getChildren().add(sync);

            Label note = new Label(mode.getTitle() + " · SINGLE AI 状态灯效");
            note.getStyleClass().add("group-note");
            note.setWrapText(true);
            box.getChildren().addAll(actions, note);
            return box;
        });

        addDisplayReason(brightnessBox, null);
        addDisplayReason(statesBox, AiRuntimeDisplayMode.SINGLE);
        root.getChildren().addAll(createAiRuntimeGroup(true), brightnessBox, statesBox, createAiRuntimeGroup(false), displayActions());
        return root;
    }

    private static Spinner<Integer> brightnessSpinner(com.example.ahakey.model.DisplayConfigState display) {
        Spinner<Integer> spinner = new Spinner<>(1, 100, display.brightness.get());
        spinner.setEditable(true);
        spinner.setPrefWidth(96);
        spinner.getValueFactory().setConverter(new javafx.util.StringConverter<>() {
            @Override public String toString(Integer value) { return Integer.toString(value); }
            @Override public Integer fromString(String text) {
                if (text == null || text.isBlank()) return spinner.getValue();
                try { return Math.max(1, Math.min(100, Integer.parseInt(text))); }
                catch (NumberFormatException e) { return spinner.getValue(); }
            }
        });
        spinner.getEditor().setTextFormatter(new javafx.scene.control.TextFormatter<String>(change ->
                change.getControlNewText().matches("[0-9]{0,3}") ? change : null));
        spinner.valueProperty().addListener((o, a, b) -> { if (b != null) display.editBrightness(b); });
        return spinner;
    }

    private void bindRuntimeSection(VBox section, com.example.ahakey.service.AiRuntimeDisplayService service, AiRuntimeDisplayMode mode) {
        bindRuntimeSection(section, service.displayModeProperty(), mode, studioState.displayConfig().busy, service.modeChangePendingProperty());
    }

    private static void bindRuntimeSection(VBox section, javafx.beans.property.ObjectProperty<AiRuntimeDisplayMode> current,
            AiRuntimeDisplayMode mode, javafx.beans.property.BooleanProperty busy, javafx.beans.property.BooleanProperty pending) {
        section.getStyleClass().add("runtime-mode-section");
        section.disableProperty().bind(current.isNotEqualTo(mode).or(busy).or(pending));
    }

    private void addDisplayReason(VBox group, AiRuntimeDisplayMode target) {
        var display = studioState.displayConfig();
        var runtime = controller.getAiRuntimeDisplayService();
        decorateDisplaySection(group, display, runtime.displayModeProperty(), runtime.modeChangePendingProperty(), target);
    }

    private static void decorateDisplaySection(VBox group, com.example.ahakey.model.DisplayConfigState display,
            javafx.beans.property.ObjectProperty<AiRuntimeDisplayMode> current,
            javafx.beans.property.BooleanProperty pending, AiRuntimeDisplayMode target) {
        VBox operations = (VBox)group.getChildren().get(1);
        Label reason = displayReason(display, current, pending, target);
        group.getChildren().add(1, reason);
        if (target != null) bindRuntimeSection(operations, current, target, display.busy, pending);
    }

    private static Label displayReason(com.example.ahakey.model.DisplayConfigState display,
            javafx.beans.property.ObjectProperty<AiRuntimeDisplayMode> current,
            javafx.beans.property.BooleanProperty pending, AiRuntimeDisplayMode target) {
        Label reason = new Label();
        reason.setWrapText(true);
        reason.getStyleClass().add("display-disabled-reason");
        reason.textProperty().bind(Bindings.createStringBinding(() -> {
            String key = display.disabledReasonKey.get();
            if (key.isEmpty() && display.busy.get()) key = "display.operation-busy";
            if (key.isEmpty() && display.loading.get()) key = "display.syncing";
            if (key.isEmpty() && pending.get()) key = "display.mode-pending";
            if (key.isEmpty() && target != null && current.get() != target)
                key = target == AiRuntimeDisplayMode.SINGLE ? "display.single-disabled" : "display.multi-disabled";
            return key.isEmpty() ? "" : LanguageManager.getInstance().getString(key);
        }, display.disabledReasonKey, display.busy, display.loading, current, pending));
        reason.visibleProperty().bind(reason.textProperty().isNotEmpty());
        reason.managedProperty().bind(reason.visibleProperty());
        return reason;
    }

    private VBox createAiRuntimeGroup(boolean modeOnly) {
        VBox group = createGroupBox(languageManager.getString(modeOnly ? "display.runtime-mode" : "display.multi-slots"), () -> {
            VBox box = new VBox(12);
            var service = controller.getAiRuntimeDisplayService();

            ToggleGroup modeGroup = new ToggleGroup();
            ToggleButton single = new ToggleButton("单任务");
            ToggleButton multi = new ToggleButton("多任务");
            single.setToggleGroup(modeGroup);
            multi.setToggleGroup(modeGroup);
            single.setSelected(service.getDisplayMode() == AiRuntimeDisplayMode.SINGLE);
            multi.setSelected(service.getDisplayMode() == AiRuntimeDisplayMode.MULTI);
            single.disableProperty().bind(studioState.displayConfig().busy.or(studioState.displayConfig().loading)
                    .or(service.modeChangePendingProperty()).or(studioState.displayConfig().capabilityReady.and(studioState.displayConfig().writeReady.not())));
            multi.disableProperty().bind(single.disableProperty().or(studioState.displayConfig().writeReady.not()));
            single.setOnAction(e -> {
                controller.setAiRuntimeDisplayMode(AiRuntimeDisplayMode.SINGLE);
                single.setSelected(service.getDisplayMode() == AiRuntimeDisplayMode.SINGLE);
                multi.setSelected(service.getDisplayMode() == AiRuntimeDisplayMode.MULTI);
            });
            multi.setOnAction(e -> {
                controller.setAiRuntimeDisplayMode(AiRuntimeDisplayMode.MULTI);
                single.setSelected(service.getDisplayMode() == AiRuntimeDisplayMode.SINGLE);
                multi.setSelected(service.getDisplayMode() == AiRuntimeDisplayMode.MULTI);
            });
            HBox modeRow = new HBox(8, new Label("展示模式"), single, multi);
            modeRow.setAlignment(Pos.CENTER_LEFT);
            if (modeOnly) { box.getChildren().add(modeRow); return box; }

            VBox slotBox = new VBox(6);
            for (AiRuntimeSlotBinding slot : service.getSlots()) {
                Label label = new Label(slotSummary(slot) + " / " + slot.runtimeState().getTitle());
                label.getStyleClass().add("group-note");
                label.setWrapText(true);
                slotBox.getChildren().add(label);
            }

            HBox actions = new HBox(8);
            Button manage = new Button("管理关注任务槽");
            manage.setOnAction(e -> showAiRuntimeSlotDialog());
            Button apply = new Button("应用到键盘");
            apply.getStyleClass().add("button-prominent");
            apply.disableProperty().bind(studioState.displayConfig().writeReady.not().or(studioState.displayConfig().busy)
                    .or(studioState.displayConfig().loading).or(service.modeChangePendingProperty()));
            apply.setOnAction(e -> controller.applyAiRuntimeToKeyboard(getScene() == null ? null : getScene().getWindow()));
            actions.getChildren().addAll(manage, apply);

            Label support = runtimeSlotSupport();

            box.getChildren().addAll(slotBox, actions, support);
            return box;
        });
        addDisplayReason(group, modeOnly ? null : AiRuntimeDisplayMode.MULTI);
        return group;
    }

    private static Label runtimeSlotSupport() {
        Label support = new Label(LanguageManager.getInstance().getString("display.slot-local-note"));
        support.getStyleClass().add("group-note");
        support.setWrapText(true);
        return support;
    }

    private void showAiRuntimeSlotDialog() {
        var service = controller.getAiRuntimeDisplayService();
        javafx.scene.control.Dialog<Void> dialog = new javafx.scene.control.Dialog<>();
        dialog.setTitle("管理关注任务槽");
        dialog.initOwner(getScene() == null ? null : getScene().getWindow());
        dialog.getDialogPane().getButtonTypes().add(javafx.scene.control.ButtonType.CLOSE);

        VBox root = new VBox(12);
        root.setPadding(new Insets(14));
        root.setPrefWidth(620);
        root.setPrefHeight(560);

        javafx.scene.control.TreeView<Object> tree = new javafx.scene.control.TreeView<>();
        tree.setShowRoot(false);
        tree.setPrefHeight(300);
        tree.setRoot(loadingRuntimeSessionTree());
        tree.setCellFactory(view -> new javafx.scene.control.TreeCell<>() {
            @Override
            protected void updateItem(Object item, boolean empty) {
                super.updateItem(item, empty);
                if (empty || item == null) {
                    setText(null);
                    setDisable(false);
                } else if (item instanceof AiRuntimeSession session) {
                    int bound = service.findBoundSlot(session.provider(), session.id());
                    setText(session.displayTitle() + "   " + session.timeLabel() + (bound >= 0 ? "   已绑定 槽位 " + (bound + 1) : ""));
                    setDisable(bound >= 0);
                } else {
                    setText(item.toString());
                    setDisable(false);
                }
            }
        });

        VBox slotsBox = new VBox(8);
        refreshRuntimeSlotRows(slotsBox, tree, false, false);

        Label slotGuide = caption("选择“主显示”后，键盘屏幕会优先展示这个会话；每个槽位固定对应灯条上的两颗灯珠。");
        Label lightGuide = new Label("灯效：运行中=绿灯常亮，等待人工确认=黄灯常亮，完成=红灯常亮，空闲=熄灭。");
        lightGuide.getStyleClass().add("group-note");
        lightGuide.setWrapText(true);

        VBox dirBox = new VBox(8);
        dirBox.getChildren().add(createDataDirRow("Codex 数据目录", service.getCodexDataDir(), value -> service.setCodexDataDir(value), dialog));
        dirBox.getChildren().add(createDataDirRow("Cursor 数据目录", service.getCursorDataDir(), value -> service.setCursorDataDir(value), dialog));

        Button apply = new Button("应用到键盘");
        apply.getStyleClass().add("button-prominent");
        apply.setOnAction(e -> controller.applyAiRuntimeToKeyboard(dialog.getDialogPane().getScene().getWindow()));
        apply.disableProperty().bind(studioState.displayConfig().writeReady.not()
                .or(studioState.displayConfig().loading).or(service.modeChangePendingProperty()));

        Button hookManager = new Button("去 Hook 管理");
        hookManager.setOnAction(e -> controller.openHookManager());

        Label note = new Label("只显示 Codex / Cursor 会话摘要和元信息，不展示完整聊天内容。");
        note.getStyleClass().add("group-note");
        note.setWrapText(true);
        HBox actionRow = new HBox(8, apply, hookManager);
        root.getChildren().addAll(dirBox, tree, slotGuide, slotsBox, lightGuide, actionRow, note);
        bindRuntimeSection(root, service, AiRuntimeDisplayMode.MULTI);
        dialog.getDialogPane().setContent(root);
        Task<RuntimeTreeLoad> loadTask = new Task<>() {
            @Override
            protected RuntimeTreeLoad call() {
                HookInstaller.HookStatus loadedCodexStatus = controller.getAiRuntimeHookStatus("Codex");
                HookInstaller.HookStatus loadedCursorStatus = controller.getAiRuntimeHookStatus("Cursor");
                return new RuntimeTreeLoad(
                    buildRuntimeSessionTree(loadedCodexStatus, loadedCursorStatus),
                    loadedCodexStatus == HookInstaller.HookStatus.LATEST,
                    loadedCursorStatus == HookInstaller.HookStatus.LATEST
                );
            }
        };
        loadTask.setOnSucceeded(e -> {
            RuntimeTreeLoad loaded = loadTask.getValue();
            tree.setRoot(loaded.root());
            refreshRuntimeSlotRows(slotsBox, tree, loaded.codexHookLatest(), loaded.cursorHookLatest());
        });
        loadTask.setOnFailed(e -> {
            javafx.scene.control.TreeItem<Object> rootItem = new javafx.scene.control.TreeItem<>("root");
            Throwable error = loadTask.getException();
            rootItem.getChildren().add(new javafx.scene.control.TreeItem<>(
                "加载会话失败：" + (error == null ? "未知错误" : error.getMessage())
            ));
            tree.setRoot(rootItem);
        });
        dialog.setOnHidden(e -> loadTask.cancel());
        Thread loader = new Thread(loadTask, "ai-runtime-session-load");
        loader.setDaemon(true);
        loader.start();
        dialog.showAndWait();
    }

    private javafx.scene.control.TreeItem<Object> loadingRuntimeSessionTree() {
        javafx.scene.control.TreeItem<Object> root = new javafx.scene.control.TreeItem<>("root");
        root.getChildren().add(new javafx.scene.control.TreeItem<>("正在加载 Codex / Cursor 会话..."));
        return root;
    }

    private record RuntimeTreeLoad(
        javafx.scene.control.TreeItem<Object> root,
        boolean codexHookLatest,
        boolean cursorHookLatest
    ) {}

    private void refreshRuntimeSlotRows(
        VBox slotsBox,
        javafx.scene.control.TreeView<Object> tree,
        boolean codexHookLatest,
        boolean cursorHookLatest
    ) {
        var service = controller.getAiRuntimeDisplayService();
        slotsBox.getChildren().clear();
        ToggleGroup primaryGroup = new ToggleGroup();
        for (int i = 0; i < 4; i++) {
            final int slotIndex = i;
            AiRuntimeSlotBinding slot = service.getSlots().get(i);
            HBox row = new HBox(8);
            row.setAlignment(Pos.CENTER_LEFT);

            RadioButton primary = new RadioButton("主显示");
            primary.setToggleGroup(primaryGroup);
            primary.setMinWidth(96);
            primary.setPrefWidth(96);
            String unavailableReason = service.slotUnavailableReason(slot, codexHookLatest, cursorHookLatest);
            boolean primarySelectable = slot.isBound() && unavailableReason == null;
            primary.setSelected(service.getPrimarySlotIndex() == slotIndex && primarySelectable);
            primary.setDisable(!primarySelectable);
            primary.setOnAction(e -> {
                if (!primary.isDisabled()) {
                    service.setPrimarySlotIndex(slotIndex);
                    refreshRuntimeSlotRows(slotsBox, tree, codexHookLatest, cursorHookLatest);
                }
            });

            Label summary = new Label(slotSummary(slot) + "｜" + slotAvailabilityText(slot, unavailableReason));
            summary.getStyleClass().add("group-note");
            summary.setWrapText(false);
            summary.setTextOverrun(OverrunStyle.ELLIPSIS);
            summary.setMaxWidth(Double.MAX_VALUE);
            Tooltip summaryTip = new Tooltip(slotSummary(slot) + "｜" + slotAvailabilityText(slot, unavailableReason));
            summaryTip.setWrapText(true);
            summaryTip.setMaxWidth(520);
            summary.setTooltip(summaryTip);

            Button bind = new Button("绑定到槽位 " + (i + 1));
            bind.setMinWidth(126);
            bind.setPrefWidth(126);
            bind.setOnAction(e -> {
                Object selected = tree.getSelectionModel().getSelectedItem() == null
                    ? null
                    : tree.getSelectionModel().getSelectedItem().getValue();
                if (selected instanceof AiRuntimeSession session) {
                    service.bindSlot(slotIndex, session);
                    tree.refresh();
                    refreshRuntimeSlotRows(slotsBox, tree, codexHookLatest, cursorHookLatest);
                    rebuild();
                }
            });

            Button clear = new Button("解绑");
            clear.setMinWidth(72);
            clear.setPrefWidth(72);
            clear.setOnAction(e -> {
                service.clearSlot(slotIndex);
                tree.refresh();
                refreshRuntimeSlotRows(slotsBox, tree, codexHookLatest, cursorHookLatest);
                rebuild();
            });

            HBox buttons = new HBox(8, bind, clear);
            buttons.setMinWidth(206);
            buttons.setPrefWidth(206);
            row.getChildren().addAll(primary, summary, buttons);
            HBox.setHgrow(summary, Priority.ALWAYS);
            slotsBox.getChildren().add(row);
        }
    }

    private HBox createDataDirRow(
        String labelText,
        String value,
        java.util.function.Consumer<String> save,
        javafx.scene.control.Dialog<Void> dialog
    ) {
        TextField field = new TextField(value);
        HBox.setHgrow(field, Priority.ALWAYS);
        Button saveButton = new Button("保存");
        saveButton.setOnAction(e -> {
            save.accept(field.getText());
            dialog.close();
            showAiRuntimeSlotDialog();
        });
        Button choose = new Button("选择");
        choose.setOnAction(e -> {
            javafx.stage.DirectoryChooser chooser = new javafx.stage.DirectoryChooser();
            chooser.setTitle("选择" + labelText);
            java.io.File selected = chooser.showDialog(dialog.getDialogPane().getScene().getWindow());
            if (selected != null) {
                save.accept(selected.getAbsolutePath());
                dialog.close();
                showAiRuntimeSlotDialog();
            }
        });
        HBox row = new HBox(8, new Label(labelText), field, saveButton, choose);
        row.setAlignment(Pos.CENTER_LEFT);
        return row;
    }

    private javafx.scene.control.TreeItem<Object> buildRuntimeSessionTree(
        HookInstaller.HookStatus codexStatus,
        HookInstaller.HookStatus cursorStatus
    ) {
        javafx.scene.control.TreeItem<Object> root = new javafx.scene.control.TreeItem<>("root");
        root.getChildren().add(buildProviderTree("Codex", codexStatus));
        root.getChildren().add(buildProviderTree("Cursor", cursorStatus));
        return root;
    }

    private javafx.scene.control.TreeItem<Object> buildProviderTree(String provider, HookInstaller.HookStatus status) {
        javafx.scene.control.TreeItem<Object> providerItem = new javafx.scene.control.TreeItem<>(provider);
        providerItem.setExpanded(true);
        var service = controller.getAiRuntimeDisplayService();
        if (status != HookInstaller.HookStatus.LATEST) {
            providerItem.getChildren().add(new javafx.scene.control.TreeItem<>("需安装/更新 Hook"));
            providerItem.getChildren().add(new javafx.scene.control.TreeItem<>("去 Hook 管理"));
            return providerItem;
        }
        if (!service.isDataDirValid(provider)) {
            providerItem.getChildren().add(new javafx.scene.control.TreeItem<>("数据目录无效，请重新选择目录"));
            return providerItem;
        }
        List<AiRuntimeSession> sessions = service.discoverSessions(provider);
        if (sessions.isEmpty()) {
            providerItem.getChildren().add(new javafx.scene.control.TreeItem<>("暂无可绑定任务"));
            return providerItem;
        }
        Map<String, List<AiRuntimeSession>> byProject = new LinkedHashMap<>();
        for (AiRuntimeSession session : sessions) {
            byProject.computeIfAbsent(session.projectName(), key -> new ArrayList<>()).add(session);
        }
        byProject.entrySet().stream()
            .sorted((a, b) -> Long.compare(sessionMillis(b.getValue().get(0)), sessionMillis(a.getValue().get(0))))
            .forEach(entry -> {
                javafx.scene.control.TreeItem<Object> project = new javafx.scene.control.TreeItem<>(entry.getKey());
                for (AiRuntimeSession session : entry.getValue()) {
                    project.getChildren().add(new javafx.scene.control.TreeItem<>(session));
                }
                project.setExpanded(true);
                providerItem.getChildren().add(project);
            });
        return providerItem;
    }

    private long sessionMillis(AiRuntimeSession session) {
        return session.updatedAt() == null ? 0L : session.updatedAt().toEpochMilli();
    }

    private String slotAvailabilityText(AiRuntimeSlotBinding slot, String unavailableReason) {
        if (!slot.isBound()) {
            return "未绑定";
        }
        return unavailableReason == null ? "可用" : unavailableReason;
    }

    private String slotSummary(AiRuntimeSlotBinding slot) {
        String slotLabel = "槽位 " + (slot == null ? "" : slot.getSlotIndex() + 1);
        String lightLabel = slot == null ? "" : "｜灯珠 " + slotLightRange(slot.getSlotIndex());
        if (slot == null || !slot.isBound()) {
            return slotLabel + lightLabel;
        }
        return slotLabel
            + lightLabel
            + "｜" + slot.getProvider()
            + "｜" + slot.displayProjectName()
            + "｜" + slot.displayTitle()
            + "｜" + slotTimeLabel(slot.getUpdatedAtMillis());
    }

    private String slotLightRange(int slotIndex) {
        int first = slotIndex * 2 + 1;
        return first + "-" + (first + 1);
    }

    private String slotTimeLabel(long updatedAtMillis) {
        if (updatedAtMillis <= 0) {
            return "最近时间未知";
        }
        long minutes = Math.max(0, (System.currentTimeMillis() - updatedAtMillis) / 60000);
        if (minutes < 60) {
            return minutes + " 分前";
        }
        long hours = minutes / 60;
        if (hours < 24) {
            return hours + " 小时前";
        }
        return (hours / 24) + " 天前";
    }
    private Label caption(String text) {
        Label label = new Label(text);
        label.getStyleClass().add("group-note");
        label.setWrapText(true);
        return label;
    }

    private VBox createOledGroup() {
        var display = studioState.displayConfig();
        VBox root = new VBox(12);
        ToggleGroup tabs = new ToggleGroup();
        HBox groups = new HBox(6);
        String[] names = {languageManager.getString("display.default-screen"), "SINGLE", "MULTI"};
        for (int group = 0; group < names.length; group++) {
            final int selectedGroup = group;
            ToggleButton button = new ToggleButton(names[group]);
            button.setToggleGroup(tabs);
            button.setSelected(display.group.get() == group);
            button.disableProperty().bind(display.busy);
            button.setOnAction(e -> controller.getDisplayConfigService().select(selectedGroup, display.substate.get()));
            groups.getChildren().add(button);
        }
        root.getChildren().add(groups);
        if (display.group.get() == 2) root.getChildren().add(caption(
                languageManager.getString("display.multi-note")));
        if (display.group.get() == 2) root.getChildren().add(caption(languageManager.getString("display.multi-mode-guide")));
        int count = display.group.get() == 0 ? 1 : 3;
        for (int sub = 0; sub < count; sub++) {
            int index = display.group.get() == 2 ? 16 + sub : studioState.getSelectedMode().getIndex() * 4 + (display.group.get() == 0 ? 0 : sub + 1);
            final int selectedSub = sub;
            var resource = display.resources.get(index);
            VBox card = new VBox(8);
            card.getStyleClass().add("oled-resource");
            if (index == display.selectedEntry.get()) card.getStyleClass().add("oled-resource-selected");
            card.disableProperty().bind(display.busy.or(display.ready.not()));
            Label title = new Label(resource.targetName());
            title.setWrapText(true);
            Label status = new Label(resource.statusText());
            status.setWrapText(true);
            Label frames = new Label(String.format(languageManager.getString("display.frames"), resource.asset() == null ? 0 : resource.asset().frames(), resource.capacity()));
            FlowPane actions = new FlowPane(8, 6);
            Button choose = new Button(languageManager.getString(resource.asset() == null ? "display.choose-file" : "display.replace-file"));
            choose.setOnAction(e -> {
                controller.getDisplayConfigService().select(display.group.get(), selectedSub);
                controller.selectOledGif(getScene() == null ? null : getScene().getWindow());
            });
            Button clear = new Button();
            clear.setGraphic(com.example.ahakey.util.Icons.xCircle("16px"));
            clear.setTooltip(new Tooltip(languageManager.getString("display.clear-local")));
            clear.setDisable(resource.asset() == null);
            clear.setOnAction(e -> {
                controller.getDisplayConfigService().select(display.group.get(), selectedSub);
                controller.clearCurrentOled();
            });
            actions.getChildren().addAll(choose, clear);
            card.getChildren().addAll(title, status, frames, actions);
            card.setOnMouseClicked(e -> {
                if (display.selectedEntry.get() != index)
                    controller.getDisplayConfigService().select(display.group.get(), selectedSub);
            });
            root.getChildren().add(card);
        }
        Button upload = new Button(languageManager.getString("display.upload-apply"));
        upload.getStyleClass().add("button-prominent");
        upload.disableProperty().bind(Bindings.createBooleanBinding(
                () -> !display.writeReady.get() || display.busy.get() || !display.current().canUpload()
                        || controller.getAiRuntimeDisplayService().modeChangePendingProperty().get(),
                display.writeReady, display.busy, display.revision, controller.getAiRuntimeDisplayService().modeChangePendingProperty()));
        upload.textProperty().bind(Bindings.when(studioState.uploadingOledProperty()).then(languageManager.getString("display.uploading")).otherwise(languageManager.getString("display.upload-apply")));
        upload.setOnAction(e -> controller.uploadCurrentOledToDevice());
        root.getChildren().add(upload);
        Label progress = new Label();
        progress.textProperty().bind(display.progress);
        progress.setWrapText(true);
        root.getChildren().addAll(progress, displayActions());
        return root;
    }

    private VBox displayActions() {
        var display = studioState.displayConfig();
        Button refresh = new Button();
        refresh.setGraphic(com.example.ahakey.util.Icons.refresh("16px"));
        refresh.setTooltip(new Tooltip(languageManager.getString("display.refresh")));
        refresh.disableProperty().bind(deviceStatus.isConnectedProperty().not().or(display.busy).or(display.loading));
        refresh.setOnAction(e -> controller.refreshDisplayCapabilities());
        Label message = new Label();
        message.setWrapText(true);
        message.textProperty().bind(display.message);
        Label loading = new Label();
        loading.textProperty().bind(Bindings.when(display.loading).then(languageManager.getString("display.syncing")).otherwise(""));
        Label reason = displayReason(display, controller.getAiRuntimeDisplayService().displayModeProperty(),
                controller.getAiRuntimeDisplayService().modeChangePendingProperty(), null);
        return new VBox(8, new FlowPane(8, 6, refresh), reason, loading, message);
    }

    private VBox createToggleGroup() {
        if (studioState.isCp4cInputConfigEnabled()) {
            return createCp4cToggleGroup();
        }
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

    private VBox createCp4cToggleGroup() {
        return createGroupBox(languageManager.getString("inspector.switch-semantics"), () -> {
            VBox box = new VBox(12);
            AhaKeyResponseParser.SideSwitchConfig config = studioState.getSideSwitchConfig();

            Label state = new Label("当前物理位置：" + sideSwitchPhysicalLabel(config.physicalPosition()));
            state.getStyleClass().add("group-note");

            Label readback = new Label();
            readback.textProperty().bind(Bindings.createStringBinding(() -> {
                String status = studioState.inputReadbackStatusProperty().get();
                if (status == null || status.isBlank()) {
                    return "CP4C 侧拨配置来自键盘回读。";
                }
                return status;
            }, studioState.inputReadbackStatusProperty()));
            readback.getStyleClass().add("group-note");
            readback.setWrapText(true);

            Label failure = new Label();
            failure.textProperty().bind(studioState.inputFailureStatusProperty());
            failure.visibleProperty().bind(studioState.inputFailureStatusProperty().isNotEmpty());
            failure.managedProperty().bind(failure.visibleProperty());
            failure.getStyleClass().add("warning-note");
            failure.setWrapText(true);

            box.getChildren().addAll(
                state,
                createSideSwitchBindingRow("上拨", AhaKeyProtocol.SIDE_SWITCH_POSITION_UP, config.up()),
                createSideSwitchBindingRow("下拨", AhaKeyProtocol.SIDE_SWITCH_POSITION_DOWN, config.down())
            );
            if (config.up().binding() == AhaKeyProtocol.SIDE_SWITCH_BINDING_CUSTOM) {
                box.getChildren().add(createSideSwitchCustomEditor("上拨", AhaKeyProtocol.SIDE_SWITCH_POSITION_UP, config.up()));
            }
            if (config.down().binding() == AhaKeyProtocol.SIDE_SWITCH_BINDING_CUSTOM) {
                box.getChildren().add(createSideSwitchCustomEditor("下拨", AhaKeyProtocol.SIDE_SWITCH_POSITION_DOWN, config.down()));
            }
            Label budget = new Label(sideSwitchActionBudgetText(config));
            budget.getStyleClass().add(
                sideSwitchActionBudgetUsed(config) > AhaKeyProtocol.SIDE_SWITCH_READBACK_ACTION_TOTAL_MAX
                    ? "warning-note"
                    : "group-note"
            );
            budget.setWrapText(true);
            box.getChildren().addAll(
                budget,
                readback,
                failure,
                caption("保存使用顶部统一“保存配置”，不会单独应用侧拨。")
            );
            return box;
        });
    }

    private HBox createSideSwitchBindingRow(
        String title,
        int position,
        AhaKeyResponseParser.SideSwitchPositionConfig positionConfig
    ) {
        HBox row = new HBox(10);
        row.setAlignment(Pos.CENTER_LEFT);

        Label label = new Label(title);
        label.getStyleClass().add("field-label");
        label.setMinWidth(56);

        ComboBox<String> combo = new ComboBox<>();
        combo.getItems().addAll("自动批准", "手动批准", "无动作", "自定义快捷键", "自定义宏");
        boolean customMacro = studioState.isSideSwitchCustomMacro(position);
        combo.setValue(sideSwitchBindingLabel(positionConfig.binding(), customMacro));
        combo.getStyleClass().add("combo-box");
        combo.valueProperty().addListener((obs, oldValue, newValue) -> {
            int binding = sideSwitchBindingValue(newValue, positionConfig.binding());
            if (binding == AhaKeyProtocol.SIDE_SWITCH_BINDING_CUSTOM) {
                KeyConfig action = new KeyConfig(0, "");
                if ("自定义宏".equals(newValue)) {
                    action.addMacroStep("DOWN_KEY", 40);
                }
                studioState.updateSideSwitchCustomAction(position, action);
            } else {
                studioState.updateSideSwitchBinding(position, binding);
            }
            rebuild();
        });

        row.getChildren().addAll(label, combo);
        return row;
    }

    private String sideSwitchPhysicalLabel(int physicalPosition) {
        return switch (physicalPosition) {
            case AhaKeyProtocol.SIDE_SWITCH_POSITION_UP -> "上拨";
            case AhaKeyProtocol.SIDE_SWITCH_POSITION_DOWN -> "下拨";
            default -> "中间 / 未知";
        };
    }

    private VBox createSideSwitchCustomEditor(
        String title,
        int position,
        AhaKeyResponseParser.SideSwitchPositionConfig positionConfig
    ) {
        boolean macro = studioState.isSideSwitchCustomMacro(position);
        KeyConfig action = studioState.getSideSwitchCustomAction(position, macro);
        return createGroupBox(title + " 自定义动作", () -> {
            VBox box = new VBox(10);
            ComboBox<String> type = new ComboBox<>();
            type.getItems().addAll("自定义快捷键", "自定义宏");
            type.setValue(macro ? "自定义宏" : "自定义快捷键");
            type.getStyleClass().add("combo-box");
            type.valueProperty().addListener((obs, oldValue, newValue) -> {
                KeyConfig next = new KeyConfig(0, "");
                if ("自定义宏".equals(newValue)) {
                    next.addMacroStep("DOWN_KEY", 40);
                }
                studioState.updateSideSwitchCustomAction(position, next);
                rebuild();
            });
            box.getChildren().add(type);
            if (macro) {
                box.getChildren().add(createSideSwitchMacroEditor(position, action));
            } else {
                box.getChildren().add(createSideSwitchShortcutEditor(position, action));
            }
            Label note = new Label("侧拨 Custom 只能与 Disabled 或另一个 Custom 组合；保存仍使用顶部统一保存。");
            note.getStyleClass().add("group-note");
            note.setWrapText(true);
            box.getChildren().add(note);
            return box;
        });
    }

    private VBox createSideSwitchShortcutEditor(int position, KeyConfig action) {
        VBox box = new VBox(8);
        Label current = new Label("当前：" + sideSwitchShortcutSummary(action));
        current.getStyleClass().add("group-note");

        ListView<String> selectedKeys = new ListView<>();
        selectedKeys.setPrefHeight(96);
        selectedKeys.getStyleClass().add("list-view");
        selectedKeys.getItems().addAll(sideSwitchShortcutItems(action));

        ComboBox<String> selector = new ComboBox<>();
        selector.getItems().addAll(sideSwitchKeyChoices());
        selector.setValue("--- 修饰键 ---");
        selector.getStyleClass().add("combo-box-small");

        HBox buttons = new HBox(8);
        Button set = new Button(languageManager.getString("inspector.add"));
        set.getStyleClass().add("btn-secondary");
        set.setOnAction(e -> {
            String selected = selector.getValue();
            if (selected != null && !selected.startsWith("---")) {
                int code = sideSwitchKeyCode(selected);
                if (code != 0) {
                    addSideSwitchShortcutCode(action, code);
                }
                studioState.updateSideSwitchCustomAction(position, action);
                rebuild();
            }
        });
        Button delete = new Button(languageManager.getString("inspector.delete"));
        delete.getStyleClass().add("btn-secondary");
        delete.setDisable(selectedKeys.getSelectionModel().getSelectedIndex() < 0);
        delete.setOnAction(e -> {
            String selected = selectedKeys.getSelectionModel().getSelectedItem();
            if (selected != null) {
                int code = sideSwitchKeyCode(selected);
                if (code != 0) {
                    removeSideSwitchShortcutCode(action, code);
                    studioState.updateSideSwitchCustomAction(position, action);
                    rebuild();
                }
            }
        });
        selectedKeys.getSelectionModel().selectedIndexProperty().addListener((obs, oldValue, newValue) ->
            delete.setDisable(newValue.intValue() < 0)
        );
        Button clear = new Button(languageManager.getString("inspector.clear"));
        clear.getStyleClass().add("btn-secondary");
        clear.setOnAction(e -> {
            action.setHidCode(0);
            studioState.updateSideSwitchCustomAction(position, action);
            rebuild();
        });
        buttons.getChildren().addAll(selector, set, delete, clear);
        Label note = new Label("可添加 Ctrl / Shift / Alt / Win 与一个基础键，例如 Left Ctrl + V。");
        note.getStyleClass().add("group-note");
        note.setWrapText(true);
        box.getChildren().addAll(current, selectedKeys, buttons, note);
        return box;
    }

    private VBox createSideSwitchMacroEditor(int position, KeyConfig action) {
        VBox box = new VBox(8);
        if (action.getMacroStepCount() == 0) {
            action.addMacroStep("DOWN_KEY", 40);
            studioState.updateSideSwitchCustomAction(position, action);
        }
        for (int i = 0; i < action.getMacroStepCount(); i++) {
            box.getChildren().add(createSideSwitchMacroStepRow(position, action, i));
        }

        HBox buttons = new HBox(8);
        Button add = new Button(languageManager.getString("inspector.add-step"));
        add.getStyleClass().add("btn-primary");
        add.setOnAction(e -> {
            action.addMacroStep("DOWN_KEY", 40);
            studioState.updateSideSwitchCustomAction(position, action);
            rebuild();
        });
        Button clear = new Button(languageManager.getString("inspector.clear"));
        clear.getStyleClass().add("btn-secondary");
        clear.setOnAction(e -> {
            for (int i = action.getMacroStepCount() - 1; i >= 0; i--) {
                action.removeMacroStep(i);
            }
            studioState.updateSideSwitchCustomAction(position, action);
            rebuild();
        });
        buttons.getChildren().addAll(add, clear);

        Label preview = new Label(languageManager.getString("inspector.preview") + action.formatMacroPreview());
        preview.getStyleClass().add("group-note");
        box.getChildren().addAll(buttons, preview);
        return box;
    }

    private HBox createSideSwitchMacroStepRow(int position, KeyConfig action, int index) {
        HBox row = new HBox(6);
        row.setAlignment(Pos.CENTER_LEFT);
        row.getChildren().add(new Label((index + 1) + "."));

        ComboBox<String> actionCombo = new ComboBox<>();
        actionCombo.getItems().addAll(List.of(languageManager.getString("inspector.press"), languageManager.getString("inspector.release"), languageManager.getString("inspector.delay")));
        String currentAction = action.getMacroStepAction(index);
        actionCombo.setValue(switch (currentAction) {
            case "UP_KEY" -> languageManager.getString("inspector.release");
            case "DELAY" -> languageManager.getString("inspector.delay");
            default -> languageManager.getString("inspector.press");
        });
        actionCombo.getStyleClass().add("combo-box-small");
        actionCombo.valueProperty().addListener((obs, oldValue, newValue) -> {
            String nextAction = sideSwitchMacroActionValue(newValue);
            action.updateMacroStep(index, nextAction, action.getMacroStepParam(index));
            studioState.updateSideSwitchCustomAction(position, action);
            rebuild();
        });
        row.getChildren().add(actionCombo);

        if ("DELAY".equals(currentAction)) {
            Spinner<Integer> delay = new Spinner<>(1, 255, Math.max(1, action.getMacroStepParam(index)), 1);
            delay.setEditable(true);
            delay.setPrefWidth(80);
            delay.valueProperty().addListener((obs, oldValue, newValue) -> {
                if (newValue != null) {
                    action.updateMacroStep(index, "DELAY", newValue);
                    studioState.updateSideSwitchCustomAction(position, action);
                }
            });
            row.getChildren().addAll(delay, new Label("ms"));
        } else {
            ComboBox<String> key = new ComboBox<>();
            key.getItems().addAll(sideSwitchKeyChoices());
            key.setValue(com.example.ahakey.model.HIDUsage.getName(action.getMacroStepParam(index)));
            key.getStyleClass().add("combo-box-small");
            key.valueProperty().addListener((obs, oldValue, newValue) -> {
                if (newValue != null && !newValue.startsWith("---")) {
                    action.updateMacroStep(index, action.getMacroStepAction(index), sideSwitchKeyCode(newValue));
                    studioState.updateSideSwitchCustomAction(position, action);
                }
            });
            row.getChildren().add(key);
        }

        Button delete = new Button("X");
        delete.getStyleClass().add("small-btn");
        delete.getStyleClass().add("delete-btn");
        delete.setOnAction(e -> {
            action.removeMacroStep(index);
            studioState.updateSideSwitchCustomAction(position, action);
            rebuild();
        });
        row.getChildren().add(delete);
        return row;
    }

    private List<String> sideSwitchKeyChoices() {
        return List.of(
            "--- 修饰键 ---", "Left Ctrl", "Left Shift", "Left Alt", "Left Win", "Right Ctrl", "Right Shift", "Right Alt", "Right Win",
            "--- 功能键 ---", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12", "F13", "F14", "F15", "F16", "F17", "F18",
            "--- 字母 ---", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
            "--- 常用键 ---", "Enter", "Escape", "Backspace", "Tab", "Space", "Delete", "Up", "Down", "Left", "Right"
        );
    }

    private int sideSwitchKeyCode(String name) {
        String keyName = name == null ? "" : name.split("\\s*\\(")[0].trim();
        return switch (keyName) {
            case "Shift", "Left Shift" -> 0xE1;
            case "Ctrl", "Left Ctrl" -> 0xE0;
            case "Alt", "Left Alt" -> 0xE2;
            case "Win", "Left Win" -> 0xE3;
            default -> com.example.ahakey.model.HIDUsage.getCode(keyName);
        };
    }

    private List<String> sideSwitchShortcutItems(KeyConfig action) {
        List<String> items = new ArrayList<>();
        int hidCode = action.getHidCode();
        if ((hidCode & 0x200) != 0) items.add("Left Ctrl");
        if ((hidCode & 0x2000) != 0) items.add("Right Ctrl");
        if ((hidCode & 0x100) != 0) items.add("Left Shift");
        if ((hidCode & 0x1000) != 0) items.add("Right Shift");
        if ((hidCode & 0x400) != 0) items.add("Left Alt");
        if ((hidCode & 0x4000) != 0) items.add("Right Alt");
        if ((hidCode & 0x800) != 0) items.add("Left Win");
        if ((hidCode & 0x8000) != 0) items.add("Right Win");
        int baseCode = hidCode & 0xFF;
        if (baseCode != 0) {
            items.add(com.example.ahakey.model.HIDUsage.getName(baseCode));
        }
        return items;
    }

    private String sideSwitchShortcutSummary(KeyConfig action) {
        List<String> items = sideSwitchShortcutItems(action);
        if (items.isEmpty()) {
            return "未设置";
        }
        return String.join(" + ", items);
    }

    private void addSideSwitchShortcutCode(KeyConfig action, int code) {
        int hidCode = action.getHidCode();
        int modifiers = hidCode & 0xFF00;
        int baseCode = hidCode & 0xFF;
        int modifierMask = sideSwitchModifierMask(code);
        if (modifierMask != 0) {
            modifiers |= modifierMask;
        } else {
            baseCode = code;
        }
        action.setHidCode(modifiers | baseCode);
    }

    private void removeSideSwitchShortcutCode(KeyConfig action, int code) {
        int hidCode = action.getHidCode();
        int modifiers = hidCode & 0xFF00;
        int baseCode = hidCode & 0xFF;
        int modifierMask = sideSwitchModifierMask(code);
        if (modifierMask != 0) {
            modifiers &= ~modifierMask;
        } else if (baseCode == code) {
            baseCode = 0;
        }
        action.setHidCode(modifiers | baseCode);
    }

    private int sideSwitchModifierMask(int code) {
        return switch (code) {
            case 0xE0 -> 0x200;
            case 0xE4 -> 0x2000;
            case 0xE1 -> 0x100;
            case 0xE5 -> 0x1000;
            case 0xE2 -> 0x400;
            case 0xE6 -> 0x4000;
            case 0xE3 -> 0x800;
            case 0xE7 -> 0x8000;
            default -> 0;
        };
    }

    private String sideSwitchActionBudgetText(AhaKeyResponseParser.SideSwitchConfig config) {
        int used = sideSwitchActionBudgetUsed(config);
        String prefix = "侧拨 Custom 动作长度：" + used + "/" + AhaKeyProtocol.SIDE_SWITCH_READBACK_ACTION_TOTAL_MAX + " 字节。";
        if (used > AhaKeyProtocol.SIDE_SWITCH_READBACK_ACTION_TOTAL_MAX) {
            return prefix + "当前固件 0x97 回读空间不足，请减少宏步骤后再保存。";
        }
        return prefix + "支持单键、组合快捷键和短宏；超长宏需减少步骤。";
    }

    private int sideSwitchActionBudgetUsed(AhaKeyResponseParser.SideSwitchConfig config) {
        return sideSwitchActionBudgetUsed(config.up()) + sideSwitchActionBudgetUsed(config.down());
    }

    private int sideSwitchActionBudgetUsed(AhaKeyResponseParser.SideSwitchPositionConfig config) {
        if (config.binding() != AhaKeyProtocol.SIDE_SWITCH_BINDING_CUSTOM) {
            return 0;
        }
        return config.actionPayload().length;
    }

    private String sideSwitchMacroActionValue(String label) {
        if (languageManager.getString("inspector.release").equals(label)) {
            return "UP_KEY";
        }
        if (languageManager.getString("inspector.delay").equals(label)) {
            return "DELAY";
        }
        return "DOWN_KEY";
    }

    private String sideSwitchBindingLabel(int binding, boolean macro) {
        return switch (binding) {
            case AhaKeyProtocol.SIDE_SWITCH_BINDING_AUTO -> "自动批准";
            case AhaKeyProtocol.SIDE_SWITCH_BINDING_MANUAL -> "手动批准";
            case AhaKeyProtocol.SIDE_SWITCH_BINDING_DISABLED -> "无动作";
            case AhaKeyProtocol.SIDE_SWITCH_BINDING_CUSTOM -> macro ? "自定义宏" : "自定义快捷键";
            default -> "无动作";
        };
    }

    private int sideSwitchBindingValue(String label, int fallback) {
        return switch (label) {
            case "自动批准" -> AhaKeyProtocol.SIDE_SWITCH_BINDING_AUTO;
            case "手动批准" -> AhaKeyProtocol.SIDE_SWITCH_BINDING_MANUAL;
            case "无动作" -> AhaKeyProtocol.SIDE_SWITCH_BINDING_DISABLED;
            case "自定义快捷键", "自定义宏" -> AhaKeyProtocol.SIDE_SWITCH_BINDING_CUSTOM;
            default -> fallback;
        };
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

