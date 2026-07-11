import SwiftUI

private struct CanvasKeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.12, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

struct AhaKeyIslandKeyboardCanvasView: View {
    let modeDraft: AhaKeyModeDraft
    let selectedPart: AhaKeyStudioPart
    let lightBarPreview: LightBarPreviewState
    let switchTitle: String
    let dirtyParts: Set<AhaKeyStudioPart>
    var deviceGeneration: DeviceGeneration = .x1
    var magneticModuleState: MagneticModuleState = .empty
    var oceanLightConfig: OceanLightConfig = .default
    var workMode: Int = 0
    let onSelect: (AhaKeyStudioPart) -> Void
    let onModeSwitch: () -> Void
    var onKeySimulate: ((AhaKeyKeyRole) -> Void)? = nil
    var onSwitchToggle: (() -> Void)? = nil
    var liveLightMode: Int? = nil
    var liveIDEStateValue: Int? = nil
    var switchState: Int = 1   // 0=auto, 1=manual; firmware uses for color/effect overrides
    /// 0x83 查询出的当前 mode flash 帧数：nil=尚未查询/未连接；0=用户没上传；>0=已上传 N 帧
    var keyboardPictureFrameCount: Int? = nil
    var appearance: KeyboardCanvasAppearance = .studioLight

    @State private var modeSwitchPressed = false
    @State private var leverPressed = false

    private var theme: KeyboardCanvasTheme { appearance.theme }
    private var layout: KeyboardCanvasLayout { appearance.layout }

    private var isGen2: Bool { deviceGeneration == .gen2 }

