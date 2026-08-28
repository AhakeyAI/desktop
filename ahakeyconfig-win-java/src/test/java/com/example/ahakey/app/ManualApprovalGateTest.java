package com.example.ahakey.app;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ManualApprovalGateTest {
    @Test void timeoutDeniesAndLateAllowIsIgnored() {
        ManualApprovalGate gate = new ManualApprovalGate();
        assertTrue(gate.timeout());
        assertFalse(gate.complete(true));
        assertFalse(gate.isAllowed());
    }

    @Test void normalAllowWinsOnce() {
        ManualApprovalGate gate = new ManualApprovalGate();
        assertTrue(gate.complete(true));
        assertTrue(gate.isAllowed());
        assertFalse(gate.complete(false));
    }

    @Test void normalDenyWinsOnce() {
        ManualApprovalGate gate = new ManualApprovalGate();
        assertTrue(gate.complete(false));
        assertFalse(gate.isAllowed());
        assertFalse(gate.complete(true));
    }
}
