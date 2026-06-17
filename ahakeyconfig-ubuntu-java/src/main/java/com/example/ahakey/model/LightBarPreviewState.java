package com.example.ahakey.model;

/** 与 Swift `LightBarPreviewState` 一致：画布灯条预览的四种业务语义。 */
public enum LightBarPreviewState {
    AI_RUNNING("aiRunning", "AI 运行中", IDEState.POST_TOOL_USE),
    WAITING_APPROVAL("waitingApproval", "等待批准", IDEState.PERMISSION_REQUEST),
    STOPPED("stopped", "已停止", IDEState.STOP),
    TASK_COMPLETED("taskCompleted", "任务完成", IDEState.STOP);

    private final String id;
    private final String title;
    private final IDEState ideState;

    LightBarPreviewState(String id, String title, IDEState ideState) {
        this.id = id;
        this.title = title;
        this.ideState = ideState;
    }

    public String getId() {
        return id;
    }

    public String getTitle() {
        return title;
    }

    public IDEState getIdeState() {
        return ideState;
    }

    public String getDetail() {
        return switch (this) {
            case AI_RUNNING -> "手动模式为来回流水，自动模式为彩虹移动。";
            case WAITING_APPROVAL -> "提醒用户当前需要确认。";
            case STOPPED -> "默认用红色常亮停住。";
            case TASK_COMPLETED -> "表示本轮执行已经完成。";
        };
    }

    public static LightBarPreviewState fromId(String id) {
        for (LightBarPreviewState s : values()) {
            if (s.id.equals(id)) {
                return s;
            }
        }
        return AI_RUNNING;
    }
}
