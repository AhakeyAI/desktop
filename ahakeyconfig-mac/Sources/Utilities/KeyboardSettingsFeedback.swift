import Foundation

/// Keep a user cancellation distinguishable from a failed or rolled-back save.
enum KeyboardSettingsFeedback {
    static func message(for error: Error) -> String {
        if error is CancellationError {
            return NSLocalizedString("操作已取消；已发出的更改可能已生效，请重新连接并读取。", comment: "")
        }
        return error.localizedDescription
    }
}
