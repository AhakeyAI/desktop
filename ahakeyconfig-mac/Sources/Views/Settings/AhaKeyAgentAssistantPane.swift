import SwiftUI
import VibeBar

private struct AgentChatMessage: Identifiable, Equatable {
    let id: UUID
    let isUser: Bool
    var text: String
    var isPending: Bool
    var followUps: [String]

    init(
        id: UUID = UUID(),
        isUser: Bool,
        text: String,
        isPending: Bool = false,
        followUps: [String] = []
    ) {
        self.id = id
        self.isUser = isUser
        self.text = text
        self.isPending = isPending
        self.followUps = followUps
    }
}

struct AhaKeyAgentAssistantPane: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @StateObject private var agentManager = AgentManager.shared
    @State private var petAppearance = VibeBarPetAppearanceSettings.appearance
    @State private var draft = ""
    @State private var isTyping = false
    @State private var messages: [AgentChatMessage] = [
        AgentChatMessage(
            isUser: false,
            text: "我是设备管家。先启用联动，再说「查状态」或点下面的建议。",
            followUps: ["一键启用联动", "帮我查一下联动状态", "打开联动页"]
        )
    ]

    private var tools: AgentAssistantTools { AgentAssistantTools(bleManager: bleManager) }

    private var isLinkageReady: Bool {
        agentManager.isInstalled
            && agentManager.isRunning
            && agentManager.bluetoothConnectionOwner == .agentDaemon
    }

    private var headerStatus: VibeBarAgentStatus {
        isTyping ? .thinking : .idle
    }

    private var statusLine: String {
        if isTyping { return "正在处理…" }
        if isLinkageReady { return "联动就绪 · 可以说自然语言下达任务" }
        return "联动未就绪 · 可说「一键启用」"
    }

    private var statusDotColor: Color {
        if isTyping { return Color.orange }
        if isLinkageReady { return Color.green.opacity(0.85) }
        return Color.orange.opacity(0.9)
    }

    var body: some View {
        VStack(spacing: 0) {
            identityHeader
                .padding(.bottom, 16)

            messageList
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
                .background(AhakeySettingsTheme.divider)
                .padding(.top, 4)

            bottomComposer
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .featureCoachTip(.agentLinkageFirst, isActive: !isLinkageReady, alignment: .topTrailing)
        .onAppear { agentManager.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: VibeBarPetAppearanceSettings.didChangeNotification)) { _ in
            petAppearance = VibeBarPetAppearanceSettings.appearance
        }
    }

    // MARK: - Header

    private var identityHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            AgentPetLiveMark(
                glyph: petAppearance.glyph(for: headerStatus),
                tint: headerStatus.lightPrimary,
                style: isTyping
                    ? .busy
                    : AgentPetLiveStyle(from: petAppearance.animationStyle(for: headerStatus)),
                period: isTyping ? 0.9 : petAppearance.animationSpeed.period,
                size: 56,
                glyphSize: 28,
                cornerRadius: 16,
                onTap: { /* 轻点也有反馈，增强互动感 */ }
            )

            VStack(alignment: .leading, spacing: 5) {
                Text("设备管家")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AhakeySettingsTheme.primaryText)

                HStack(spacing: 6) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 6, height: 6)
                        .modifier(AgentStatusDotPulse(active: isTyping || !isLinkageReady))
                    Text(statusLine)
                        .font(.system(size: 12))
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Button {
                StudioNavigationRouter.shared.openPetAppearanceSettings()
            } label: {
                Image(systemName: "paintbrush.pointed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(AhakeySettingsTheme.controlFill)
                    )
            }
            .buttonStyle(.plain)
            .help("修改 Pet 外观（Agent · 设置）")
        }
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(messages) { message in
                        chatRow(message)
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: message.isUser ? .trailing : .leading)),
                                removal: .opacity
                            ))
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .onChange(of: messages) { _ in
                scrollToBottom(proxy: proxy)
            }
            .onAppear {
                scrollToBottom(proxy: proxy)
            }
        }
    }

    @ViewBuilder
    private func chatRow(_ message: AgentChatMessage) -> some View {
        if message.isUser {
            userBubble(message)
        } else {
            assistantBubble(message)
        }
    }

    private func userBubble(_ message: AgentChatMessage) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            Spacer(minLength: 72)
            Text(message.text)
                .font(.system(size: 13.5))
                .foregroundStyle(Color.white.opacity(0.96))
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AhakeySettingsTheme.accentBlue)
                )
        }
    }

    private func assistantBubble(_ message: AgentChatMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            petAvatar(thinking: message.isPending)

            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if message.isPending {
                        typingIndicator
                    } else {
                        Text(message.text)
                            .font(.system(size: 13.5))
                            .foregroundStyle(AhakeySettingsTheme.primaryText)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AhakeySettingsTheme.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AhakeySettingsTheme.divider, lineWidth: 1)
                )

                if !message.isPending, !message.followUps.isEmpty {
                    followUpLinks(message.followUps)
                }
            }
            .frame(maxWidth: 460, alignment: .leading)

            Spacer(minLength: 48)
        }
    }

    private func petAvatar(thinking: Bool) -> some View {
        let status: VibeBarAgentStatus = thinking ? .thinking : .idle
        return AgentPetLiveMark(
            glyph: petAppearance.glyph(for: status),
            tint: status.lightPrimary,
            style: thinking
                ? .busy
                : AgentPetLiveStyle(from: petAppearance.animationStyle(for: status)),
            period: thinking ? 0.85 : max(1.1, petAppearance.animationSpeed.period),
            size: 28,
            glyphSize: 15,
            cornerRadius: 14,
            isCircle: true
        )
    }

    private var typingIndicator: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(AhakeySettingsTheme.secondaryText)
                    .frame(width: 5, height: 5)
                    .opacity(0.4)
                    .modifier(AgentTypingDotBounce(index: index))
            }
            Text("…")
                .font(.system(size: 12))
                .foregroundStyle(AhakeySettingsTheme.tertiaryText)
        }
        .padding(.vertical, 2)
    }

    private func followUpLinks(_ phrases: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(phrases.enumerated()), id: \.offset) { _, phrase in
                Button {
                    sendNatural(phrase)
                } label: {
                    HStack(spacing: 4) {
                        Text("→")
                            .font(.system(size: 11, weight: .medium))
                        Text(phrase)
                            .font(.system(size: 12, weight: .medium))
                            .underline(true, color: AhakeySettingsTheme.accentBlue.opacity(0.35))
                    }
                    .foregroundStyle(AhakeySettingsTheme.accentBlue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 2)
    }

    // MARK: - Composer

    private var bottomComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(AgentAssistantIntent.quickChips) { intent in
                        Button {
                            sendNatural(intent.naturalPhrase)
                        } label: {
                            Text(intent.chipTitle)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(AhakeySettingsTheme.secondaryText)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(AhakeySettingsTheme.controlFill)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 0) {
                TextField("跟管家说点什么…", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .padding(.leading, 14)
                    .padding(.vertical, 12)
                    .onSubmit(submitDraft)

                Button {
                    submitDraft()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(
                            canSend
                                ? Color.white
                                : AhakeySettingsTheme.tertiaryText
                        )
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(
                                    canSend
                                        ? AhakeySettingsTheme.accentBlue
                                        : AhakeySettingsTheme.controlFill
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .padding(.trailing, 10)
                .accessibilityLabel("发送")
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AhakeySettingsTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AhakeySettingsTheme.divider, lineWidth: 1)
            )
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Actions

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let last = messages.last else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func submitDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        sendNatural(text)
    }

    private func sendNatural(_ text: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            messages.append(AgentChatMessage(isUser: true, text: text))
        }

        let pendingID = UUID()
        isTyping = true
        withAnimation(.easeOut(duration: 0.2)) {
            messages.append(AgentChatMessage(id: pendingID, isUser: false, text: "", isPending: true))
        }

        let intents = AgentAssistantRouter.resolveAll(text)
        let rawReply = tools.runAll(intents)
        let bubbled = chatifyReply(rawReply, intents: intents)
        let followUps = suggestedFollowUps(for: intents)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                if let index = messages.firstIndex(where: { $0.id == pendingID }) {
                    messages[index] = AgentChatMessage(
                        id: pendingID,
                        isUser: false,
                        text: bubbled,
                        isPending: false,
                        followUps: followUps
                    )
                } else {
                    messages.append(AgentChatMessage(isUser: false, text: bubbled, followUps: followUps))
                }
                isTyping = false
            }
        }
    }

    private func chatifyReply(_ raw: String, intents: [AgentAssistantIntent]) -> String {
        if intents.isEmpty {
            return "这句话我还没学会。可以点下面的建议，或者说「你能做什么」。"
        }
        let openers = [
            "好的：",
            "收到：",
            "结果：",
        ]
        let opener = openers[abs(raw.hashValue) % openers.count]
        if intents == [.help] {
            return raw
        }
        if intents.count == 1, intents[0] == .status {
            return "当前联动：\n\n\(raw)"
        }
        return "\(opener)\n\n\(raw)"
    }

    private func suggestedFollowUps(for intents: [AgentAssistantIntent]) -> [String] {
        if intents.isEmpty {
            return ["你能做什么", "一键启用联动", "打开联动页"]
        }
        if intents.contains(.help) {
            return ["一键启用联动", "帮我查一下联动状态", "把蓝牙交给 Agent"]
        }
        if intents.contains(.enableLinkage) || intents.contains(.startAgent) {
            return ["帮我查一下联动状态", "装一下 Cursor 的 hook", "打开联动页"]
        }
        if intents.contains(.status) {
            var tips = ["打开联动页"]
            if !isLinkageReady {
                tips.insert("一键启用联动", at: 0)
            } else if agentManager.bluetoothConnectionOwner != .agentDaemon {
                tips.insert("把蓝牙交给 Agent", at: 0)
            } else {
                tips.insert("打开我的设备", at: 0)
            }
            return Array(tips.prefix(3))
        }
        if intents.contains(.giveBluetoothToAgent) {
            return ["帮我查一下联动状态", "打开联动页", "打开我的设备"]
        }
        if intents.contains(.installCursorHook) || intents.contains(.installClaudeHook) {
            return ["帮我查一下联动状态", "把蓝牙交给 Agent"]
        }
        if intents.contains(.openApproveKey) || intents.contains(.openVoiceKey) || intents.contains(.openHardwareMode) {
            return ["帮我查一下联动状态", "把蓝牙交回 Studio"]
        }
        return ["帮我查一下联动状态", "打开联动页"]
    }
}

