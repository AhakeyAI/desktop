import SwiftUI

struct AhaKeyVoiceGeneralConfigPane: View {
    @ObservedObject private var store = VoiceInputStore.shared
    @ObservedObject private var voiceRelay = VoiceRelayService.shared
    @ObservedObject private var nativeSpeech = NativeSpeechTranscriptionService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("通用设置")
                    .font(AhakeySettingsTheme.pageTitleFont)
                    .foregroundStyle(AhakeySettingsTheme.primaryText)
                Text("试录、路由与历史保存时长。系统权限请到「用户中心 · 设置」。")
                    .font(AhakeySettingsTheme.rowSubtitleFont)
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
            }

            tryRecordCard
            routingCard
            retentionCard
            preferencesHintCard
        }
    }

    private var tryRecordCard: some View {
        AhakeySettingsCard(sectionTitle: "试录") {
            VStack(alignment: .leading, spacing: 10) {
                if nativeSpeech.isRecording {
                    Text(nativeSpeech.transcriptPreview.isEmpty ? "暂无转写" : nativeSpeech.transcriptPreview)
                        .font(.system(size: 13))
                        .foregroundStyle(AhakeySettingsTheme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if !nativeSpeech.lastCommittedText.isEmpty {
                    Text(nativeSpeech.lastCommittedText)
                        .font(.system(size: 13))
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("点击下方按钮试录，转写会写入历史并同步到展开岛虚拟键盘。")
                        .font(.system(size: 12))
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                }

                HStack(spacing: 10) {
                    Button(nativeSpeech.isRecording ? "结束并写入" : "试录") {
                        nativeSpeech.toggleRecordingFromVoiceKey()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("重新检查权限") {
                        voiceRelay.refreshPermissions(deferredTCCRequery: true)
                        nativeSpeech.refreshPermissions(deferredTCCRequery: true)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 14)
        }
    }

    private var routingCard: some View {
        AhakeySettingsCard(sectionTitle: "语音路由") {
            VStack(alignment: .leading, spacing: 8) {
                Text(voiceRelay.activeRouteSummary)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AhakeySettingsTheme.primaryText)
                Text(voiceRelay.statusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 14)
        }
    }

    private var retentionCard: some View {
        AhakeySettingsCard(sectionTitle: "保存历史") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("保存时长")
                        .font(AhakeySettingsTheme.rowTitleFont)
                        .foregroundStyle(AhakeySettingsTheme.primaryText)
                    Text("控制「历史记录」页保留多久；到期自动清理。")
                        .font(AhakeySettingsTheme.rowSubtitleFont)
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                }
                Spacer()
                Picker("", selection: $store.retention) {
                    ForEach(VoiceHistoryRetention.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 110)
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 14)
        }
    }

    private var preferencesHintCard: some View {
        AhakeySettingsCard(sectionTitle: "相关入口") {
            VStack(alignment: .leading, spacing: 10) {
                Text("系统权限与隐私说明已迁至「用户中心 · 设置」。")
                    .font(AhakeySettingsTheme.rowSubtitleFont)
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    StudioNavigationRouter.shared.openUserCenter(section: .settings)
                } label: {
                    HStack {
                        Text("打开用户中心 · 设置")
                            .font(AhakeySettingsTheme.rowTitleFont)
                            .foregroundStyle(AhakeySettingsTheme.primaryText)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    StudioNavigationRouter.shared.selectSettingsTab(.hardware)
                    StudioNavigationRouter.shared.navigate(to: .voice)
                } label: {
                    HStack {
                        Text("在硬件设备中配置语音键")
                            .font(AhakeySettingsTheme.rowTitleFont)
                            .foregroundStyle(AhakeySettingsTheme.primaryText)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 14)
        }
    }
}