package com.example.ahakey.service;

/** Immutable result of one approval-relevant hardware query. */
public record ApprovalSnapshot(
    ApprovalState state,
    boolean connected,
    boolean fresh,
    long timestampMillis
) {
    public boolean permitsAutomaticApproval() {
        return state == ApprovalState.AUTO && connected && fresh;
    }
}
