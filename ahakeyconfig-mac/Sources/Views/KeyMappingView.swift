import SwiftUI

/// 单个键的映射配置
struct KeyConfig: Codable {
    var hidCode: UInt8 = 0
    var description: String = ""

    var displayName: String {
        hidCode == 0 ? NSLocalizedString("未设置", comment: "") : HIDUsage.name(for: hidCode)
    }
}

/// 键位配置持久化
enum KeyConfigStore {
    private static let key = "keyMappingConfig"

    static func save(_ keys: [KeyConfig]) {
        if let data = try? JSONEncoder().encode(keys) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> [KeyConfig]? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let configs = try? JSONDecoder().decode([KeyConfig].self, from: data),
              configs.count == 4 else { return nil }
        return configs
    }
}

struct KeyMappingView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager

    @State private var selectedKey = 0
    @State private var keys: [KeyConfig] = KeyConfigStore.load() ?? [
        KeyConfig(hidCode: HIDUsage.capsLock, description: NSLocalizedString("录音", comment: "")),
        KeyConfig(hidCode: HIDUsage.enter, description: "Enter"),
        KeyConfig(hidCode: HIDUsage.escape, description: NSLocalizedString("取消", comment: "")),
        KeyConfig(hidCode: HIDUsage.backspace, description: "Backspace"),
    ]
    @State private var showWriteSuccess = false

    private let keyLabels = ["Key 1\n🎤", "Key 2\n✓", "Key 3\n✗", "Key 4\n⌫"]

    var body: some View {
        Form {
            // MARK: - 按键选择
            Section(NSLocalizedString("按键映射", comment: "")) {
                HStack(spacing: 12) {
                    ForEach(0..<4) { index in
                        Button {
                            selectedKey = index
                        } label: {
                            VStack(spacing: 4) {
                                Text(keyLabels[index])
                                    .font(.system(.body, design: .rounded))
                                    .multilineTextAlignment(.center)
                                Text(keys[index].displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedKey == index
                                          ? Color.accentColor.opacity(0.15)
                                          : Color.primary.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(selectedKey == index
                                                  ? Color.accentColor
                                                  : Color.primary.opacity(0.1), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // MARK: - 编辑选中键
            Section(String(format: NSLocalizedString("Key %d 设置", comment: ""), selectedKey + 1)) {
                Picker(NSLocalizedString("键码", comment: ""), selection: $keys[selectedKey].hidCode) {
                    Text(NSLocalizedString("未设置", comment: "")).tag(UInt8(0))
                    ForEach(HIDUsage.allOptions, id: \.code) { option in
                        Text("\(option.name)  (\(String(format: "0x%02X", option.code)))")
                            .tag(option.code)
                    }
                }

                CompatLabeledContent(NSLocalizedString("描述", comment: "")) {
                    TextField(NSLocalizedString("显示在键盘 LCD 上", comment: ""), text: $keys[selectedKey].description)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }
            }

            // MARK: - 预设方案
            Section {
                HStack {
                    Button(NSLocalizedString("EchoWrite 推荐", comment: "")) {
                        applyEchoWritePreset()
                    }
                    .buttonStyle(.bordered)
                    .help("Key1=F18(EchoWrite) Key2=Enter Key3=Escape Key4=Enter")

                    Button(NSLocalizedString("恢复默认", comment: "")) {
                        applyDefaultPreset()
                    }
                    .buttonStyle(.bordered)
                    .help(NSLocalizedString("恢复出厂默认键位", comment: ""))
                }
            } header: {
                Text(NSLocalizedString("预设方案", comment: ""))
            } footer: {
                Text(NSLocalizedString("EchoWrite 推荐：Key1 发送 F18 触发随声写录音，Key2/4 确认，Key3 取消。", comment: ""))
                    .font(.caption)
            }

            // MARK: - 写入设备
            if bleManager.isConnected {
                Section {
                    HStack {
                        Button(NSLocalizedString("应用全部键位到设备", comment: "")) {
                            writeAllKeys()
                        }
                        .buttonStyle(.borderedProminent)

                        if showWriteSuccess {
                            Label(NSLocalizedString("已发送", comment: ""), systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }
                }
            } else {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(NSLocalizedString("请先连接 AhaKey 设备", comment: ""))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }

    }

    // MARK: - Actions

    private func applyEchoWritePreset() {
        keys = [
            KeyConfig(hidCode: HIDUsage.f18, description: "EchoWrite"),
            KeyConfig(hidCode: HIDUsage.enter, description: "Enter"),
            KeyConfig(hidCode: HIDUsage.escape, description: "Cancel"),
            KeyConfig(hidCode: HIDUsage.enter, description: "Enter"),
        ]
        KeyConfigStore.save(keys)
    }

    private func applyDefaultPreset() {
        keys = [
            KeyConfig(hidCode: HIDUsage.capsLock, description: "CapsLock"),
            KeyConfig(hidCode: HIDUsage.enter, description: "Enter"),
            KeyConfig(hidCode: HIDUsage.escape, description: "Escape"),
            KeyConfig(hidCode: HIDUsage.enter, description: "Enter"),
        ]
        KeyConfigStore.save(keys)
    }

    private func writeAllKeys() {
        for (index, key) in keys.enumerated() {
            guard key.hidCode != 0 else { continue }
            let keyIndex = UInt8(index)
            bleManager.setKeyMapping(keyIndex: keyIndex, hidCodes: [key.hidCode])
            if !key.description.isEmpty {
                bleManager.setKeyDescription(keyIndex: keyIndex, text: key.description)
            }
        }
        // 写入完毕后保存到 Flash + 本地持久化
        bleManager.saveConfig()
        KeyConfigStore.save(keys)
        showWriteSuccess = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Double(3) * 1_000_000_000))
            showWriteSuccess = false
        }
    }
}
