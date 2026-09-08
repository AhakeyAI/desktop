package com.example.ahakey.firmware;

/**
 * Supplies a structured chip identity decision for an ISP device.
 *
 * <p>The current Windows PnP probe only proves that a WCH ISP USB device is
 * present; it does not prove the exact CH582 model.  The production default
 * therefore returns {@link Status#UNKNOWN}.  A later official control-mode or
 * native detector can implement this interface without changing the firmware
 * operation state machine.</p>
 */
@FunctionalInterface
public interface ChipMatched {
    ChipMatchResult inspect() throws Exception;

    static ChipMatched unknown() {
        return () -> ChipMatchResult.unknown(
            "当前 ISP 探测只确认 VID_4348&PID_55E0，未取得可审计的 CH582 型号信息");
    }

    static ChipMatched matched() {
        return () -> ChipMatchResult.matched("测试替身确认 CH582");
    }

    static ChipMatched mismatched(String detail) {
        return () -> ChipMatchResult.mismatched(detail);
    }

    enum Status {
        MATCHED,
        MISMATCH,
        UNKNOWN
    }

    record ChipMatchResult(Status status, String detail) {
        public ChipMatchResult {
            status = status == null ? Status.UNKNOWN : status;
            detail = detail == null ? "" : detail;
        }

        public static ChipMatchResult matched(String detail) {
            return new ChipMatchResult(Status.MATCHED, detail);
        }

        public static ChipMatchResult mismatched(String detail) {
            return new ChipMatchResult(Status.MISMATCH, detail);
        }

        public static ChipMatchResult unknown(String detail) {
            return new ChipMatchResult(Status.UNKNOWN, detail);
        }

        public boolean matched() {
            return status == Status.MATCHED;
        }

        public boolean mismatch() {
            return status == Status.MISMATCH;
        }

        public boolean unknown() {
            return status == Status.UNKNOWN;
        }
    }
}