private struct AgentTypingDotBounce: ViewModifier {
    let index: Int
    @State private var up = false

    func body(content: Content) -> some View {
        content
            .offset(y: up ? -3 : 2)
            .animation(
                .easeInOut(duration: 0.38)
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.12),
                value: up
            )
            .onAppear { up = true }
    }
}

/// 助手页 Pet 持续动画：空闲跟外观设置，忙碌时更活泼；可点按触发轻弹。
private enum AgentPetLiveStyle {
    case idleBreathe
    case bounce
    case blink
    case busy

    init(from style: VibeBarPetAnimationStyle) {
        switch style {
        case .none, .breathe: self = .idleBreathe
        case .bounce: self = .bounce
        case .blink: self = .blink
        }
    }
}

private struct AgentPetLiveMark: View {
    let glyph: String
    let tint: Color
    let style: AgentPetLiveStyle
    let period: TimeInterval
    var size: CGFloat = 56
    var glyphSize: CGFloat = 28
    var cornerRadius: CGFloat = 16
    var isCircle: Bool = false
    var onTap: (() -> Void)? = nil

    @State private var tapScale: CGFloat = 1

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.45)) {
                tapScale = 1.14
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) {
                    tapScale = 1
                }
            }
            onTap?()
        } label: {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let p = max(0.45, period)
                let phase = (sin(t * (.pi * 2) / p) + 1) / 2
                let busyBoost = style == .busy ? 0.08 : 0.0

                ZStack {
                    // 底：主题色 + 状态 tint 的柔和渐变
                    petFillShape
                        .fill(
                            LinearGradient(
                                colors: [
                                    tint.opacity(0.22 + 0.10 * phase + busyBoost),
                                    AhakeySettingsTheme.cardBackground.opacity(0.92),
                                    tint.opacity(0.10 + 0.06 * (1 - phase)),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    // 高光斑：随呼吸轻微漂移
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.18 + 0.08 * phase),
                                    tint.opacity(0.06),
                                    Color.clear,
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: size * 0.42
                            )
                        )
                        .frame(width: size * 0.55, height: size * 0.38)
                        .offset(x: -size * 0.12, y: -size * 0.14 - CGFloat(phase) * 1.5)
                        .allowsHitTesting(false)

                    // 外圈：状态色描边，忙碌时略亮
                    petStrokeShape
                        .stroke(
                            tint.opacity(0.28 + 0.22 * phase + busyBoost),
                            lineWidth: style == .busy ? 1.4 : 1
                        )

                    Text(glyph)
                        .font(.system(size: glyphSize))
                        .foregroundStyle(tint)
                        .shadow(color: tint.opacity(0.35 + 0.2 * phase), radius: 4 + 2 * phase, y: 1)
                        .modifier(AgentPetMotion(style: style, phase: phase))
                }
                .frame(width: size, height: size)
                .clipShape(petClipShape)
            }
            .scaleEffect(tapScale)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("设备管家 Pet")
        .help("点一下打个招呼")
    }

    private var petFillShape: AnyShape {
        isCircle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var petStrokeShape: AnyShape {
        petFillShape
    }

    private var petClipShape: AnyShape {
        petFillShape
    }
}

