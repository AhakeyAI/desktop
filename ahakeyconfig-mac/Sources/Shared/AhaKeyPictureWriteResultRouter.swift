import Foundation

// MARK: - 0x81 图片写入确认路由（WBS-5.6 返工 R2）
//
// 从 Agent BLE 回调中抽出的纯决策，保证可测：
// - session 必须匹配当前在途 0x9B 会话，否则忽略（迟到/串台确认不得完成新 waiter）；
// - status 裁决成功/设备拒绝。

public enum AhaKeyPictureWriteResultDecision: Equatable, Sendable {
    /// 0x81 成功：会话正常关闭。
    case success
    /// 设备拒绝（status != 0）：保留 session 供 0x9A 收尾。
    case deviceRejected
    /// 有在途会话但确认帧缺少 session 字段：忽略。
    case ignoreMissingSession
    /// session 与在途会话不符（过期确认）：忽略。
    case ignoreStaleSession(session: UInt16)
}

public enum AhaKeyPictureWriteResultRouter {
    public static func decide(
        status: UInt8, payload: [UInt8], expectedSession: UInt16?
    ) -> AhaKeyPictureWriteResultDecision {
        if let expected = expectedSession {
            guard payload.count >= 2 else { return .ignoreMissingSession }
            let session = UInt16(payload[0]) | (UInt16(payload[1]) << 8)
            guard session == expected else { return .ignoreStaleSession(session: session) }
        }
        return status == 0 ? .success : .deviceRejected
    }
}
