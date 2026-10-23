package com.example.ahakey.model;

public enum AiRuntimeSlotState {
    EMPTY(0, "空"),
    RUNNING(1, "处理中"),
    WAITING(2, "等待"),
    DONE(3, "完成");

    private final int protocolValue;
    private final String title;

    AiRuntimeSlotState(int protocolValue, String title) {
        this.protocolValue = protocolValue;
        this.title = title;
    }

    public int getProtocolValue() {
        return protocolValue;
    }

    public String getTitle() {
        return title;
    }

    public static AiRuntimeSlotState fromIdeState(IDEState state) {
        if (state == null) {
            return EMPTY;
        }
        return switch (state) {
            case NOTIFICATION, PERMISSION_REQUEST -> WAITING;
            case SESSION_START, USER_PROMPT_SUBMIT, PRE_TOOL_USE, POST_TOOL_USE -> RUNNING;
            case TASK_COMPLETED, STOP, SESSION_END -> DONE;
        };
    }
}
