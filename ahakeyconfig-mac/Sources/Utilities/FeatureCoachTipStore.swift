import Foundation
import SwiftUI

/// 功能级一次性 coach tip（全屏新手引导完成后再出现）。
enum FeatureCoachTipID: String, CaseIterable, Identifiable {
    case deviceConnect = "tip.device.connect"
    case hardwareBindWrite = "tip.hardware.bind_write"
    case hardwareModeVsAgent = "tip.hardware.mode_vs_agent"
    case agentLinkageFirst = "tip.agent.linkage_first"
    case voiceEmptyHistory = "tip.voice.empty_history"
    case userCenterPermissions = "tip.usercenter.permissions"
    case islandFirst = "tip.island.first"
    case islandLibrary = "tip.island.library"
    case pluginComingSoon = "tip.plugin.coming_soon"

    var id: String { rawValue }

    /// 数字越小优先级越高；同屏只展示一条时取最高优先级。
    var priority: Int {
        switch self {
        case .deviceConnect: return 0
        case .hardwareBindWrite: return 1
        case .hardwareModeVsAgent: return 2
        case .agentLinkageFirst: return 3
        case .voiceEmptyHistory: return 4
        case .userCenterPermissions: return 5
        case .islandFirst: return 6
        case .islandLibrary: return 7
        case .pluginComingSoon: return 8
        }
    }

    var title: String {
        switch self {
        case .deviceConnect: return "先连接键盘"
        case .hardwareBindWrite: return "改完要写入"
        case .hardwareModeVsAgent: return "这不是装 Agent"
        case .agentLinkageFirst: return "先打开联动"
        case .voiceEmptyHistory: return "去试录一句话"
        case .userCenterPermissions: return "权限在这里"
        case .islandFirst: return "先调这两个分段"
        case .islandLibrary: return "只管岛上模块"
        case .pluginComingSoon: return "安装尚未开放"
        }
    }

    /// 指向界面上的具体控件名称，降低「不知道点哪」的成本。
    var targetLabel: String {
        switch self {
        case .deviceConnect:
            return "卡片右侧「连接设备」"
        case .hardwareBindWrite:
            return "右侧底部蓝色「写入键盘」"
        case .hardwareModeVsAgent:
            return "画布下方「Agent 模式」分段"
        case .agentLinkageFirst:
            return "顶部分段「联动」→ 卡片右侧「一键启用联动」"
        case .voiceEmptyHistory:
            return "顶部分段「通用设置」"
        case .userCenterPermissions:
            return "本页「权限与隐私」"
        case .islandFirst:
            return "顶部分段「常驻岛 / 展开岛」"
        case .islandLibrary:
            return "本页模块开关与排序"
        case .pluginComingSoon:
            return "产品页「下载 / 安装到本机」（暂不可点）"
        }
    }

    var message: String {
        switch self {
        case .deviceConnect:
            return "改键前先连上键盘。点左下角「我的设备」，在卡片右侧点「连接设备」（改键用 Studio 占用蓝牙）。"
        case .hardwareBindWrite:
            return "先点左侧画布上的按键改绑定；改完务必点右侧底部蓝色「写入键盘」，否则真机不会生效。"
        case .hardwareModeVsAgent:
            return "下面的「Agent 模式」只是键盘 Mode 槽（对应 Claude / Cursor 等）。要装守护、日常控制，请点右侧按钮去「Agent · 联动」。"
        case .agentLinkageFirst:
            return "当前还不能对话。请点顶栏「联动」，再点「联动就绪」卡片右侧的「一键启用联动」。"
        case .voiceEmptyHistory:
            return "历史为空是正常的。点顶栏「通用设置」去做试录；若失败，再到左下角用户中心 →「设置」补权限。"
        case .userCenterPermissions:
            return "麦克风、语音识别、辅助功能等系统权限都在本页「权限与隐私」里，不在「语音输入」Tab。"
        case .islandFirst:
            return "用顶部「常驻岛」「展开岛」分段调整左右槽与模块。标「即将推出 / 占位」的条目可先忽略。"
        case .islandLibrary:
            return "这里只控制悬停展开后面板上的模块显隐与顺序。改按键映射请回侧栏「硬件设备」。"
        case .pluginComingSoon:
            return "现在可以浏览货架和安装路径。产品页上的「下载」「安装到本机」仍是灰色，尚未开放。"
        }
    }

