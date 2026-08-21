import Foundation

public enum WriteResultAlertChoice {
    case continueEditing
    case completeEditing
}

public enum AhaKeyDeviceWriteResultMessage {
    public static func taskPicturesUnsupported(defaultPictureUpdated: Bool) -> String {
        if defaultPictureUpdated {
            return NSLocalizedString("写入成功：默认图片设置已更新，键位与灯效已写入。旧版固件不支持任务状态动图，该可选功能已跳过。", comment: "")
        }
        return NSLocalizedString("写入成功：键位与灯效已写入。当前固件不支持任务状态动图，该可选功能已跳过。", comment: "")
    }
}

public enum WriteResultAlertPolicy {
    public static func shouldExitEditing(for choice: WriteResultAlertChoice) -> Bool {
        choice == .completeEditing
    }
}