    var body: some View {
        GeometryReader { proxy in
            let drawingWidth = min(proxy.size.width, proxy.size.height * layout.aspectRatio)
            let drawingHeight = drawingWidth / layout.aspectRatio

            ZStack {
                keyboardFrame(width: drawingWidth, height: drawingHeight)
            }
            .frame(width: drawingWidth, height: drawingHeight)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    @ViewBuilder
    private func keyboardFrame(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(theme.chassisFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(theme.chassisStroke, lineWidth: 1.2)
                )
                .shadow(color: theme.chassisShadowColor, radius: theme.chassisShadowRadius, y: theme.chassisShadowY)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(theme.innerBezelStroke, lineWidth: 1)
                .padding(12)

            // 螺丝挪到真正的"边角内侧" + 缩小直径 4.8 → 3.6：
            // 旧位置 (8,8)/(8,46) 会被按键灰底矩形和灯条/Key1 边线擦边或交叠。
            // 新位置每颗距离灯条/按键灰底/Key 边都留出 ≥ 3 个基线单位。
            ForEach(Array(layout.cornerScrewPoints.enumerated()), id: \.offset) { _, point in
                Circle()
                    .stroke(theme.screwStroke, lineWidth: 1.2)
                    .background(Circle().fill(theme.screwFill))
                    .frame(width: scaled(3.6, in: width), height: scaled(3.6, in: width))
                    .position(position(point.x, point.y, width: width, height: height))
            }

            // 左侧挂绳孔（Gen2 无此开孔）
            if !isGen2 {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(theme.chassisStroke, lineWidth: 1)
                    .frame(width: scaled(4.2, in: width), height: scaled(12, in: width))
                    .position(position(3.8, 28, width: width, height: height))
            }

            // 按键灰底：略收一点尺寸，使它显著低于灯条选中态阴影的影响范围（≥ 5 个基线单位）
            Group {
                if theme.usesNeumorphicKeyCaps {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .neumorphicRecessed(
                            cornerRadius: 16,
                            fill: theme.keyTrackFill,
                            stroke: theme.keyTrackStroke
                        )
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(theme.keyTrackFill)
                }
            }
            .frame(
                width: scaled(isGen2 ? layout.keyTrackWidthGen2 : layout.keyTrackWidthX1, in: width),
                height: scaled(21, in: width)
            )
            .position(
                position(
                    isGen2 ? layout.keyTrackCenterGen2 : layout.keyTrackCenterX1,
                    38.5,
                    width: width,
                    height: height
                )
            )

            ledBarButton(width: width, height: height)
            oledButton(width: width, height: height)
            keyButton(for: .voice, width: width, height: height)
            keyButton(for: .approve, width: width, height: height)
            keyButton(for: .reject, width: width, height: height)
            keyButton(for: .submit, width: width, height: height)

            if isGen2 {
                magneticBaseButton(width: width, height: height)
            } else {
                modeSwitchKey(width: width, height: height)
                switchButton(width: width, height: height)
            }
        }
    }

    // 固件 ws2812_mode_e (psk_ws2812.h) → Swift 灯效样式
    private func lightModeToEffect(_ mode: Int) -> LightEffectStyle {
        switch mode {
        case 1: return .singleMove
        case 2: return .rainbowMove
        case 3: return .rainbowWave
        case 4: return .rainbowWaveSlow
        case 5: return .breathing
        case 6: return .middleLight
        default: return .off
        }
    }

    private static let firmwareRed = Color(red: 240 / 255, green: 32 / 255, blue: 41 / 255)
    private static let firmwareBlue = Color(red: 32 / 255, green: 80 / 255, blue: 255 / 255)

    /// 1:1 还原固件 update_claude_ws2812() 的灯效/颜色决策（CH582m main.c:458-500）。
    /// 仅 mode_data==0 时固件会按 claude_state 切灯效；其他 mode 固件提前 return，
    /// 灯条停在上一次设定的状态，所以我们这里返回 OFF 作为"没有运行时灯效"的真实表达。
    private func firmwareLEDState(ideState: IDEState?, modeData: Int, switchState: Int) -> (LightEffectStyle, Color) {
        guard modeData == 0, let s = ideState else {
            return (.off, Self.firmwareRed)
        }
        var effect: LightEffectStyle
        var color: Color = Self.firmwareRed
        switch s {
        case .sessionStart, .stop:
            effect = .middleLight
        case .postToolUse, .userPromptSubmit:
            effect = .singleMove
        case .permissionRequest:
            effect = .breathing
        case .preToolUse:
            effect = .singleMove
            color = Self.firmwareBlue
        case .sessionEnd:
            effect = .off
        case .notification, .taskCompleted:
            // 固件 switch 未处理这两个 state，灯条保持上一次状态（这里以 OFF 表示无新效果）
            return (.off, Self.firmwareRed)
        }
        if switchState == 0 { // auto: 固件覆盖部分 state 为彩虹效果
            switch s {
            case .postToolUse, .userPromptSubmit:
                effect = .rainbowMove
            case .permissionRequest, .preToolUse:
                effect = .rainbowWave
            default:
                break
            }
        }
        return (effect, color)
    }

    @ViewBuilder
    private func ledBarButton(width: CGFloat, height: CGFloat) -> some View {
        let part = AhaKeyStudioPart.lightBar
        let rect = frame(
            isGen2 ? layout.lightBarXGen2 : layout.lightBarX1,
            layout.lightBarY,
            isGen2 ? layout.lightBarWGen2 : layout.lightBarWX1,
            isGen2 ? 10.8 : 8.6,
            width: width,
            height: height
        )

        if isGen2 {
            Button {
                onSelect(part)
            } label: {
                OceanLightPreviewView(config: oceanLightConfig, rowCount: 3, ledsPerRow: 14)
                    .frame(width: rect.width, height: rect.height)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(theme.ledSlotFill)
                    )
                    .modifier(hotspotChrome(part: part))
            }
            .buttonStyle(.plain)
            .position(x: rect.midX, y: rect.midY)
        } else {
            x1LedBarButton(part: part, rect: rect, width: width, height: height)
        }
    }

