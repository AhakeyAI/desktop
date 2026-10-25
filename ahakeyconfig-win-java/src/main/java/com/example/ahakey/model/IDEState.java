package com.example.ahakey.model;

import com.example.ahakey.util.LanguageManager;

public enum IDEState {
    SESSION_START(4, "ide-state.session-start", "ide-state.session-start-desc"),
    USER_PROMPT_SUBMIT(7, "ide-state.user-prompt-submit", "ide-state.user-prompt-submit-desc"),
    PRE_TOOL_USE(3, "ide-state.pre-tool-use", "ide-state.pre-tool-use-desc"),
    PERMISSION_REQUEST(1, "ide-state.permission-request", "ide-state.permission-request-desc"),
    POST_TOOL_USE(2, "ide-state.post-tool-use", "ide-state.post-tool-use-desc"),
    NOTIFICATION(0, "ide-state.notification", "ide-state.notification-desc"),
    TASK_COMPLETED(6, "ide-state.task-completed", "ide-state.task-completed-desc"),
    STOP(5, "ide-state.stop", "ide-state.stop-desc"),
    SESSION_END(8, "ide-state.session-end", "ide-state.session-end-desc");

    private final int code;
    private final String labelKey;
    private final String descriptionKey;

    IDEState(int code, String labelKey, String descriptionKey) {
        this.code = code;
        this.labelKey = labelKey;
        this.descriptionKey = descriptionKey;
    }

    public int getCode() {
        return code;
    }

    public String getLabel() {
        return LanguageManager.getInstance().getString(labelKey);
    }

    public String getDescription() {
        return LanguageManager.getInstance().getString(descriptionKey);
    }

    public String getFullLabel() {
        return code + " " + getLabel();
    }

    public static IDEState fromCode(int code) {
        for (IDEState state : values()) {
            if (state.code == code) {
                return state;
            }
        }
        return NOTIFICATION;
    }
}
