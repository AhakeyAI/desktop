import SwiftUI
import AhaKeyConfigShared

struct PowerProtectionSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject var manager: PowerProtectionManager
    @StateObject var processDetector: ProcessDetector
    @State private var showResetAlert = false

    // Local slider values prevent UserDefaults thrashing while dragging.
    @State private var l3BatteryValue: Double = 20
    @State private var fullReleaseBatteryValue: Double = 10
    @State private var maxDurationValue: TimeInterval = 7200

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(NSLocalizedString("合盖运行设置", comment: ""))
                    .font(.headline)
                Spacer()
                Button(NSLocalizedString("关闭", comment: "")) { dismiss() }
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switchesSection

                    Divider()

                    targetsSection

                    Divider()

                    safetySection

                    Divider()

                    resetSection
                }
                .padding(18)
            }
        }
        .onAppear {
            l3BatteryValue = Double(manager.safetySettings.l3DisableBatteryThreshold)
            fullReleaseBatteryValue = Double(manager.safetySettings.fullReleaseBatteryThreshold)
            maxDurationValue = manager.safetySettings.maxLidCloseDuration
        }
        .onChange(of: manager.safetySettings.l3DisableBatteryThreshold) { newValue in
            l3BatteryValue = Double(newValue)
        }
        .onChange(of: manager.safetySettings.fullReleaseBatteryThreshold) { newValue in
            fullReleaseBatteryValue = Double(newValue)
        }
        .onChange(of: manager.safetySettings.maxLidCloseDuration) { newValue in
            maxDurationValue = newValue
        }
        .alert(NSLocalizedString("确认恢复", comment: ""), isPresented: $showResetAlert) {
            Button(NSLocalizedString("恢复", comment: ""), role: .destructive) {
                manager.deactivateAll()
                manager.enabled = false
            }
            Button(NSLocalizedString("取消", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("这会立即释放所有合盖运行断言和虚拟显示器。", comment: ""))
        }
    }

    private var switchesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("总开关", comment: ""))
                .font(.callout.weight(.semibold))

            Toggle(NSLocalizedString("编程时阻止系统休眠", comment: ""), isOn: $manager.enabled)
                .toggleStyle(.switch)

            if manager.isLidCloseProtectionAvailable {
                Toggle(NSLocalizedString("合盖后也继续运行", comment: ""), isOn: $manager.lidCloseProtectionEnabled)
                    .toggleStyle(.switch)
            } else {
                HStack {
                    Text(NSLocalizedString("合盖保护", comment: ""))
                    Spacer()
                    Text(NSLocalizedString("需 macOS 14 或更高版本", comment: ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(manager.statusSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var targetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("检测目标", comment: ""))
                .font(.callout.weight(.semibold))

            ForEach($processDetector.targets) { $target in
                Toggle(target.name, isOn: $target.isEnabled)
            }
        }
    }

    private var safetySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("安全阈值", comment: ""))
                .font(.callout.weight(.semibold))

            HStack {
                Text(NSLocalizedString("L3 禁用电量", comment: ""))
                Spacer()
                Text("\(Int(l3BatteryValue))%")
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: $l3BatteryValue,
                in: 5...50,
                step: 1,
                onEditingChanged: { isEditing in
                    if !isEditing {
                        manager.safetySettings.l3DisableBatteryThreshold = Int(l3BatteryValue)
                    }
                }
            )

            HStack {
                Text(NSLocalizedString("完全释放电量", comment: ""))
                Spacer()
                Text("\(Int(fullReleaseBatteryValue))%")
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: $fullReleaseBatteryValue,
                in: 1...20,
                step: 1,
                onEditingChanged: { isEditing in
                    if !isEditing {
                        manager.safetySettings.fullReleaseBatteryThreshold = Int(fullReleaseBatteryValue)
                    }
                }
            )

            HStack {
                Text(NSLocalizedString("最大合盖保护时长", comment: ""))
                Spacer()
                Text(formatDuration(maxDurationValue))
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: $maxDurationValue,
                in: 600...14400,
                step: 600,
                onEditingChanged: { isEditing in
                    if !isEditing {
                        manager.safetySettings.maxLidCloseDuration = maxDurationValue
                    }
                }
            )

            Toggle(NSLocalizedString("始终允许（忽略所有限制）", comment: ""), isOn: $manager.safetySettings.alwaysAllow)
                .toggleStyle(.switch)
        }
    }

    private var resetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(NSLocalizedString("立即恢复正常休眠", comment: "")) {
                showResetAlert = true
            }
            .foregroundStyle(.red)
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 && minutes > 0 {
            return String(format: NSLocalizedString("%d小时%d分钟", comment: ""), hours, minutes)
        } else if hours > 0 {
            return String(format: NSLocalizedString("%d小时", comment: ""), hours)
        } else {
            return String(format: NSLocalizedString("%d分钟", comment: ""), minutes)
        }
    }
}

struct PowerProtectionSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        PowerProtectionSettingsView(
            manager: PowerProtectionManager(),
            processDetector: ProcessDetector()
        )
    }
}
