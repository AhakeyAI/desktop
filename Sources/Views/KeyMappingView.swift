import SwiftUI

/// 单个键的映射配置
struct KeyConfig: Codable {
    var hidCode: UInt8 = 0
    var description: String = ""

    var displayName: String {
        hidCode == 0 ? "未设置" : HIDUsage.name(for: hidCode)
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
        KeyConfig(hidCode: HIDUsage.capsLock, description: "录音"),
        KeyConfig(hidCode: HIDUsage.enter, description: "Enter"),
        KeyConfig(hidCode: HIDUsage.escape, description: "取消"),
        KeyConfig(hidCode: HIDUsage.enter, description: "Enter"),
    ]
    @State private var showWriteSuccess = false

    private let keyLabels = ["Key 1\n🎤", "Key 2\n✓", "Key 3\n✗", "Key 4\n↵"]

    var body: some View {
        Form {
            // MARK: - 按键选择
            Section("按键映射") {
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
            Section("Key \(selectedKey + 1) 设置") {
                Picker("键码", selection: $keys[selectedKey].hidCode) {
                    Text("未设置").tag(UInt8(0))
                    ForEach(HIDUsage.allOptions, id: \.code) { option in
                        Text("\(option.name)  (\(String(format: "0x%02X", option.code)))")
                            .tag(option.code)
                    }
                }

                LabeledContent("描述") {
                    TextField("显示在键盘 OLED 上", text: $keys[selectedKey].description)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }
            }

            // MARK: - 预设方案
            Section {
                HStack {
                    Button("EchoWrite 推荐") {
                        applyEchoWritePreset()
                    }
                    .buttonStyle(.bordered)
                    .help("Key1=F18(EchoWrite) Key2=Enter Key3=Escape Key4=Enter")

                    Button("恢复默认") {
                        applyDefaultPreset()
                    }
                    .buttonStyle(.bordered)
                    .help("恢复出厂默认键位")
                }
            } header: {
                Text("预设方案")
            } footer: {
                Text("EchoWrite 推荐：Key1 发送 F18 触发随声写录音，Key2/4 确认，Key3 取消。")
                    .font(.caption)
            }

            // MARK: - 写入设备
            if bleManager.isConnected {
                Section {
                    HStack {
                        Button("应用全部键位到设备") {
                            writeAllKeys()
                        }
                        .buttonStyle(.borderedProminent)

                        if showWriteSuccess {
                            Label("已发送", systemImage: "checkmark.circle.fill")
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
                        Text("请先连接 AhaKey 设备")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .formStyle(.grouped)
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
            try? await Task.sleep(for: .seconds(3))
            showWriteSuccess = false
        }
    }
}
