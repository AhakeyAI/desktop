import Foundation
import SwiftUI

@MainActor
public final class VibeBarState: ObservableObject {
    @Published public var keyboardConnected: Bool = false
    @Published public var batteryLevel: Int = 0
    @Published public var deviceName: String? = nil

    /// `true` 表示拨杆在 auto 位（switchState == 0），AI 工具调用自动放行
    @Published public var leverIsAuto: Bool = false
    /// 是否已经读取到拨杆状态。读不到时默认 ask（fail-safe）
    @Published public var leverKnown: Bool = false

    @Published public var voiceListening: Bool = false
    @Published public var voiceRecording: Bool = false

    /// 主 app 注入的回调：用户在灵动岛展开菜单里点 "打开主窗口" 时调用
    public var onOpenMainWindow: (() -> Void)?

    public init() {}
}
