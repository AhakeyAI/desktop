package com.example.ahakey.model;

import java.nio.file.Path;
import java.time.Instant;

public record AiRuntimeSession(
    String provider,
    String id,
    String title,
    String projectName,
    String cwd,
    String transcriptPath,
    Instant updatedAt
) {
    public AiRuntimeSlotBinding toBinding(int slotIndex) {
        AiRuntimeSlotBinding binding = new AiRuntimeSlotBinding(slotIndex);
        binding.setProvider(provider);
        binding.setStableId(id);
        binding.setTranscriptPath(transcriptPath);
        binding.setCwd(cwd);
        binding.setProjectName(projectName);
        binding.setSessionTitle(title);
        binding.setUpdatedAtMillis(updatedAt == null ? 0L : updatedAt.toEpochMilli());
        return binding;
    }

    public String displayTitle() {
        return title == null || title.isBlank() ? "未命名会话" : title;
    }

    public String timeLabel() {
        if (updatedAt == null || updatedAt.equals(Instant.EPOCH)) {
            return "";
        }
        long minutes = Math.max(0, (Instant.now().toEpochMilli() - updatedAt.toEpochMilli()) / 60000);
        if (minutes < 60) {
            return minutes + " 分";
        }
        long hours = minutes / 60;
        if (hours < 24) {
            return hours + " 小时";
        }
        return (hours / 24) + " 天";
    }

    public static String projectFromCwd(String cwd) {
        if (cwd == null || cwd.isBlank()) {
            return "未归类";
        }
        try {
            Path name = Path.of(cwd).getFileName();
            return name == null ? cwd : name.toString();
        } catch (Exception e) {
            return cwd;
        }
    }
}
