import SwiftUI
import VibeBar
import UniformTypeIdentifiers
import AppKit

/// 四键键帽二级设置：外观 / 显隐 / 角色映射。
struct AhaKeyKeyPadSettingsPane: View {
    @ObservedObject var state: VibeBarState
    let brandName: String
    var onBack: () -> Void

    @State private var slots = VibeBarKeyPadSettings.slots
    @State private var selectedSlotID: String?
    @State private var statusMessage: String?

    private let presetIcons = [
        "mic", "mic.fill", "checkmark.circle.fill", "xmark.circle.fill",
        "return", "arrow.up.circle.fill", "hand.thumbsup.fill", "hand.thumbsdown.fill",
        "bolt.fill", "star.fill", "heart.fill", "flag.fill",
    ]

    private let presetColors: [(title: String, hex: String)] = [
        ("紫", "#BF59F2"), ("绿", "#42E86B"), ("红", "#FF7359"),
        ("蓝", "#56C2FF"), ("橙", "#FF9F0A"), ("白", "#FFFFFF"),
    ]

    var body: some View {
        AhakeyWrappedSettingsPane(title: "四键键帽", brandName: brandName, onBack: onBack) {
            Text("配置展开岛四键的外观与动作。隐藏后键区会压缩布局。")
                .font(AhakeySettingsTheme.rowSubtitleFont)
                .foregroundStyle(AhakeySettingsTheme.secondaryText)

            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AhakeySettingsTheme.accentBlue)
            }

            previewCard
            ForEach(slots) { slot in
                slotEditor(slot)
            }

