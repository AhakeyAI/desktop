package com.example.ahakey.service;

import com.example.ahakey.model.DeviceStatus;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Objects;

/**
 * The single decision point for hardware-backed automatic approval.
 * Only a new response from a connected device which explicitly reports AUTO
 * can permit automatic approval.
 */
public final class ApprovalService {
    private static final Logger logger = LoggerFactory.getLogger(ApprovalService.class);
    public static final long DEFAULT_QUERY_TIMEOUT_MS = 500;

    @FunctionalInterface
    interface StatusSource {
        ApprovalSnapshot refresh(long timeoutMillis);
    }

    private final StatusSource statusSource;
    private final long queryTimeoutMillis;

    public ApprovalService(BleManager bleManager) {
        this(timeoutMillis -> {
            boolean fresh = bleManager.queryStatusAndWait(timeoutMillis);
            return fromDeviceStatus(
                fresh ? bleManager.getApprovalQueryStatus() : bleManager.getCachedStatus(),
                fresh,
                bleManager.getLastStatusUpdateTime()
            );
        }, DEFAULT_QUERY_TIMEOUT_MS);
    }

    ApprovalService(StatusSource statusSource, long queryTimeoutMillis) {
        this.statusSource = Objects.requireNonNull(statusSource, "statusSource");
        if (queryTimeoutMillis <= 0) {
            throw new IllegalArgumentException("queryTimeoutMillis must be positive");
        }
        this.queryTimeoutMillis = queryTimeoutMillis;
    }

    public ApprovalSnapshot refresh() {
        try {
            ApprovalSnapshot snapshot = statusSource.refresh(queryTimeoutMillis);
            return snapshot == null
                ? new ApprovalSnapshot(ApprovalState.UNKNOWN, false, false, 0)
                : snapshot;
        } catch (RuntimeException exception) {
            logger.warn("Hardware approval query failed; automatic approval disabled",
                exception);
            return new ApprovalSnapshot(ApprovalState.UNKNOWN, false, false, 0);
        }
    }

    public boolean canAutoApprove() {
        return refresh().permitsAutomaticApproval();
    }

    static ApprovalSnapshot fromDeviceStatus(
        DeviceStatus status,
        boolean fresh,
        long timestampMillis
    ) {
        if (status == null) {
            return new ApprovalSnapshot(ApprovalState.UNKNOWN, false, false, 0);
        }
        if (!status.isConnected()) {
            return new ApprovalSnapshot(
                ApprovalState.DISCONNECTED, false, false, timestampMillis);
        }
        if (!fresh) {
            return new ApprovalSnapshot(
                ApprovalState.STALE, true, false, timestampMillis);
        }
        ApprovalState state = switch (status.getSwitchState()) {
            case 0 -> ApprovalState.AUTO;
            case 1 -> ApprovalState.MANUAL;
            default -> ApprovalState.UNKNOWN;
        };
        return new ApprovalSnapshot(state, true, true, timestampMillis);
    }
}
