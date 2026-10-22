package com.example.ahakey.model;

import com.example.ahakey.util.LanguageManager;

/** 与 Swift `LightBarPreviewState` 一致：画布灯条预览的四种业务语义。 */
public enum LightBarPreviewState {
    AI_RUNNING("aiRunning", "light-bar-preview.ai-running", IDEState.POST_TOOL_USE),
    WAITING_APPROVAL("waitingApproval", "light-bar-preview.waiting-approval", IDEState.PERMISSION_REQUEST),
    STOPPED("stopped", "light-bar-preview.stopped", IDEState.STOP),
    TASK_COMPLETED("taskCompleted", "light-bar-preview.task-completed", IDEState.STOP);

    private final String id;
    private final String titleKey;
    private final IDEState ideState;

    LightBarPreviewState(String id, String titleKey, IDEState ideState) {
        this.id = id;
        this.titleKey = titleKey;
        this.ideState = ideState;
    }

    public String getId() {
        return id;
    }

    public String getTitle() {
        return LanguageManager.getInstance().getString(titleKey);
    }

    public IDEState getIdeState() {
        return ideState;
    }

    public String getDetail() {
        return LanguageManager.getInstance().getString(titleKey + "-detail");
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
