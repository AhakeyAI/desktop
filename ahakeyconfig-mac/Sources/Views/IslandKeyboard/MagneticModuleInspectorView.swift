import SwiftUI

struct MagneticModuleInspectorView: View {
    @Binding var moduleState: MagneticModuleState
    var onToggleVirtualSwitch: (() -> Void)?
    var isEmbedded: Bool = true

    @State private var lockedModuleHint: MagneticModuleType?

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InspectorSection(title: "磁吸模块", isEmbedded: isEmbedded) {
                if !moduleState.isConnected {
                    HStack(spacing: 8) {
                        Image(systemName: "square.dashed")
                            .foregroundStyle(.secondary)
                        Text("当前为空槽，请从下方选择要吸附的模块。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.04))
                    )
                }

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(MagneticModuleType.attachableCases) { module in
                        moduleCard(module)
                    }
                }

                Button {
                    moduleState.attachedType = .none
                } label: {
                    Label("清空磁吸槽", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!moduleState.isConnected)
            }

            if moduleState.isConnected {
                moduleControls
            }

            if !MagneticModuleUnlockStore.previewAssumeAllPurchased,
               !MagneticModuleUnlockStore.lockedPurchasableModules().isEmpty {
                InspectorSection(title: "未解锁套件", isEmbedded: isEmbedded) {
                    ForEach(MagneticModuleUnlockStore.lockedPurchasableModules()) { module in
                        HStack(spacing: 8) {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text(module.title)
                                .font(.caption)
                            Spacer()
                            Text("需购买")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .alert(item: $lockedModuleHint) { module in
            Alert(
                title: Text("\(module.title) 未解锁"),
                message: Text("该磁吸模块需单独购买套件。购买并绑定账号后将自动解锁。"),
                dismissButton: .default(Text("知道了"))
            )
        }
    }

    @ViewBuilder
    private func moduleCard(_ module: MagneticModuleType) -> some View {
        let selected = moduleState.attachedType == module
        let unlocked = MagneticModuleUnlockStore.isUnlocked(module)
        let showsLock = MagneticModuleUnlockStore.showsLockedInUI(module)
        Button {
            if unlocked {
                moduleState.attachedType = module
            } else {
                lockedModuleHint = module
            }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: module.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(unlocked ? Color.primary : Color.secondary.opacity(0.45))
                    if showsLock {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.orange)
                            .offset(x: 8, y: -6)
                    } else if module.isIncludedByDefault {
                        Text("免费")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.18)))
                            .foregroundStyle(.green)
                            .offset(x: 10, y: -8)
                    } else if module.requiresPurchase, MagneticModuleUnlockStore.previewAssumeAllPurchased {
                        Text("测试")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.blue.opacity(0.14)))
                            .foregroundStyle(.blue)
                            .offset(x: 10, y: -8)
                    }
                }
                Text(module.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(unlocked ? Color.primary : Color.secondary)
                Text(MagneticModuleUnlockStore.moduleCardSubtitle(for: module))
                    .font(.system(size: 9))
                    .foregroundStyle(showsLock ? Color.orange.opacity(0.85) : Color.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
                    .opacity(unlocked ? 1 : 0.72)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? Color.accentColor : Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!unlocked && !module.requiresPurchase)
    }

    @ViewBuilder
    private var moduleControls: some View {
        InspectorSection(title: "\(moduleState.attachedType.title) 模拟", isEmbedded: isEmbedded) {
            switch moduleState.attachedType {
            case .none:
                EmptyView()
            case .toggle:
                toggleControls
            case .joystick:
                joystickControls
            case .knob:
                knobControls
            case .scrollWheel:
                scrollControls
            case .dpad:
                dpadControls
            }
        }
    }

    private var toggleControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("档位")
                    .font(.callout)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 4)
                Picker("", selection: $moduleState.togglePosition) {
                    Text("自动批准").tag(0)
                    Text("手动批准").tag(1)
                    Text("中间档").tag(2)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 120, alignment: .trailing)
            }
            Text("当前：\(moduleState.toggleTitle)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let onToggleVirtualSwitch {
                Button("同步虚拟拨杆（0x91 占位）") {
                    onToggleVirtualSwitch()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.top, 4)
    }

    private var joystickControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            JoystickPad(x: $moduleState.joystickX, y: $moduleState.joystickY)
                .frame(height: 140)
            Text("X: \(moduleState.joystickX)  Y: \(moduleState.joystickY)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var knobControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper("累计增量：\(moduleState.knobDelta)", value: $moduleState.knobDelta, in: -999...999)
            Button("归零") { moduleState.knobDelta = 0 }
                .buttonStyle(.borderless)
        }
        .padding(.top, 4)
    }

    private var scrollControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper("滚动增量：\(moduleState.scrollDelta)", value: $moduleState.scrollDelta, in: -999...999)
            Button("归零") { moduleState.scrollDelta = 0 }
                .buttonStyle(.borderless)
        }
        .padding(.top, 4)
    }

    private var dpadControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                dpadButton(.up)
            }
            HStack(spacing: 8) {
                dpadButton(.left)
                dpadButton(.center)
                dpadButton(.right)
            }
            HStack(spacing: 8) {
                dpadButton(.down)
            }
            if let dir = moduleState.dpadDirection {
                Text("当前方向：\(dir.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func dpadButton(_ direction: DPadDirection) -> some View {
        let selected = moduleState.dpadDirection == direction
        return Button {
            moduleState.dpadDirection = direction
        } label: {
            Text(direction.title)
                .font(.callout.weight(.semibold))
                .frame(width: 44, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selected ? Color.accentColor.opacity(0.2) : Color(nsColor: .controlBackgroundColor))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct JoystickPad: View {
    @Binding var x: Int
    @Binding var y: Int

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let knobX = center.x + CGFloat(x) / 100 * (size / 2 - 16)
            let knobY = center.y - CGFloat(y) / 100 * (size / 2 - 16)

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.06))
                Circle()
                    .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    .frame(width: size - 24, height: size - 24)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 28, height: 28)
                    .shadow(radius: 3, y: 1)
                    .position(x: knobX, y: knobY)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let dx = value.location.x - center.x
                                let dy = center.y - value.location.y
                                let maxR = size / 2 - 16
                                x = Int(max(-100, min(100, dx / maxR * 100)))
                                y = Int(max(-100, min(100, dy / maxR * 100)))
                            }
                    )
            }
        }
    }
}