    private func x1LedBarButton(part: AhaKeyStudioPart, rect: CGRect, width: CGFloat, height: CGFloat) -> some View {
        let modeData = modeDraft.mode.rawValue
        let effect: LightEffectStyle
        let baseColor: Color
        if let live = liveLightMode {
            // BLE 连接且 mode tab 与物理 workMode 一致：直接信任固件回报的 ws2812_mode + claude_state
            effect = lightModeToEffect(live)
            let liveIDE: IDEState? = liveIDEStateValue.flatMap { IDEState(rawValue: UInt8($0)) }
            // 颜色：仅 preToolUse + manual 是蓝，其他均红（与固件 ws2812_single_color 设定一致）
            if let s = liveIDE, s == .preToolUse, switchState != 0 {
                baseColor = Self.firmwareBlue
            } else {
                baseColor = Self.firmwareRed
            }
        } else {
            // 离线/查看非物理档位：按固件逻辑模拟 update_claude_ws2812()
            let previewIDE = lightBarPreview.ideState
            (effect, baseColor) = firmwareLEDState(ideState: previewIDE, modeData: modeData, switchState: switchState)
        }
        return Button {
            onSelect(part)
        } label: {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let colors = ledColors(effect: effect, time: context.date.timeIntervalSince1970, count: 10, baseColor: baseColor)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(theme.ledSlotFill)
                    HStack(spacing: rect.width * 0.026) {
                        ForEach(0..<10, id: \.self) { index in
                            Capsule()
                                .fill(colors[index])
                                .frame(width: rect.width * 0.072, height: rect.height * 0.42)
                                .shadow(color: colors[index].opacity(0.65), radius: 2.5)
                        }
                    }
                    .padding(.horizontal, rect.width * 0.04)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(width: rect.width, height: rect.height)
            .modifier(hotspotChrome(part: part))
        }
        .buttonStyle(.plain)
        .position(x: rect.midX, y: rect.midY)
    }