/// 统一圆形 / 圆角矩形，避免 `@ViewBuilder some Shape` 分支问题。
private struct AnyShape: Shape {
    private let pathBuilder: (CGRect) -> Path

    init<S: Shape>(_ shape: S) {
        pathBuilder = { rect in shape.path(in: rect) }
    }

    func path(in rect: CGRect) -> Path {
        pathBuilder(rect)
    }
}

private struct AgentPetMotion: ViewModifier {
    let style: AgentPetLiveStyle
    let phase: Double

    func body(content: Content) -> some View {
        switch style {
        case .idleBreathe:
            content
                .scaleEffect(0.94 + 0.08 * phase)
                .opacity(0.78 + 0.22 * phase)
                .offset(y: -1.2 * phase)
        case .bounce:
            content
                .offset(y: -5 * abs(sin(phase * .pi)))
        case .blink:
            content
                .opacity(phase > 0.82 ? 0.28 : 1.0)
        case .busy:
            content
                .scaleEffect(0.9 + 0.14 * phase)
                .rotationEffect(.degrees((-6 + 12 * phase) * 0.55))
                .offset(y: -2.5 * phase)
                .opacity(0.82 + 0.18 * phase)
        }
    }
}

private struct AgentStatusDotPulse: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = active ? (sin(t * 3.2) + 1) / 2 : 1.0
            content
                .opacity(0.55 + 0.45 * phase)
                .scaleEffect(0.85 + 0.2 * phase)
        }
    }
}
