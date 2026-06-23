package com.example.ahakey.model;

public class MacroStep {
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
    
    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        MacroStep macroStep = (MacroStep) o;
        return id.equals(macroStep.id);
    }
    
    @Override
    public int hashCode() {
        return id.hashCode();
    }
    
    @Override
    public String toString() {
        return "MacroStep{" +
                "id='" + id + '\'' +
                ", action=" + action +
                ", param=" + param +
                '}';
    }
    
    /**
     * 深度拷贝方法
     */
    @Override
    public MacroStep clone() {
        MacroStep copy = new MacroStep();
        copy.id = this.id;      // 保留相同 id
        copy.action = this.action;
        copy.param = this.param;
        return copy;
    }
}