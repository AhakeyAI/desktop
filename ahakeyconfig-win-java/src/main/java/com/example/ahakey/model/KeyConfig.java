package com.example.ahakey.model;

import java.util.ArrayList;
import java.util.List;

public class KeyConfig {
    private int hidCode;
    private String description;
    private VoicePreset voicePreset;
    private List<MacroStep> macro;
    
    public KeyConfig() {
        this.hidCode = 0;
        this.description = "";
        this.voicePreset = VoicePreset.CUSTOM;
        this.macro = new ArrayList<>();
    }
    
    public KeyConfig(int hidCode, String description) {
        this.hidCode = hidCode;
        this.description = description;
        this.voicePreset = VoicePreset.CUSTOM;
        this.macro = new ArrayList<>();
    }
    
    public int getHidCode() {
        return hidCode;
    }
    
    public void setHidCode(int hidCode) {
        this.hidCode = hidCode;
    }
    
    public String getDescription() {
        return description;
    }
    
    public void setDescription(String description) {
        this.description = description;
    }
    
    public VoicePreset getVoicePreset() {
        return voicePreset;
    }
    
    public void setVoicePreset(VoicePreset voicePreset) {
        this.voicePreset = voicePreset;
    }
    
    public List<MacroStep> getMacro() {
        return macro;
    }
    
    public void setMacro(List<MacroStep> macro) {
        this.macro = macro;
    }
    
    public String getDisplayName() {
        if (hidCode == 0) return "未设置";
        return HIDUsage.getName(hidCode);
    }
    
    public boolean usesMacro() {
        return voicePreset == VoicePreset.CUSTOM && !macro.isEmpty();
    }
    
    public String getDisplaySummary() {
        if (voicePreset != VoicePreset.CUSTOM) {
            return voicePreset.getDisplayName();
        }
        if (usesMacro()) {
            return "宏 (" + macro.size() + " 步)";
        }
        return getDisplayName();
    }
    
    public int getMacroStepCount() {
        return macro.size();
    }
    
    public String getMacroStepAction(int index) {
        if (index >= 0 && index < macro.size()) {
            MacroAction action = macro.get(index).getAction();
            return switch (action) {
                case DOWN_KEY -> "DOWN_KEY";
                case UP_KEY -> "UP_KEY";
                case DELAY -> "DELAY";
                default -> "DOWN_KEY";
            };
        }
        return "DOWN_KEY";
    }
    
    public int getMacroStepParam(int index) {
        if (index >= 0 && index < macro.size()) {
            return macro.get(index).getParam();
        }
        return 0;
    }
    
    public void addMacroStep(String actionType, int param) {
        MacroStep step = new MacroStep();
        step.setAction(switch (actionType) {
            case "DOWN_KEY" -> MacroAction.DOWN_KEY;
            case "UP_KEY" -> MacroAction.UP_KEY;
            case "DELAY" -> MacroAction.DELAY;
            default -> MacroAction.DOWN_KEY;
        });
        step.setParam(param);
        macro.add(step);
    }
    
    public void updateMacroStep(int index, String actionType, int param) {
        if (index >= 0 && index < macro.size()) {
            MacroStep step = macro.get(index);
            step.setAction(switch (actionType) {
                case "DOWN_KEY" -> MacroAction.DOWN_KEY;
                case "UP_KEY" -> MacroAction.UP_KEY;
                case "DELAY" -> MacroAction.DELAY;
                default -> MacroAction.DOWN_KEY;
            });
            step.setParam(param);
        }
    }
    
    public void removeMacroStep(int index) {
        if (index >= 0 && index < macro.size()) {
            macro.remove(index);
        }
    }
    
    public void moveMacroStep(int fromIndex, int toIndex) {
        if (fromIndex >= 0 && fromIndex < macro.size() && toIndex >= 0 && toIndex < macro.size()) {
            MacroStep step = macro.remove(fromIndex);
            macro.add(toIndex, step);
        }
    }
    
    public String formatMacroPreview() {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < macro.size(); i++) {
            if (i > 0) sb.append(" → ");
            MacroStep step = macro.get(i);
            switch (step.getAction()) {
                case DOWN_KEY -> sb.append("↓").append(HIDUsage.getName(step.getParam()));
                case UP_KEY -> sb.append("↑").append(HIDUsage.getName(step.getParam()));
                case DELAY -> sb.append("+").append(step.getParam() * 3).append("ms");
                default -> sb.append("·");
            }
        }
        return sb.toString();
    }
}

class MacroStep {
    private String id;
    private MacroAction action;
    private int param;
    
    public MacroStep() {
        this.id = java.util.UUID.randomUUID().toString();
        this.action = MacroAction.NO_OP;
        this.param = 0;
    }
    
    public String getId() {
        return id;
    }
    
    public MacroAction getAction() {
        return action;
    }
    
    public void setAction(MacroAction action) {
        this.action = action;
    }
    
    public int getParam() {
        return param;
    }
    
    public void setParam(int param) {
        this.param = param;
    }
}

enum MacroAction {
    NO_OP("无操作", false, false),
    DOWN_KEY("按下键", true, false),
    UP_KEY("释放键", true, false),
    UP_ALL_KEYS("释放所有", false, false),
    DELAY("延时", false, true);
    
    private final String title;
    private final boolean takesKeycodeParam;
    private final boolean takesDelayParam;
    
    MacroAction(String title, boolean takesKeycodeParam, boolean takesDelayParam) {
        this.title = title;
        this.takesKeycodeParam = takesKeycodeParam;
        this.takesDelayParam = takesDelayParam;
    }
    
    public String getTitle() {
        return title;
    }
    
    public boolean takesKeycodeParam() {
        return takesKeycodeParam;
    }
    
    public boolean takesDelayParam() {
        return takesDelayParam;
    }
}