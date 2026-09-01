import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FirmwareFlasherView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @StateObject private var flasher = AhaKeyFirmwareFlasher()
    @Environment(\.dismiss) private var dismiss
    @State private var acknowledgesDataLoss = false
    @State private var showsFlashConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    firmwareSection
                    preparationSection
                    statusSection
                }
                .padding(24)
            }
            Divider()
            footer
        }
        .frame(width: 720, height: 680)
        .task {
            flasher.loadBundledFirmwareIfNeeded()
        }
        .interactiveDismissDisabled(flasher.phase.isBusy)
        .alert("确认全量烧录", isPresented: $showsFlashConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空并开始烧录", role: .destructive) {
                bleManager.disconnect()
                flasher.startFlashing()
            }
        } message: {
            Text("此操作将清空 AhaKey X1 的 CodeFlash 和全部 DataFlash 配置。确认固件文件及 SHA-256 无误，并确保烧录期间不会拔线或退出 App。")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "memorychip")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("AhaKey X1 固件升级")
                    .font(.title2.weight(.semibold))
                Text("CH582M · USB ISP 全量烧录")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("关闭") { dismiss() }
                .disabled(flasher.phase.isBusy)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var firmwareSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if let firmware = flasher.selectedFirmware {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(firmware.fileName)
                                .font(.system(.body, design: .monospaced).weight(.medium))
                                .textSelection(.enabled)
                            Text("\(firmware.formattedByteCount) · \(firmware.isBundled ? "App 内置版本" : "自定义固件")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label("校验通过", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                    }
                    Text("SHA-256  \(firmware.sha256)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else if flasher.phase == .validating {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("正在检查 Intel HEX 结构和校验和…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("没有可用的固件。请重新安装完整 App，或选择一个 Intel HEX 文件。")
                        .foregroundStyle(.orange)
                }

                HStack(spacing: 10) {
                    Button("选择 HEX…") { chooseFirmware() }
                        .disabled(flasher.phase.isBusy)
                    Button("恢复内置 1.4.6") {
                        acknowledgesDataLoss = false
                        flasher.selectBundledFirmware()
                    }
                    .disabled(flasher.phase.isBusy)
                }
                .buttonStyle(.bordered)
            }
            .padding(4)
        } label: {
            Label("固件文件", systemImage: "doc.badge.gearshape")
        }
    }

    private var preparationSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                instructionRow(1, "拔掉键盘 USB，并关闭键盘电源。")
                instructionRow(2, "将 CN1 的 BOOT（PB22）与 GND 短接。")
                instructionRow(3, "点击开始后，保持短接并插入支持数据传输的 USB 线。")
                instructionRow(4, "App 检测到 CH582 并开始擦除后，可以移除短接。")

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("实体 KEY0 接在 PB0，不是 ROM BOOT 引脚；仅按 KEY0 通常无法进入烧录模式。")
                        .font(.callout)
                }
                .padding(.top, 4)

                Toggle("我已确认目标是 AhaKey X1，并理解烧录会删除设备中的全部配置数据。", isOn: $acknowledgesDataLoss)
                    .toggleStyle(.checkbox)
                    .disabled(flasher.phase.isBusy)
                    .padding(.top, 6)
            }
            .padding(4)
        } label: {
            Label("进入 USB ISP", systemImage: "cable.connector")
        }
    }

    private var statusSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    phaseIcon
                    VStack(alignment: .leading, spacing: 2) {
                        Text(flasher.phase.title)
                            .font(.headline)
                        if case .failed(let message) = flasher.phase {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                            if flasher.hasStartedDestructiveOperation {
                                Text("设备可能已被擦除；请保持 USB ISP 连接，确认固件有效后重新烧录。")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.orange)
                            }
                        } else if flasher.phase == .waitingForDevice {
                            Text("最长等待 60 秒；在检测和确认 CH582 之前不会擦除任何数据。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if flasher.phase.isDestructive {
                            Text("请勿拔线、关闭窗口或退出 App。")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                }

                if flasher.phase.isBusy || flasher.phase == .success {
                    if let progress = flasher.phase.progress {
                        ProgressView(value: progress)
                    } else {
                        ProgressView()
                    }
                }

                if !flasher.logLines.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 3) {
                                ForEach(Array(flasher.logLines.enumerated()), id: \.offset) { index, line in
                                    Text(line)
                                        .font(.system(.caption2, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(index)
                                }
                            }
                            .padding(8)
                        }
                        .frame(height: 125)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .onChange(of: flasher.logLines.count) { count in
                            if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
                        }
                    }
                }
            }
            .padding(4)
        } label: {
            Label("烧录状态", systemImage: "waveform.path.ecg")
        }
    }

    private var footer: some View {
        HStack {
            Text("烧录工具：wchisp 0.3.0 · GPL-2.0")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            if flasher.phase.canCancelSafely {
                Button("取消等待", role: .cancel) { flasher.cancelSafely() }
                    .buttonStyle(.bordered)
            }
            Button("开始等待设备") {
                showsFlashConfirmation = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                !acknowledgesDataLoss
                || flasher.selectedFirmware == nil
                || flasher.phase != .ready
            )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var phaseIcon: some View {
        switch flasher.phase {
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "stop.circle.fill").foregroundStyle(.secondary)
        case .erasingDataFlash, .erasingCodeFlash, .flashing:
            Image(systemName: "bolt.trianglebadge.exclamationmark.fill").foregroundStyle(.orange)
        default:
            Image(systemName: "circle.dotted").foregroundStyle(.blue)
        }
    }

    private func instructionRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
            Text(text)
                .font(.callout)
        }
    }

    private func chooseFirmware() {
        let panel = NSOpenPanel()
        panel.title = "选择 AhaKey X1 Intel HEX 固件"
        panel.message = "App 会先校验每条 Intel HEX 记录及 SHA-256；确认前不会访问设备。"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "hex") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        acknowledgesDataLoss = false
        flasher.selectCustomFirmware(at: url)
    }
}