    /// 主按钮文案；与界面真实入口对齐。nil 表示只需「知道了」。
    var primaryActionTitle: String? {
        switch self {
        case .deviceConnect: return "打开我的设备"
        case .hardwareBindWrite: return nil
        case .hardwareModeVsAgent: return "去 Agent · 联动"
        case .agentLinkageFirst: return "打开联动页"
        case .voiceEmptyHistory: return "打开通用设置"
        case .userCenterPermissions: return "展开权限与隐私"
        case .islandFirst: return nil
        case .islandLibrary: return "回硬件设备"
        case .pluginComingSoon: return nil
        }
    }

    @MainActor
    func performPrimaryAction() {
        switch self {
        case .deviceConnect:
            StudioNavigationRouter.shared.openDeviceManagement(showDetail: true)
        case .hardwareBindWrite:
            break
        case .hardwareModeVsAgent, .agentLinkageFirst:
            StudioNavigationRouter.shared.selectAgentSection(.status)
        case .voiceEmptyHistory:
            StudioNavigationRouter.shared.selectVoiceSection(.general)
        case .userCenterPermissions:
            NotificationCenter.default.post(name: .ahaKeyExpandUserCenterPermissions, object: nil)
        case .islandFirst:
            break
        case .islandLibrary:
            StudioNavigationRouter.shared.selectSettingsTab(.hardware)
        case .pluginComingSoon:
            break
        }
    }
}

enum FeatureCoachTipStore {
    private static let seenPrefix = "AhaKey.FeatureCoachTip.seen."

    static func isSeen(_ id: FeatureCoachTipID) -> Bool {
        UserDefaults.standard.bool(forKey: seenPrefix + id.rawValue)
    }

    static func markSeen(_ id: FeatureCoachTipID) {
        UserDefaults.standard.set(true, forKey: seenPrefix + id.rawValue)
    }

    static var onboardingCompleted: Bool {
        UserDefaults.standard.bool(forKey: UnifiedOnboardingStorage.completedKey)
    }

    static func canShow(_ id: FeatureCoachTipID) -> Bool {
        onboardingCompleted && !isSeen(id)
    }

    /// 重新打开新手引导时清空全部「已读」气泡，便于再次出现。
    static func resetAllSeen() {
        for id in FeatureCoachTipID.allCases {
            UserDefaults.standard.removeObject(forKey: seenPrefix + id.rawValue)
        }
    }
}

/// 全局协调：同屏最多一条 tip；离开锚点不记已读，点「知道了」/主操作才记。
@MainActor
final class FeatureCoachTipController: ObservableObject {
    static let shared = FeatureCoachTipController()

    @Published private(set) var presented: FeatureCoachTipID?

    /// 当前仍挂在界面上、希望展示的 tip（即使当时因未完成全屏引导而未能弹出）。
    private var interestedIDs: Set<FeatureCoachTipID> = []

    private init() {}

    func request(_ id: FeatureCoachTipID) {
        interestedIDs.insert(id)
        guard FeatureCoachTipStore.canShow(id) else { return }
        if let current = presented {
            if id.priority < current.priority {
                presented = id
            }
            return
        }
        presented = id
    }

    func dismissCurrent() {
        guard let current = presented else { return }
        FeatureCoachTipStore.markSeen(current)
        interestedIDs.remove(current)
        presented = nil
        // 关掉一条后，若同屏还有其它未读锚点，立刻补上一条。
        refreshInterested()
    }

    func performPrimaryAndDismiss() {
        guard let current = presented else { return }
        current.performPrimaryAction()
        FeatureCoachTipStore.markSeen(current)
        interestedIDs.remove(current)
        presented = nil
        refreshInterested()
    }

