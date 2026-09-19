package com.example.ahakey.firmware;

import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** The only parser that translates raw WCHISP output into business results. */
public final class WchIspResultParser {
    private static final Pattern UID = Pattern.compile(
        "(?im)^\\s*Device\\s+UID\\s*:\\s*([0-9A-F][0-9A-F: -]+)\\s*$");
    private static final Pattern FAIL_CODE = Pattern.compile(
        "(?i)[\\\"']?Code[\\\"']?\\s*[:=]\\s*(\\d+)");
    private static final Pattern FINISHED = Pattern.compile(
        "(?is)[\\\"']?Status[\\\"']?\\s*[:=]\\s*[\\\"']Finished[\\\"'].*?"
            + "[\\\"']?Code[\\\"']?\\s*[:=]\\s*0.*?"
            + "[\\\"']?Message[\\\"']?\\s*[:=]\\s*[\\\"']Succeed[\\\"']");
    /** WCHISP may print the terminal fields as plain console text. */
    private static final Pattern TEXT_FINISHED = Pattern.compile(
        "(?is)\\bFinished\\b.*?\\bCode\\s*[:=]?\\s*0\\b.*?"
            + "\\bMessage\\s*[:=]?\\s*Succeed\\b");
    private static final Pattern FAIL = Pattern.compile(
        "(?is)[\\\"']?Status[\\\"']?\\s*[:=]\\s*[\\\"']Fail[\\\"']");
    private static final Pattern EXPLICIT_FAILURE = Pattern.compile(
        "(?is)(?:[\\\"']?Status[\\\"']?\\s*[:=]\\s*[\\\"']?(?:Fail|Failed|Error)[\\\"']?"
            + "|\\b(?:Error|Fail|Failed|Failure|Exception)\\b"
            + "|\\bCode\\s*[:=]?\\s*[1-9]\\d*\\b)");

    private WchIspResultParser() {}

    public static UidQueryResult parseUid(WchIspRunner.WchIspProcessResult result) {
        if (result == null) return UidQueryResult.failure(FirmwareUpdateError.INTERNAL_ERROR, "结果为空");
        String output = combined(result);
        if (result.cancelled()) return UidQueryResult.failure(
            ownershipIncomplete(result) ? FirmwareUpdateError.PROCESS_OWNERSHIP_INCOMPLETE
                : isUacCancelled(result) ? FirmwareUpdateError.UAC_CANCELLED : FirmwareUpdateError.CANCELLED,
            ownershipIncomplete(result) ? "UID 查询已取消，但 elevated 进程归属未完整确认"
                : isUacCancelled(result) ? "UID 查询被用户取消管理员授权" : "UID 查询已取消");
        if (result.timedOut()) return UidQueryResult.failure(FirmwareUpdateError.PROCESS_TIMEOUT, "UID 查询超时");
        if (!result.processStarted()) return UidQueryResult.failure(FirmwareUpdateError.PROCESS_START_FAILED, result.stderr());
        Matcher uid = UID.matcher(output);
        if (uid.find()) return new UidQueryResult(true, null, uid.group(1).trim(), "UID 查询成功");
        if (result.exitCode() == 100) return UidQueryResult.failure(FirmwareUpdateError.UID_EXIT_100, output);
        return UidQueryResult.failure(FirmwareUpdateError.UID_QUERY_FAILED,
            output.isBlank() ? "WCHISP 未返回设备 UID" : output.trim());
    }

    public static FlashExecutionResult parseFlash(WchIspRunner.WchIspProcessResult result) {
        if (result == null) return FlashExecutionResult.failure(FirmwareUpdateError.INTERNAL_ERROR, "结果为空");
        String output = combined(result);
        if (result.cancelled()) return FlashExecutionResult.failure(
            ownershipIncomplete(result) ? FirmwareUpdateError.PROCESS_OWNERSHIP_INCOMPLETE
                : isUacCancelled(result) ? FirmwareUpdateError.UAC_CANCELLED : FirmwareUpdateError.CANCELLED,
            ownershipIncomplete(result) ? "烧录已取消，但 elevated 进程归属未完整确认"
                : isUacCancelled(result) ? "烧录被用户取消管理员授权" : "烧录已取消");
        if (result.timedOut()) return FlashExecutionResult.failure(
            FirmwareUpdateError.FLASH_TERMINAL_RESULT_TIMEOUT,
            "WCHISP 未在时限内返回 Finished/Code 0/Succeed 终态");
        if (!result.processStarted()) return FlashExecutionResult.failure(FirmwareUpdateError.PROCESS_START_FAILED, result.stderr());
        boolean explicitFailure = EXPLICIT_FAILURE.matcher(output).find();
        boolean terminalSuccess = FINISHED.matcher(output).find()
            || TEXT_FINISHED.matcher(output).find();
        // WCHISP's terminal payload is the authoritative flash result.  Some
        // vendor builds return a non-zero process code after printing the
        // complete Finished/Code=0/Message=Succeed record.  Do not let that
        // transport-level code override an explicit successful device result.
        if (terminalSuccess && !explicitFailure) {
            return new FlashExecutionResult(true, null, "烧录完成（WCHISP 明确终态）", 0);
        }
        int vendorCode = code(output, result.exitCode());
        FirmwareUpdateError error = FAIL.matcher(output).find()
            ? FirmwareUpdateError.FLASH_FAILED : FirmwareUpdateError.FLASH_FAILED;
        String detail = output.isBlank() ? "WCHISP 未返回可信的 Finished/Code 0/Succeed 终态"
            : output.trim();
        return new FlashExecutionResult(false, error, detail, vendorCode);
    }

    private static int code(String output, int fallback) {
        Matcher matcher = FAIL_CODE.matcher(output == null ? "" : output);
        if (matcher.find()) {
            try { return Integer.parseInt(matcher.group(1)); } catch (NumberFormatException ignored) { }
        }
        return fallback;
    }

    private static String combined(WchIspRunner.WchIspProcessResult result) {
        String output = result.stdout() + "\n" + result.stderr() + "\n" + result.console();
        return output.toLowerCase(Locale.ROOT).contains("device uid")
            ? output : output;
    }

    private static boolean isUacCancelled(WchIspRunner.WchIspProcessResult result) {
        return result != null && result.terminationReason().toUpperCase(Locale.ROOT)
            .contains("UAC_CANCELLED");
    }

    private static boolean ownershipIncomplete(WchIspRunner.WchIspProcessResult result) {
        return result != null && result.terminationReason().toUpperCase(Locale.ROOT)
            .contains("PROCESS_OWNERSHIP_INCOMPLETE");
    }

    public record UidQueryResult(boolean success, FirmwareUpdateError error,
                                 String deviceUid, String detail) {
        static UidQueryResult failure(FirmwareUpdateError error, String detail) {
            return new UidQueryResult(false, error, "", detail == null ? "" : detail);
        }
    }

    public record FlashExecutionResult(boolean success, FirmwareUpdateError error,
                                       String detail, int vendorCode) {
        static FlashExecutionResult failure(FirmwareUpdateError error, String detail) {
            return new FlashExecutionResult(false, error, detail == null ? "" : detail, -1);
        }
    }
}