    private func oledButton(width: CGFloat, height: CGFloat) -> some View {
        let part = AhaKeyStudioPart.oledDisplay
        let rect = frame(layout.oledX, layout.oledY, layout.oledW, 13.4, width: width, height: height)
        return Button {
            onSelect(part)
        } label: {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.92))
                    oledInnerContent(rect: rect)
                }
                // 右上角徽章：反映键盘 flash 真实状态
                pictureStateBadge(rect: rect)
            }
            .frame(width: rect.width, height: rect.height)
            .modifier(hotspotChrome(part: part))
        }
        .buttonStyle(.plain)
        .position(x: rect.midX, y: rect.midY)
    }

    @ViewBuilder
    private func pictureStateBadge(rect: CGRect) -> some View {
        if let count = keyboardPictureFrameCount {
            let isUploaded = count > 0
            let label = isUploaded ? "✓ 已上传 \(count) 帧" : "未上传"
            Text(label)
                .font(.system(size: max(rect.height * 0.11, 8), weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, rect.width * 0.04)
                .padding(.vertical, rect.height * 0.02)
                .background(
                    Capsule()
                        .fill(isUploaded ? Color.green.opacity(0.85) : Color.gray.opacity(0.85))
                )
                .padding(rect.width * 0.025)
        }
    }

    /// 真实 OLED 是 160×80（2:1）。在 slot 中央用一个 2:1 的"屏幕区"渲染内容，
    /// 周围留键盘黑壳作为外框；图片 / 占位都在屏幕区内 .fit，不会撑出范围、不会被裁切。
    private func screenInnerSize(for rect: CGRect) -> CGSize {
        let screenAspect: CGFloat = 2.0
        if rect.width / rect.height >= screenAspect {
            let h = rect.height * 0.86
            return CGSize(width: h * screenAspect, height: h)
        } else {
            let w = rect.width * 0.86
            return CGSize(width: w, height: w / screenAspect)
        }
    }

    private func oledInnerContent(rect: CGRect) -> some View {
        let size = screenInnerSize(for: rect)
        return ZStack {
            Color.clear
            screenBody(screenWidth: size.width, screenHeight: size.height)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func screenBody(screenWidth: CGFloat, screenHeight: CGFloat) -> some View {
        if let gifPath = modeDraft.oled.localAssetPath {
            PixelArtAnimatedGIFView(
                path: gifPath,
                fps: modeDraft.oled.framesPerSecond,
                targetWidth: 160,
                targetHeight: 80,
                blockSize: isGen2 ? 3 : PixelArtProcessor.canvasBlockSize
            )
            .id(gifPath)
        } else {
            PixelArtStatusScreenView(
                mode: modeDraft.mode,
                screenWidth: screenWidth,
                screenHeight: screenHeight
            )
        }
    }

    private func hotspotChrome(part: AhaKeyStudioPart, cornerRadius: CGFloat = 14) -> IslandHotspotChrome {
        IslandHotspotChrome(
            part: part,
            selectedPart: selectedPart,
            dirtyParts: dirtyParts,
            theme: theme,
            cornerRadius: cornerRadius
        )
    }

    @ViewBuilder
    private func keyCapSurface(cornerRadius: CGFloat) -> some View {
        if theme.usesNeumorphicKeyCaps {
            Color.clear
                .neumorphicRecessed(
                    cornerRadius: cornerRadius,
                    fill: theme.keyCapBaseColor,
                    stroke: theme.keyTrackStroke
                )
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(theme.keyCapFill)
                .shadow(color: theme.keyCapShadowColor, radius: theme.keyCapShadowRadius, y: theme.keyCapShadowY)
        }
    }

    private func keyButton(for role: AhaKeyKeyRole, width: CGFloat, height: CGFloat) -> some View {
        let part = role.part
        let keyDraft = modeDraft.key(for: role)
        let specs: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)
        switch role {
        case .voice:
            specs = isGen2 ? (9.5, 29.2, 15.0, 16.8) : (10.2, 29.2, 16.2, 16.8)
        case .approve:
            specs = isGen2 ? (25.5, 29.2, 15.0, 16.8) : (27.2, 29.2, 16.2, 16.8)
        case .reject:
            specs = isGen2 ? (41.5, 29.2, 15.0, 16.8) : (44.2, 29.2, 16.2, 16.8)
        case .submit:
            specs = isGen2 ? (57.5, 29.2, 15.0, 16.8) : (61.2, 29.2, 16.2, 16.8)
        }
        let rect = frame(specs.x, specs.y, specs.w, specs.h, width: width, height: height)
        return Button {
            onSelect(part)
            onKeySimulate?(role)
        } label: {
            VStack(spacing: rect.height * 0.07) {
                ZStack {
                    keyCapSurface(cornerRadius: rect.width * 0.18)
                    keyCapIcon(for: role, size: rect.height * 0.24)
                        .fixedSize()
                }
                .frame(width: rect.width * 0.8, height: rect.height * 0.76)

                Text(keyDraft.description.isEmpty ? keyDraft.displaySummary : keyDraft.description)
                    .font(.system(size: rect.height * 0.11, weight: .medium))
                    .foregroundStyle(theme.keyLabelColor)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .frame(width: rect.width, height: rect.height)
            .modifier(hotspotChrome(part: part))
        }
        .buttonStyle(CanvasKeyButtonStyle())
        .position(x: rect.midX, y: rect.midY)
    }

    @ViewBuilder
    private func keyCapIcon(for role: AhaKeyKeyRole, size: CGFloat) -> some View {
        CanvasKeyRoleIcon(role: role, color: theme.keyIconColor, size: size)
    }

    private func modeSwitchKey(width: CGFloat, height: CGFloat) -> some View {
        let rect = frame(78.9, 40.9, 8.0, 10.2, width: width, height: height)
        return Button {
            onModeSwitch()
        } label: {
            VStack(spacing: rect.height * 0.08) {
                ZStack {
                    keyCapSurface(cornerRadius: rect.width * 0.2)

                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: rect.height * 0.18, weight: .semibold))
                        .foregroundStyle(theme.accentColor.opacity(0.85))
                }
                .frame(width: rect.width * 0.78, height: rect.height * 0.5)

                Text("Mode")
                    .font(.system(size: rect.height * 0.1, weight: .medium))
                    .foregroundStyle(theme.secondaryLabelColor)
                    .lineLimit(1)
            }
            .frame(width: rect.width, height: rect.height)
        }
        .buttonStyle(CanvasKeyButtonStyle())
        .position(x: rect.midX, y: rect.midY)
        .help("点击切换 Mode（模拟实体键）")
    }

    private func magneticBaseButton(width: CGFloat, height: CGFloat) -> some View {
        let part = AhaKeyStudioPart.magneticPort
        // 圆角正方形磁吸槽，吸附模块后与单键同高、控件更大
        let side = layout.magneticSide
        let rect = frame(layout.magneticPortX, 27.8, side, side, width: width, height: height)
        let baseSize = min(rect.width, rect.height)

        return Button {
            onSelect(part)
        } label: {
            VStack(spacing: rect.height * 0.05) {
                MagneticBaseView(moduleState: magneticModuleState)
                    .frame(width: baseSize, height: baseSize)
                    .modifier(
                        hotspotChrome(part: part, cornerRadius: baseSize * 0.2)
                    )

                Text(magneticModuleState.isConnected ? magneticModuleState.attachedType.title : "磁吸底座")
                    .font(.system(size: max(rect.height * 0.11, 9), weight: .semibold))
                    .foregroundStyle(
                        magneticModuleState.isConnected
                            ? theme.keyLabelColor
                            : theme.secondaryLabelColor
                    )
                    .lineLimit(1)
            }
            .frame(width: rect.width, height: rect.height)
        }
        .buttonStyle(CanvasKeyButtonStyle())
        .position(x: rect.midX, y: rect.midY)
        .zIndex(2)
    }

    private func switchButton(width: CGFloat, height: CGFloat) -> some View {
        let part = AhaKeyStudioPart.toggleSwitch
        let rect = frame(87.8, 35.6, 6.8, 10.6, width: width, height: height)
        return Button {
            onSelect(part)
            // 物理拨杆损坏的用户靠这个：点击即翻转 auto/manual。
            // - 已 patch 固件：agent 通过 0x91 BLE 命令真改键盘 sw_state，灯效也会跟着变
            // - 老固件：只在 agent 软覆盖层生效（hook 自动批准走新值），键盘灯效不会变
            onSwitchToggle?()
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: rect.width * 0.18, style: .continuous)
                        .fill(Color.black.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: rect.width * 0.18, style: .continuous)
                                .stroke(Color.black.opacity(0.12), lineWidth: 1)
                        )
                    Capsule()
                        .fill(Color.white)
                        .frame(width: rect.width * 0.36, height: rect.height * 0.65)
                        .overlay(Circle().fill(Color.gray.opacity(0.24)).frame(width: rect.width * 0.28, height: rect.width * 0.28))
                        .offset(y: switchTitle == "自动批准" ? -rect.height * 0.08 : rect.height * 0.12)
                }
                .frame(width: rect.width * 0.58, height: rect.height * 0.78)

                Text(switchTitle)
                    .font(.system(size: rect.height * 0.12, weight: .medium))
                    .foregroundStyle(theme.secondaryLabelColor)
                    .lineLimit(1)
            }
            .frame(width: rect.width, height: rect.height)
            .modifier(hotspotChrome(part: part))
        }
        .buttonStyle(CanvasKeyButtonStyle())
        .position(x: rect.midX, y: rect.midY)
    }

    private func frame(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(
            x: x / layout.baseWidth * width,
            y: y / layout.baseHeight * height,
            width: w / layout.baseWidth * width,
            height: h / layout.baseHeight * height
        )
    }

    private func position(_ x: CGFloat, _ y: CGFloat, width: CGFloat, height: CGFloat) -> CGPoint {
        CGPoint(x: x / layout.baseWidth * width, y: y / layout.baseHeight * height)
    }

    private func scaled(_ value: CGFloat, in width: CGFloat) -> CGFloat {
        value / layout.baseWidth * width
    }

    private func ledColors(effect: LightEffectStyle, time: TimeInterval, count: Int,
                           baseColor: Color = Self.firmwareRed) -> [Color] {
        switch effect {
        case .off:
            return Array(repeating: Color.gray.opacity(0.15), count: count)
        case .middleLight:
            let center = Double(count - 1) / 2.0
            return (0..<count).map { i in
                let dist = abs(Double(i) - center) / center
                let pulse = (sin(time * 1.5) + 1.0) / 2.0 * 0.15
                return baseColor.opacity(0.2 + (1.0 - dist) * 0.65 + pulse)
            }
        case .singleMove:
            let period = 2.4
            let t = time.truncatingRemainder(dividingBy: period) / period
            let pos = t < 0.5 ? t * 2.0 * Double(count - 1) : (1.0 - (t - 0.5) * 2.0) * Double(count - 1)
            return (0..<count).map { i in
                let dist = abs(Double(i) - pos)
                let brightness = max(0.0, 1.0 - dist * 0.75)
                return baseColor.opacity(0.12 + brightness * 0.82)
            }
        case .breathing:
            let breath = (sin(time * Double.pi * 0.9) + 1.0) / 2.0
            return Array(repeating: baseColor.opacity(0.12 + breath * 0.78), count: count)
        case .rainbowMove:
            let period = 2.4
            let t = time.truncatingRemainder(dividingBy: period) / period
            let pos = t < 0.5 ? t * 2.0 * Double(count - 1) : (1.0 - (t - 0.5) * 2.0) * Double(count - 1)
            return (0..<count).map { i in
                let dist = abs(Double(i) - pos)
                let brightness = max(0.0, 1.0 - dist * 0.7)
                let hue = (Double(i) / Double(count) + time * 0.25).truncatingRemainder(dividingBy: 1.0)
                return Color(hue: hue, saturation: 1.0, brightness: 0.15 + brightness * 0.85)
            }
        case .rainbowWave:
            return (0..<count).map { i in
                let hue = (Double(i) / Double(count) + time * 0.4).truncatingRemainder(dividingBy: 1.0)
                return Color(hue: hue, saturation: 1.0, brightness: 0.9)
            }
        case .rainbowWaveSlow:
            return (0..<count).map { i in
                let hue = (Double(i) / Double(count) + time * 0.14).truncatingRemainder(dividingBy: 1.0)
                return Color(hue: hue, saturation: 1.0, brightness: 0.9)
            }
        case .typingRipple:
            let center = Double(count - 1) / 2.0
            let phase = time.truncatingRemainder(dividingBy: 1.6) / 1.6
            let rippleRadius = phase * center * 1.8
            return (0..<count).map { i in
                let dist = abs(Double(i) - center)
                let wave = max(0, 1.0 - abs(dist - rippleRadius) * 0.8)
                return baseColor.opacity(0.1 + wave * 0.85)
            }
        case .comet:
            let period = 1.8
            let t = time.truncatingRemainder(dividingBy: period) / period
            let pos = t * Double(count + 3) - 1.5
            return (0..<count).map { i in
                let dist = Double(i) - pos
                let tail = dist >= 0 ? 0.0 : max(0, 1.0 + dist * 0.25)
                let head = dist >= 0 && dist < 1.5 ? max(0, 1.0 - dist * 0.65) : 0.0
                return baseColor.opacity(0.08 + max(tail, head) * 0.88)
            }
        case .scanBar:
            let period = 2.0
            let t = time.truncatingRemainder(dividingBy: period) / period
            let pos = t < 0.5 ? t * 2.0 * Double(count - 1) : (1.0 - (t - 0.5) * 2.0) * Double(count - 1)
            return (0..<count).map { i in
                let dist = abs(Double(i) - pos)
                let brightness = dist < 1.5 ? 1.0 - dist * 0.3 : 0.0
                return baseColor.opacity(0.08 + max(0, brightness) * 0.88)
            }
        case .pulseCenter:
            let center = Double(count - 1) / 2.0
            let pulse = (sin(time * Double.pi * 2.5) + 1.0) / 2.0
            return (0..<count).map { i in
                let dist = abs(Double(i) - center) / center
                let intensity = pulse * max(0, 1.0 - dist * 0.8)
                return baseColor.opacity(0.08 + intensity * 0.88)
            }
        case .warningBlink:
            let blink = sin(time * Double.pi * 4.0) > 0 ? 0.9 : 0.1
            let orange = Color(red: 1.0, green: 0.6, blue: 0.0)
            return Array(repeating: orange.opacity(blink), count: count)
        case .successSweep:
            let green = Color(red: 0.1, green: 0.85, blue: 0.3)
            let progress = time.truncatingRemainder(dividingBy: 2.0) / 2.0
            let fillPos = progress * Double(count + 2) - 1
            return (0..<count).map { i in
                let lit = Double(i) <= fillPos ? 1.0 : 0.0
                return green.opacity(0.08 + lit * 0.88)
            }
        case .blueThinking:
            let blue = Color(red: 0.2, green: 0.5, blue: 1.0)
            return (0..<count).map { i in
                let wave = (sin(time * Double.pi * 0.8 + Double(i) * 0.6) + 1.0) / 2.0
                return blue.opacity(0.15 + wave * 0.75)
            }
        case .lowBattery:
            let red = Color(red: 1.0, green: 0.15, blue: 0.1)
            let pulse = (sin(time * Double.pi * 0.5) + 1.0) / 2.0
            return Array(repeating: red.opacity(0.1 + pulse * 0.6), count: count)
        case .chargingFlow:
            let green = Color(red: 0.1, green: 0.85, blue: 0.3)
            let period = 3.0
            let progress = time.truncatingRemainder(dividingBy: period) / period
            let fillPos = progress * Double(count)
            return (0..<count).map { i in
                let lit = Double(i) < fillPos ? 0.85 : 0.08
                return green.opacity(lit)
            }
        case .approvalWait:
            let amber = Color(red: 1.0, green: 0.75, blue: 0.2)
            let center = Double(count - 1) / 2.0
            let breath = (sin(time * Double.pi * 1.2) + 1.0) / 2.0
            let centerBlink = sin(time * Double.pi * 3.0) > 0 ? 1.0 : 0.4
            return (0..<count).map { i in
                let dist = abs(Double(i) - center) / center
                let isCenter = dist < 0.2
                let intensity = isCenter ? centerBlink : breath * (1.0 - dist * 0.5)
                return amber.opacity(0.1 + intensity * 0.8)
            }
        }
    }

}
private struct IslandHotspotChrome: ViewModifier {
    let part: AhaKeyStudioPart
    let selectedPart: AhaKeyStudioPart
    let dirtyParts: Set<AhaKeyStudioPart>
    var theme: KeyboardCanvasTheme = .studioLight
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        let isSelected = selectedPart == part
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? theme.hotspotSelectedStroke : theme.hotspotIdleStroke,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .overlay(alignment: .topTrailing) {
                if dirtyParts.contains(part) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                        .padding(8)
                }
            }
            // 选中态阴影从 10 收到 6，减少向邻近元件溢出的发光半径
            .shadow(color: isSelected ? theme.hotspotSelectedGlow : .clear, radius: 6)
    }
}