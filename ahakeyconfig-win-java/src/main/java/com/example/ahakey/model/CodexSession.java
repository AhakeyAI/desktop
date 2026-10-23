package com.example.ahakey.model;

import java.time.Instant;

public record CodexSession(
    String id,
    String title,
    String projectName,
    String cwd,
    String transcriptPath,
    Instant updatedAt
) {
    public AiRuntimeSlotBinding toBinding(int slotIndex) {
        return toAiRuntimeSession().toBinding(slotIndex);
    }

    public String timeLabel() {
        return toAiRuntimeSession().timeLabel();
    }

    public AiRuntimeSession toAiRuntimeSession() {
        return new AiRuntimeSession("Codex", id, title, projectName, cwd, transcriptPath, updatedAt);
    }

    public static String projectFromCwd(String cwd) {
        return AiRuntimeSession.projectFromCwd(cwd);
    }
}
