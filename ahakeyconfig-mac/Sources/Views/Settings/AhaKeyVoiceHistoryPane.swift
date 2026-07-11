import AppKit
import SwiftUI

struct AhaKeyVoiceHistoryPane: View {
    @ObservedObject private var store = VoiceInputStore.shared
    @ObservedObject private var nativeSpeech = NativeSpeechTranscriptionService.shared

    private var groups: [(day: Date, entries: [VoiceHistoryEntry])] {
        store.historyGroupedByDay(kind: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("历史记录")
                    .font(AhakeySettingsTheme.pageTitleFont)
                    .foregroundStyle(AhakeySettingsTheme.primaryText)
                Text("本机口述转写记录。保存多久请到「通用」设置。")
                    .font(AhakeySettingsTheme.rowSubtitleFont)
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
            }

            if groups.isEmpty {
                emptyState
                    .featureCoachTip(.voiceEmptyHistory, isActive: true, alignment: .topTrailing)
            } else {
                ForEach(groups, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(dayTitle(group.day))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                            .padding(.top, 4)

                        VStack(spacing: 0) {
                            ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                                historyRow(entry)
                                if index < group.entries.count - 1 {
                                    Rectangle()
                                        .fill(AhakeySettingsTheme.divider)
                                        .frame(height: 1)
                                        .padding(.leading, 72)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: AhakeySettingsTheme.cardCornerRadius, style: .continuous)
                                .fill(AhakeySettingsTheme.cardBackground)
                        )
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("暂无历史记录")
                .font(AhakeySettingsTheme.rowTitleFont)
                .foregroundStyle(AhakeySettingsTheme.primaryText)
            Text("试录或按下语音键完成转写后，记录会出现在这里。")
                .font(AhakeySettingsTheme.rowSubtitleFont)
                .foregroundStyle(AhakeySettingsTheme.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AhakeySettingsTheme.cardCornerRadius, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(AhakeySettingsTheme.divider)
        )
    }

    private func historyRow(_ entry: VoiceHistoryEntry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(timeTitle(entry.createdAt))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                .frame(width: 56, alignment: .leading)

            Text(entry.text)
                .font(.system(size: 13))
                .foregroundStyle(AhakeySettingsTheme.primaryText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if entry.status == .cancelled || entry.status == .failed {
                Button {
                    nativeSpeech.toggleRecordingFromVoiceKey()
                } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Menu {
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.text, forType: .string)
                }
                Button("删除", role: .destructive) {
                    store.deleteHistory(id: entry.id)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
        .padding(.vertical, 12)
    }

    private func dayTitle(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: day)
    }

    private func timeTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "hh:mm a"
        return formatter.string(from: date)
    }
}
