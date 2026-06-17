package com.example.ahakey.model;

public enum IDEState {
    SESSION_START(4, "会话开始", "Claude/Codex 会话刚启动，适合给用户一个启动反馈。"),
    USER_PROMPT_SUBMIT(7, "用户提交输入", "用户把问题或指令提交给 AI，适合短暂输入反馈。"),
    PRE_TOOL_USE(3, "工具即将执行", "AI 准备调用工具或执行动作。"),
    PERMISSION_REQUEST(1, "等待批准", "AI 需要用户确认，例如批准命令、文件修改或工具调用。"),
    POST_TOOL_USE(2, "工具执行完成", "一次工具调用结束，AI 可能继续分析或进入下一步。"),
    NOTIFICATION(0, "通知提醒", "普通提示或状态通知。"),
    TASK_COMPLETED(6, "任务完成", "本轮任务已经完成。"),
    STOP(5, "AI 停止", "AI 当前停止输出或处于待命状态。"),
    SESSION_END(8, "会话结束", "会话收尾或退出。");

    private final int code;
    private final String label;
    private final String description;

    IDEState(int code, String label, String description) {
        this.code = code;
        this.label = label;
        this.description = description;
    }

    public int getCode() {
        return code;
    }

    public String getLabel() {
        return label;
    }

    public String getDescription() {
        return description;
    }

    public String getFullLabel() {
        return code + " " + label;
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
