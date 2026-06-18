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
}