struct MagneticModuleSummaryView: View {
    let moduleState: MagneticModuleState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summaryRow("吸附模块", value: moduleState.isConnected ? moduleState.attachedType.title : "空槽",
                       dot: moduleState.isConnected ? .green : .orange)
            if moduleState.isConnected {
                summaryRow("模块来源", value: MagneticModuleUnlockStore.moduleSourceLabel(for: moduleState.attachedType),
                           dot: MagneticModuleUnlockStore.isUnlocked(moduleState.attachedType) ? .green : .orange)
            }
            if moduleState.attachedType == .toggle {
                summaryRow("拨杆档位", value: moduleState.toggleTitle)
            }
            if moduleState.attachedType == .joystick {
                summaryRow("摇杆", value: "X \(moduleState.joystickX) · Y \(moduleState.joystickY)")
            }
            if moduleState.attachedType == .knob {
                summaryRow("旋钮增量", value: "\(moduleState.knobDelta)")
            }
            if moduleState.attachedType == .scrollWheel {
                summaryRow("滚轮增量", value: "\(moduleState.scrollDelta)")
            }
            if moduleState.attachedType == .dpad, let dir = moduleState.dpadDirection {
                summaryRow("方向键", value: dir.title)
            }
        }
    }

    private func summaryRow(_ label: String, value: String, dot: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            HStack(spacing: 6) {
                if let dot {
                    Circle().fill(dot).frame(width: 7, height: 7)
                }
                Text(value)
                    .font(.callout)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5)
        }
    }
}

struct OceanLightInspectorView: View {
    @Binding var config: OceanLightConfig
    var onApply: (() -> Void)?
    var isEmbedded: Bool = true

    @State private var showMoreOcean = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InspectorSection(title: "灯效配置", isEmbedded: isEmbedded) {
                Toggle("灯效总开关", isOn: $config.powerSwitchEnabled)
                HStack {
                    Text("亮度")
                    Slider(value: $config.brightness, in: 0.1...1)
                    Text("\(Int(config.brightness * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }

                Text("预设（10 种）")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isEmbedded ? AhaKeyStudioEmbeddedTheme.secondaryText : .secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                    ForEach(OceanLightPreset.all) { preset in
                        presetCard(preset)
                    }
                }
            }

            AhaKeyStudioDisclosureSection(
                title: "更多海洋灯",
                subtitle: "IMU、文字轮播与占位下发",
                isEmbedded: isEmbedded,
                isExpanded: $showMoreOcean
            ) {
                Toggle("IMU 重力联动", isOn: $config.imuEnabled)

                TextField("输入轮播文字（最多 48 字符）", text: $config.marqueeText)
                    .textFieldStyle(.roundedBorder)

                if let onApply {
                    Button("应用到设备（占位）") { onApply() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!config.powerSwitchEnabled)
                }
            }
        }
    }

    private func presetCard(_ preset: OceanLightPreset) -> some View {
        let selected = config.selectedPresetId == preset.id
        return Button {
            config.selectedPresetId = preset.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(Array(preset.previewColors.enumerated()), id: \.offset) { _, color in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color)
                            .frame(height: 8)
                    }
                }
                Text(preset.name)
                    .font(.callout.weight(.semibold))
                Text("#\(preset.id)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? Color.accentColor : Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct OceanLightSummaryView: View {
    let config: OceanLightConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summaryRow("预设", value: config.selectedPreset.name)
            summaryRow("亮度", value: "\(Int(config.brightness * 100))%")
            summaryRow("IMU 联动", value: config.imuEnabled ? "开启" : "关闭",
                       dot: config.imuEnabled ? .green : .gray)
            summaryRow("总开关", value: config.powerSwitchEnabled ? "开启" : "关闭",
                       dot: config.powerSwitchEnabled ? .green : .orange)
            if !config.marqueeText.isEmpty {
                summaryRow("轮播文字", value: String(config.marqueeText.prefix(24)))
            }
        }
    }

    private func summaryRow(_ label: String, value: String, dot: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            HStack(spacing: 6) {
                if let dot {
                    Circle().fill(dot).frame(width: 7, height: 7)
                }
                Text(value)
                    .font(.callout)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5)
        }
    }
}
