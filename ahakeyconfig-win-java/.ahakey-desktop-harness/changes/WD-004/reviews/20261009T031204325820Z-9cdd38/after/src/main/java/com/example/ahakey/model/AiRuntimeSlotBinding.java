package com.example.ahakey.model;

public class AiRuntimeSlotBinding {
    private int slotIndex;
    private String provider = "Codex";
    private String stableId = "";
    private String transcriptPath = "";
    private String cwd = "";
    private String projectName = "";
    private String sessionTitle = "";
    private String lastIdeState = "";
    private long updatedAtMillis;
    private boolean foreground;

    public AiRuntimeSlotBinding() {
    }

    public AiRuntimeSlotBinding(int slotIndex) {
        this.slotIndex = slotIndex;
    }

    public boolean isBound() {
        return stableId != null && !stableId.isBlank();
    }

    public AiRuntimeSlotState runtimeState() {
        if (!isBound() || lastIdeState == null || lastIdeState.isBlank()) {
            return AiRuntimeSlotState.EMPTY;
        }
        try {
            return AiRuntimeSlotState.fromIdeState(IDEState.valueOf(lastIdeState));
        } catch (IllegalArgumentException e) {
            return AiRuntimeSlotState.EMPTY;
        }
    }

    public String displayTitle() {
        if (!isBound()) {
            return "未绑定";
        }
        if (sessionTitle != null && !sessionTitle.isBlank()) {
            return sessionTitle;
        }
        return "未命名会话";
    }

    public String displayProjectName() {
        return projectName == null || projectName.isBlank() ? "未归类" : projectName;
    }

    public int getSlotIndex() { return slotIndex; }
    public void setSlotIndex(int slotIndex) { this.slotIndex = slotIndex; }
    public String getProvider() { return provider; }
    public void setProvider(String provider) { this.provider = provider; }
    public String getStableId() { return stableId; }
    public void setStableId(String stableId) { this.stableId = stableId == null ? "" : stableId; }
    public String getTranscriptPath() { return transcriptPath; }
    public void setTranscriptPath(String transcriptPath) { this.transcriptPath = transcriptPath == null ? "" : transcriptPath; }
    public String getCwd() { return cwd; }
    public void setCwd(String cwd) { this.cwd = cwd == null ? "" : cwd; }
    public String getProjectName() { return projectName; }
    public void setProjectName(String projectName) { this.projectName = projectName == null ? "" : projectName; }
    public String getSessionTitle() { return sessionTitle; }
    public void setSessionTitle(String sessionTitle) { this.sessionTitle = sessionTitle == null ? "" : sessionTitle; }
    public String getLastIdeState() { return lastIdeState; }
    public void setLastIdeState(String lastIdeState) { this.lastIdeState = lastIdeState == null ? "" : lastIdeState; }
    public long getUpdatedAtMillis() { return updatedAtMillis; }
    public void setUpdatedAtMillis(long updatedAtMillis) { this.updatedAtMillis = updatedAtMillis; }
    public boolean isForeground() { return foreground; }
    public void setForeground(boolean foreground) { this.foreground = foreground; }
}