    /// 离开页面时撤回，不标记已读。
    func withdraw(_ id: FeatureCoachTipID) {
        interestedIDs.remove(id)
        if presented == id {
            presented = nil
            refreshInterested()
        }
    }

    func isShowing(_ id: FeatureCoachTipID) -> Bool {
        presented == id
    }

    /// 重放引导时清掉当前气泡，避免残留（保留 interested，等全屏结束后再弹）。
    func clearPresented() {
        presented = nil
    }

    /// 全屏引导刚完成 / 重放结束后：按优先级从仍挂着的锚点里弹出下一条。
    func refreshInterested() {
        let next = interestedIDs
            .filter { FeatureCoachTipStore.canShow($0) }
            .sorted { $0.priority < $1.priority }
            .first
        presented = next
    }
}

struct FeatureCoachTipBubble: View {
    let tip: FeatureCoachTipID
    var onDismiss: () -> Void
    var onPrimary: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AhakeySettingsTheme.accentBlue)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 6) {
                    Text(tip.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AhakeySettingsTheme.primaryText)

                    Text(tip.message)
                        .font(.system(size: 12))
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        Text("去点")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AhakeySettingsTheme.accentBlue)
                        Text(tip.targetLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AhakeySettingsTheme.primaryText)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AhakeySettingsTheme.accentBlue.opacity(0.10))
                    )
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button("知道了", action: onDismiss)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Spacer(minLength: 0)

                if let actionTitle = tip.primaryActionTitle, let onPrimary {
                    Button(actionTitle, action: onPrimary)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(AhakeySettingsTheme.accentBlue)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 380, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AhakeySettingsTheme.cardBackground)
                .shadow(color: Color.black.opacity(0.18), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AhakeySettingsTheme.accentBlue.opacity(0.35), lineWidth: 1)
        )
    }
}

struct FeatureCoachTipAnchorModifier: ViewModifier {
    let id: FeatureCoachTipID
    let isActive: Bool
    var alignment: Alignment = .top
    var enablePrimaryAction: Bool = true

    @ObservedObject private var controller = FeatureCoachTipController.shared
    @AppStorage(UnifiedOnboardingStorage.completedKey) private var onboardingCompleted = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: alignment) {
                if isActive, onboardingCompleted, controller.isShowing(id) {
                    FeatureCoachTipBubble(
                        tip: id,
                        onDismiss: { controller.dismissCurrent() },
                        onPrimary: (enablePrimaryAction && id.primaryActionTitle != nil)
                            ? { controller.performPrimaryAndDismiss() }
                            : nil
                    )
                    .padding(12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(50)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: controller.presented)
            .onAppear { syncRequest() }
            .onChange(of: isActive) { _ in syncRequest() }
            .onChange(of: onboardingCompleted) { completed in
                // 主壳在全屏引导下层一直挂着：completed 翻转时必须重新登记 / 唤醒气泡。
                if completed {
                    syncRequest()
                    controller.refreshInterested()
                } else {
                    controller.clearPresented()
                    if isActive {
                        controller.request(id)
                    }
                }
            }
            .onDisappear { controller.withdraw(id) }
    }

    private func syncRequest() {
        if isActive {
            controller.request(id)
        } else {
            controller.withdraw(id)
        }
    }
}

extension View {
    func featureCoachTip(
        _ id: FeatureCoachTipID,
        isActive: Bool,
        alignment: Alignment = .top,
        enablePrimaryAction: Bool = true
    ) -> some View {
        modifier(
            FeatureCoachTipAnchorModifier(
                id: id,
                isActive: isActive,
                alignment: alignment,
                enablePrimaryAction: enablePrimaryAction
            )
        )
    }
}

extension Notification.Name {
    static let ahaKeyExpandUserCenterPermissions = Notification.Name("lab.jawa.ahakeyconfig.expandUserCenterPermissions")
}
