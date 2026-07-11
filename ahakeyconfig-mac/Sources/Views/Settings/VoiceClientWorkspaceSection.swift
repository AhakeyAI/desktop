import SwiftUI

/// Shared voice permissions, routing summary, and try-recording controls for Studio diagnostics and Settings voice tab.
struct VoiceClientWorkspaceSection: View {
    struct Labels {
        var permissionsTitle: String
        var inputMonitoring: String
        var accessibility: String
        var microphone: String
        var speechRecognition: String
        var routingTitle: String
        var trySectionTitle: String
        var tryHint: String
        var tryRecord: String
        var recheckPermissions: String
        var granted: String
        var missing: String
        var emptyTranscript: String
    }

    enum Presentation {
        case studioGroupBox
        case settingsCards
    }

    let labels: Labels
    var presentation: Presentation = .studioGroupBox

    @ObservedObject private var voiceRelay = VoiceRelayService.shared
    @ObservedObject private var nativeSpeech = NativeSpeechTranscriptionService.shared

    static var studioDefault: Labels {
        Labels(
            permissionsTitle: "系统权限",
            inputMonitoring: "输入监控",
            accessibility: "辅助功能",
            microphone: "麦克风",
            speechRecognition: "语音转写",
            routingTitle: "语音路由",
            trySectionTitle: "试录",
            tryHint: "点击下方按钮试录，转写会同步到展开岛虚拟键盘。",
            tryRecord: "试录",
            recheckPermissions: "重新检查",
            granted: "已授权",
            missing: "未授权",
            emptyTranscript: "暂无转写"
        )
    }

    static func labels(localized key: (String) -> String) -> Labels {
        Labels(
            permissionsTitle: key("ahakey.settings.voice.permissions"),
            inputMonitoring: key("ahakey.settings.voice.inputMonitoring"),
            accessibility: key("ahakey.settings.voice.accessibility"),
            microphone: key("ahakey.settings.voice.microphone"),
            speechRecognition: key("ahakey.settings.voice.speechRecognition"),
            routingTitle: key("ahakey.settings.voice.routing"),
            trySectionTitle: key("ahakey.settings.voice.trySection"),
            tryHint: key("ahakey.settings.voice.tryHint"),
            tryRecord: key("ahakey.settings.voice.tryRecord"),
            recheckPermissions: key("ahakey.settings.voice.recheckPermissions"),
            granted: key("ahakey.settings.voice.granted"),
            missing: key("ahakey.settings.voice.missing"),
            emptyTranscript: key("virtualKeyboard.voiceHistoryEmpty")
        )
    }

    var body: some View {
        switch presentation {
        case .studioGroupBox:
            VStack(alignment: .leading, spacing: 16) {
                permissionsContent
                routingContent
                tryRecordContent
            }
        case .settingsCards:
            VStack(alignment: .leading, spacing: 20) {
                settingsCard(sectionTitle: labels.permissionsTitle) {
                    settingsPermissionRow(labels.inputMonitoring, granted: voiceRelay.inputMonitoringGranted)
                    settingsDivider()
                    settingsPermissionRow(labels.accessibility, granted: voiceRelay.accessibilityGranted)
                    settingsDivider()
                    settingsPermissionRow(labels.microphone, granted: nativeSpeech.microphoneGranted)
                    settingsDivider()
                    settingsPermissionRow(labels.speechRecognition, granted: nativeSpeech.speechRecognitionGranted)
                }

                settingsCard(sectionTitle: labels.routingTitle) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(voiceRelay.activeRouteSummary)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AhaKeyStudioEmbeddedTheme.primaryText)
                        Text(voiceRelay.statusMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(AhaKeyStudioEmbeddedTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }

                settingsCard(sectionTitle: labels.trySectionTitle) {
                    tryRecordInnerContent
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                }
            }
        }
    }

    @ViewBuilder
    private var permissionsContent: some View {
        GroupBox(labels.permissionsTitle) {
            VStack(alignment: .leading, spacing: 8) {
                permissionBadge(title: labels.inputMonitoring, granted: voiceRelay.inputMonitoringGranted)
                permissionBadge(title: labels.accessibility, granted: voiceRelay.accessibilityGranted)
                permissionBadge(title: labels.microphone, granted: nativeSpeech.microphoneGranted)
                permissionBadge(title: labels.speechRecognition, granted: nativeSpeech.speechRecognitionGranted)
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var routingContent: some View {
        GroupBox(labels.routingTitle) {
            VStack(alignment: .leading, spacing: 6) {
                Text(voiceRelay.activeRouteSummary)
                    .font(.callout.weight(.medium))
                Text(voiceRelay.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var tryRecordContent: some View {
        GroupBox(labels.trySectionTitle) {
            tryRecordInnerContent
                .padding(.top, 4)
        }
    }

    private var tryRecordInnerContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if nativeSpeech.isRecording {
                Text(nativeSpeech.transcriptPreview.isEmpty ? labels.emptyTranscript : nativeSpeech.transcriptPreview)
                    .font(.system(size: 13))
                    .foregroundStyle(presentation == .settingsCards ? AhaKeyStudioEmbeddedTheme.primaryText : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !nativeSpeech.lastCommittedText.isEmpty {
                Text(nativeSpeech.lastCommittedText)
                    .font(.system(size: 13))
                    .foregroundStyle(presentation == .settingsCards ? AhaKeyStudioEmbeddedTheme.secondaryText : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(labels.tryHint)
                    .font(.system(size: 12))
                    .foregroundStyle(presentation == .settingsCards ? AhaKeyStudioEmbeddedTheme.secondaryText : .secondary)
            }

            HStack(spacing: 10) {
                Button(nativeSpeech.isRecording ? "结束并写入" : labels.tryRecord) {
                    nativeSpeech.toggleRecordingFromVoiceKey()
                }
                .buttonStyle(.borderedProminent)

                Button(labels.recheckPermissions) {
                    voiceRelay.refreshPermissions(deferredTCCRequery: true)
                    nativeSpeech.refreshPermissions(deferredTCCRequery: true)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func permissionBadge(title: String, granted: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(granted ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption.weight(.semibold))
            Text(granted ? labels.granted : labels.missing)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 999)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    @ViewBuilder
    private func settingsCard<Content: View>(sectionTitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(sectionTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AhaKeyStudioEmbeddedTheme.secondaryText)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AhaKeyStudioEmbeddedTheme.cardBackground)
            )
        }
    }

    private func settingsPermissionRow(_ title: String, granted: Bool) -> some View {
        HStack {
            Circle()
                .fill(granted ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AhaKeyStudioEmbeddedTheme.primaryText)
            Spacer()
            Text(granted ? labels.granted : labels.missing)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AhaKeyStudioEmbeddedTheme.secondaryText)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func settingsDivider() -> some View {
        Rectangle()
            .fill(AhaKeyStudioEmbeddedTheme.divider)
            .frame(height: 1)
            .padding(.leading, 18)
    }
}
