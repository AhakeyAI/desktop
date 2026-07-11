import SwiftUI

/// 语音输入顶部分段：历史记录 / 词典 / 通用设置。
struct AhaKeyVoiceInputSectionPicker: View {
    @Binding var selection: AhaKeyVoiceInputConfigSection

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AhaKeyVoiceInputConfigSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    VStack(spacing: 3) {
                        Text(section.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selection == section ? AhakeySettingsTheme.primaryText : AhakeySettingsTheme.secondaryText)
                        Text(section.subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(selection == section ? AhakeySettingsTheme.accentBlue : AhakeySettingsTheme.tertiaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selection == section ? AhakeySettingsTheme.controlFill : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AhakeySettingsTheme.cardBackground)
        )
    }
}
