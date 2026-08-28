package com.example.ahakey.service;

/** Executes ordered lighting writes and produces exactly one final UI result. */
public final class LightOperationCoordinator {
    @FunctionalInterface
    public interface CheckedAction {
        void run() throws Exception;
    }

    public record Step(String name, CheckedAction action) {
        public Step {
            if (name == null || name.isBlank() || action == null) {
                throw new IllegalArgumentException("Lighting step requires a name and action");
            }
        }
    }

    public record Result(boolean success, String message) {}

    private LightOperationCoordinator() {}

    public static Step step(String name, CheckedAction action) {
        return new Step(name, action);
    }

    public static Result execute(String successMessage, Step... steps) {
        for (Step step : steps) {
            try {
                step.action().run();
            } catch (Exception failure) {
                String reason = failure.getMessage();
                if (reason == null || reason.isBlank()) {
                    reason = failure.getClass().getSimpleName();
                }
                return new Result(false, step.name() + "失败：" + reason);
            }
        }
        return new Result(true, successMessage);
    }
}
