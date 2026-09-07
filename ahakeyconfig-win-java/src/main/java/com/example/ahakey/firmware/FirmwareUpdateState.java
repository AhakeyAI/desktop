package com.example.ahakey.firmware;

/**
 * States of one firmware update operation.  The service is the only component
 * allowed to advance this state machine.
 */
public enum FirmwareUpdateState {
    IDLE,
    PREFLIGHT,
    WAITING_ISP,
    DETECTING,
    READY,
    FLASHING,
    WAITING_RECONNECT,
    VERIFYING,
    SUCCESS,
    FAILED,
    CANCELLED;

    public boolean terminal() {
        return this == SUCCESS || this == FAILED || this == CANCELLED;
    }
}