            Button("重置为默认") {
                VibeBarKeyPadSettings.resetToDefaults()
                reload()
                statusMessage = "已恢复默认四键"
                clearStatusLater()
            }
            .buttonStyle(.bordered)
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: VibeBarKeyPadSettings.didChangeNotification)) { _ in
            reload()
        }
    }

    private var previewCard: some View {
        AhakeySettingsCard(sectionTitle: "预览") {
            VibeBarCommandKeyPad(
                keys: previewKeys,
                highlightStatus: state.agentStatus
            )
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.55))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            )
        }
    }

    private var previewKeys: [VibeBarCommandKey] {
        VibeBarKeyPadSettings.visibleSlots.map { slot in
            VibeBarCommandKey(
                id: slot.role.rawValue,
                title: slot.title,
                subtitle: slot.id.uppercased(),
                systemName: slot.systemImage,
                tint: slot.tintColor,
                action: {
                    selectedSlotID = slot.id
                }
            )
        }
    }

    private func slotEditor(_ slot: VibeBarKeyPadSlot) -> some View {
        let isSelected = selectedSlotID == slot.id
        return AhakeySettingsCard(sectionTitle: "\(slot.id.uppercased()) · \(slot.role.title)") {
            VStack(alignment: .leading, spacing: 12) {
                AhakeySettingsToggleRow(
                    title: "显示此键",
                    subtitle: slots.filter(\.isEnabled).count <= 1 && slot.isEnabled
                        ? "至少保留一颗可见键"
                        : nil,
                    isOn: Binding(
                        get: { slot.isEnabled },
                        set: { enabled in
                            var next = slot
                            next.isEnabled = enabled
                            commit(next)
                        }
                    )
                )

                AhakeySettingsCardDivider()

                labeledRow("角色") {
                    Picker("", selection: Binding(
                        get: { slot.role },
                        set: { role in
                            var next = slot
                            next.role = role
                            if next.title == slot.role.title || next.title.isEmpty {
                                next.title = role.title
                            }
                            if next.systemImage == slot.role.defaultSystemImage {
                                next.systemImage = role.defaultSystemImage
                            }
                            commit(next)
                        }
                    )) {
                        ForEach(VibeBarKeyPadRole.allCases) { role in
                            Text(role.title).tag(role)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }

                labeledRow("标题") {
                    TextField("标题", text: Binding(
                        get: { slot.title },
                        set: { title in
                            var next = slot
                            next.title = title
                            commit(next)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("图标")
                        .font(AhakeySettingsTheme.rowTitleFont)
                        .foregroundStyle(AhakeySettingsTheme.primaryText)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 8)], spacing: 8) {
                        ForEach(presetIcons, id: \.self) { icon in
                            Button {
                                var next = slot
                                next.systemImage = icon
                                commit(next)
                            } label: {
                                Image(systemName: icon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(slot.systemImage == icon ? .white : AhakeySettingsTheme.secondaryText)
                                    .frame(width: 36, height: 36)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(slot.systemImage == icon ? AhakeySettingsTheme.accentBlue.opacity(0.85) : AhakeySettingsTheme.controlFill)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)

                VStack(alignment: .leading, spacing: 8) {
                    Text("颜色")
                        .font(AhakeySettingsTheme.rowTitleFont)
                        .foregroundStyle(AhakeySettingsTheme.primaryText)
                    HStack(spacing: 8) {
                        ForEach(presetColors, id: \.hex) { item in
                            Button {
                                var next = slot
                                next.tintHex = item.hex
                                commit(next)
                            } label: {
                                Circle()
                                    .fill(Color(hex: item.hex) ?? .gray)
                                    .frame(width: 22, height: 22)
                                    .overlay(
                                        Circle().stroke(slot.tintHex == item.hex ? AhakeySettingsTheme.primaryText : AhakeySettingsTheme.divider, lineWidth: slot.tintHex == item.hex ? 2 : 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(item.title)
                        }
                    }
                }
                .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
                .padding(.bottom, 8)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? AhakeySettingsTheme.accentBlue.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .onTapGesture { selectedSlotID = slot.id }
    }

    private func labeledRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(AhakeySettingsTheme.rowTitleFont)
                .foregroundStyle(AhakeySettingsTheme.primaryText)
            Spacer()
            content()
        }
        .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
    }

    private func commit(_ slot: VibeBarKeyPadSlot) {
        VibeBarKeyPadSettings.updateSlot(slot)
        reload()
        NotificationCenter.default.post(name: .ahaKeyIslandAppearanceApplyRequested, object: nil)
    }

    private func reload() {
        slots = VibeBarKeyPadSettings.slots
        if selectedSlotID == nil {
            selectedSlotID = slots.first?.id
        }
    }

    private func clearStatusLater() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            statusMessage = nil
        }
    }
}

/// Agent · 设置：仅皮肤与状态图标。
struct AhaKeyPetAppearanceEditor: View {
    var agentTaskTitle: String = ""

    @State private var appearance = VibeBarPetAppearanceSettings.appearance
    @State private var previewStatus: VibeBarAgentStatus = .thinking
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("选择极简圆点（默认）或状态 emoji，并可自定义各状态图标。动画、尺寸、信息层与 GIF 请到灵动岛 · 组件库 · OLED Pet。")
                .font(AhakeySettingsTheme.rowSubtitleFont)
                .foregroundStyle(AhakeySettingsTheme.secondaryText)

            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AhakeySettingsTheme.accentBlue)
            }

            previewCard
            skinCard
            if appearance.skinId == .classicEmoji {
                emojiCustomizeCard
            }

            Button("重置皮肤与图标") {
                commit { value in
                    value.skinId = .minimalDot
                    value.statusOverrides = [:]
                }
                statusMessage = "已恢复默认皮肤与图标"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { statusMessage = nil }
            }
            .buttonStyle(.bordered)
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: VibeBarPetAppearanceSettings.didChangeNotification)) { _ in
            reload()
        }
    }

    private var previewCard: some View {
        AhakeySettingsCard(sectionTitle: "预览") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("预览状态", selection: $previewStatus) {
                    ForEach(VibeBarAgentStatus.allCases) { status in
                        Text(status.title).tag(status)
                    }
                }
                .pickerStyle(.menu)

                VibeBarAIPetOLED(
                    status: previewStatus,
                    taskTitle: previewTaskTitle,
                    progress: previewStatus == .coding || previewStatus == .thinking ? 0.55 : 0,
                    appearance: appearance,
                    onTap: {
                        let all = VibeBarAgentStatus.allCases
                        if let idx = all.firstIndex(of: previewStatus) {
                            previewStatus = all[(idx + 1) % all.count]
                        }
                    }
                )
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 12)
        }
    }

    private var previewTaskTitle: String {
        switch previewStatus {
        case .listening: return "Voice input active"
        case .thinking: return "Analyzing context"
        case .coding: return "Generating changes"
        case .approval: return "Waiting for your confirm"
        default: return agentTaskTitle.isEmpty ? "Ready for next task" : agentTaskTitle
        }
    }

    private var skinCard: some View {
        AhakeySettingsCard(sectionTitle: "外观模式") {
            HStack(spacing: 10) {
                ForEach(VibeBarPetSkin.allCases) { skin in
                    Button {
                        commit { $0.skinId = skin }
                    } label: {
                        VStack(spacing: 6) {
                            Text(skin.glyph(for: previewStatus))
                                .font(.system(size: 28))
                            Text(skin.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AhakeySettingsTheme.primaryText)
                            Text(skin.detail)
                                .font(.system(size: 10))
                                .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(AhakeySettingsTheme.controlFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(appearance.skinId == skin ? AhakeySettingsTheme.accentBlue.opacity(0.55) : AhakeySettingsTheme.divider, lineWidth: appearance.skinId == skin ? 1.2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 12)
        }
    }

    private var emojiCustomizeCard: some View {
        AhakeySettingsCard(sectionTitle: "自定义状态图标") {
            Text("为各 Agent 状态填写 emoji 或符号；留空则使用默认状态 emoji。")
                .font(AhakeySettingsTheme.rowSubtitleFont)
                .foregroundStyle(AhakeySettingsTheme.secondaryText)
                .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
                .padding(.top, 12)

            ForEach(VibeBarAgentStatus.allCases) { status in
                statusGlyphRow(status)
                if status != VibeBarAgentStatus.allCases.last {
                    AhakeySettingsCardDivider()
                }
            }
        }
    }

    private func statusGlyphRow(_ status: VibeBarAgentStatus) -> some View {
        let override = appearance.statusOverrides[status.rawValue] ?? VibeBarPetStatusOverride()
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(appearance.glyph(for: status))
                    .font(.system(size: 18))
                    .frame(width: 28)
                Text(status.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
                Spacer(minLength: 0)
                Text("默认 \(status.petEmoji)")
                    .font(.system(size: 10))
                    .foregroundStyle(AhakeySettingsTheme.tertiaryText)
            }

            TextField("自定义 emoji / 符号", text: Binding(
                get: { override.glyph ?? "" },
                set: { text in
                    commit { appearance in
                        var map = appearance.statusOverrides
                        var value = map[status.rawValue] ?? VibeBarPetStatusOverride()
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        value.glyph = trimmed.isEmpty ? nil : trimmed
                        if value.glyph == nil && value.animationStyle == nil {
                            map.removeValue(forKey: status.rawValue)
                        } else {
                            map[status.rawValue] = value
                        }
                        appearance.statusOverrides = map
                    }
                }
            ))
            .textFieldStyle(.roundedBorder)
        }
        .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
        .padding(.vertical, 8)
    }

    private func commit(_ mutate: (inout VibeBarPetAppearance) -> Void) {
        VibeBarPetAppearanceSettings.update(mutate)
        reload()
        NotificationCenter.default.post(name: .ahaKeyIslandAppearanceApplyRequested, object: nil)
    }

    private func reload() {
        appearance = VibeBarPetAppearanceSettings.appearance
    }
}

/// 灵动岛 · 组件库 · OLED Pet：信息层、尺寸、动画、自定义 GIF。
struct AhaKeyOledPetIslandSettingsEditor: View {
    @State private var appearance = VibeBarPetAppearanceSettings.appearance
    @State private var showAdvanced = false
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("配置展开岛 Pet 的信息层、尺寸、动画与软件岛 GIF。皮肤与状态图标请到 Agent · 设置。")
                .font(AhakeySettingsTheme.rowSubtitleFont)
                .foregroundStyle(AhakeySettingsTheme.secondaryText)

            Button {
                StudioNavigationRouter.shared.openPetAppearanceSettings()
            } label: {
                HStack {
                    Text("去 Agent · 设置改外观（皮肤 / 图标）")
                        .font(AhakeySettingsTheme.rowTitleFont)
                        .foregroundStyle(AhakeySettingsTheme.accentBlue)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AhakeySettingsTheme.accentBlue)
                }
                .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AhakeySettingsTheme.controlFill)
                )
            }
            .buttonStyle(.plain)

            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AhakeySettingsTheme.accentBlue)
            }

            layoutCard
            sizeCard
            animationCard
            advancedCard
            customAssetCard

            Button("重置岛侧设置") {
                commit { value in
                    let defaults = VibeBarPetAppearance.default
                    value.showsStatusLabel = defaults.showsStatusLabel
                    value.showsTaskTitle = defaults.showsTaskTitle
                    value.showsProgress = defaults.showsProgress
                    value.petSize = defaults.petSize
                    value.animationStyle = defaults.animationStyle
                    value.animationSpeed = defaults.animationSpeed
                    value.customAssetPath = nil
                    // 保留皮肤与图标覆盖，只清动画覆盖
                    var map = value.statusOverrides
                    for key in Array(map.keys) {
                        guard var entry = map[key] else { continue }
                        entry.animationStyle = nil
                        if entry.glyph == nil {
                            map.removeValue(forKey: key)
                        } else {
                            map[key] = entry
                        }
                    }
                    value.statusOverrides = map
                }
                statusMessage = "已恢复默认岛侧设置"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { statusMessage = nil }
            }
            .buttonStyle(.bordered)
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: VibeBarPetAppearanceSettings.didChangeNotification)) { _ in
            reload()
        }
    }

    private var layoutCard: some View {
        AhakeySettingsCard(sectionTitle: "信息层") {
            AhakeySettingsToggleRow(
                title: "显示状态名",
                subtitle: nil,
                isOn: Binding(
                    get: { appearance.showsStatusLabel },
                    set: { value in commit { $0.showsStatusLabel = value } }
                )
            )
            AhakeySettingsCardDivider()
            AhakeySettingsToggleRow(
                title: "显示任务标题",
                subtitle: nil,
                isOn: Binding(
                    get: { appearance.showsTaskTitle },
                    set: { value in commit { $0.showsTaskTitle = value } }
                )
            )
            AhakeySettingsCardDivider()
            AhakeySettingsToggleRow(
                title: "显示进度条",
                subtitle: nil,
                isOn: Binding(
                    get: { appearance.showsProgress },
                    set: { value in commit { $0.showsProgress = value } }
                )
            )
        }
    }

    private var sizeCard: some View {
        AhakeySettingsCard(sectionTitle: "尺寸") {
            HStack {
                Text("Pet 尺寸")
                    .font(AhakeySettingsTheme.rowTitleFont)
                    .foregroundStyle(AhakeySettingsTheme.primaryText)
                Spacer()
                Picker("", selection: Binding(
                    get: { appearance.petSize },
                    set: { value in commit { $0.petSize = value } }
                )) {
                    ForEach(VibeBarPetSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 12)
        }
    }

    private var animationCard: some View {
        AhakeySettingsCard(sectionTitle: "动画") {
            HStack {
                Text("样式")
                    .font(AhakeySettingsTheme.rowTitleFont)
                    .foregroundStyle(AhakeySettingsTheme.primaryText)
                Spacer()
                Picker("", selection: Binding(
                    get: { appearance.animationStyle },
                    set: { value in commit { $0.animationStyle = value } }
                )) {
                    ForEach(VibeBarPetAnimationStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 100)
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 10)

            AhakeySettingsCardDivider()

            HStack {
                Text("速度")
                    .font(AhakeySettingsTheme.rowTitleFont)
                    .foregroundStyle(AhakeySettingsTheme.primaryText)
                Spacer()
                Picker("", selection: Binding(
                    get: { appearance.animationSpeed },
                    set: { value in commit { $0.animationSpeed = value } }
                )) {
                    ForEach(VibeBarPetAnimationSpeed.allCases) { speed in
                        Text(speed.title).tag(speed)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 12)
        }
    }

    private var advancedCard: some View {
        AhakeySettingsCard(sectionTitle: "高级 · 按状态动画覆盖") {
            DisclosureGroup(isExpanded: $showAdvanced) {
                ForEach(VibeBarAgentStatus.allCases) { status in
                    statusAnimationRow(status)
                    if status != VibeBarAgentStatus.allCases.last {
                        AhakeySettingsCardDivider()
                    }
                }
            } label: {
                Text(showAdvanced ? "收起状态动画表" : "展开状态动画表")
                    .font(AhakeySettingsTheme.rowTitleFont)
                    .foregroundStyle(AhakeySettingsTheme.primaryText)
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 12)
        }
    }

    private func statusAnimationRow(_ status: VibeBarAgentStatus) -> some View {
        let override = appearance.statusOverrides[status.rawValue] ?? VibeBarPetStatusOverride()
        return HStack {
            Text(status.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AhakeySettingsTheme.secondaryText)
            Spacer()
            Picker("动画", selection: Binding(
                get: { override.animationStyle?.rawValue ?? "inherit" },
                set: { raw in
                    commit { appearance in
                        var map = appearance.statusOverrides
                        var value = map[status.rawValue] ?? VibeBarPetStatusOverride()
                        value.animationStyle = raw == "inherit" ? nil : VibeBarPetAnimationStyle(rawValue: raw)
                        if value.glyph == nil && value.animationStyle == nil {
                            map.removeValue(forKey: status.rawValue)
                        } else {
                            map[status.rawValue] = value
                        }
                        appearance.statusOverrides = map
                    }
                }
            )) {
                Text("跟随全局").tag("inherit")
                ForEach(VibeBarPetAnimationStyle.allCases) { style in
                    Text(style.title).tag(style.rawValue)
                }
            }
            .labelsHidden()
            .frame(width: 110)
        }
        .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
        .padding(.vertical, 8)
    }

    private var customAssetCard: some View {
        AhakeySettingsCard(sectionTitle: "自定义素材（软件岛）") {
            VStack(alignment: .leading, spacing: 10) {
                Text(appearance.customAssetPath?.isEmpty == false
                      ? (appearance.resolvedCustomAssetURL?.lastPathComponent ?? "路径无效，将回退皮肤")
                      : "未选择自定义 GIF")
                    .font(AhakeySettingsTheme.rowSubtitleFont)
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)

                HStack(spacing: 10) {
                    Button("选择 GIF…") { pickCustomGIF() }
                        .buttonStyle(.borderedProminent)
                    Button("清除") {
                        commit { $0.customAssetPath = nil }
                    }
                    .buttonStyle(.bordered)
                    .disabled(appearance.customAssetPath == nil)
                }
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 12)
        }
    }

    private func pickCustomGIF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.gif]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        commit { $0.customAssetPath = url.path }
        statusMessage = "已设置自定义 GIF（仅软件岛）"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { statusMessage = nil }
    }

    private func commit(_ mutate: (inout VibeBarPetAppearance) -> Void) {
        VibeBarPetAppearanceSettings.update(mutate)
        reload()
        NotificationCenter.default.post(name: .ahaKeyIslandAppearanceApplyRequested, object: nil)
    }

    private func reload() {
        appearance = VibeBarPetAppearanceSettings.appearance
    }
}

/// 灵动岛 · 组件库 → OLED Pet 子页。
struct AhaKeyOledPetSettingsPane: View {
    @ObservedObject var state: VibeBarState
    let brandName: String
    var onBack: () -> Void

    var body: some View {
        AhakeyWrappedSettingsPane(title: "OLED Pet", brandName: brandName, onBack: onBack) {
            AhaKeyOledPetIslandSettingsEditor()
        }
    }
}
