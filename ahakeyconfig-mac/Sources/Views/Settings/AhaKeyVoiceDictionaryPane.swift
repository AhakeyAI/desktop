import SwiftUI

struct AhaKeyVoiceDictionaryPane: View {
    @ObservedObject private var store = VoiceInputStore.shared
    @State private var showsEditor = false
    @State private var editingEntry: VoiceDictionaryEntry?
    @State private var draftPhrase = ""
    @State private var draftReplacement = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("词典")
                        .font(AhakeySettingsTheme.pageTitleFont)
                        .foregroundStyle(AhakeySettingsTheme.primaryText)
                    Text("转写完成后按词条做本地替换；较长短语优先匹配。")
                        .font(AhakeySettingsTheme.rowSubtitleFont)
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                }
                Spacer(minLength: 8)
                Button {
                    editingEntry = nil
                    draftPhrase = ""
                    draftReplacement = ""
                    showsEditor = true
                } label: {
                    Label("添加", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if store.dictionary.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.dictionary.enumerated()), id: \.element.id) { index, entry in
                        dictionaryRow(entry)
                        if index < store.dictionary.count - 1 {
                            Rectangle()
                                .fill(AhakeySettingsTheme.divider)
                                .frame(height: 1)
                                .padding(.leading, AhakeySettingsTheme.rowPaddingH)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: AhakeySettingsTheme.cardCornerRadius, style: .continuous)
                        .fill(AhakeySettingsTheme.cardBackground)
                )
            }
        }
        .sheet(isPresented: $showsEditor) {
            dictionaryEditorSheet
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("暂无词条")
                .font(AhakeySettingsTheme.rowTitleFont)
                .foregroundStyle(AhakeySettingsTheme.primaryText)
            Text("添加「原词 → 替换为」后，后续听写结果会自动替换。")
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

    private func dictionaryRow(_ entry: VoiceDictionaryEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.phrase)
                    .font(AhakeySettingsTheme.rowTitleFont)
                    .foregroundStyle(AhakeySettingsTheme.primaryText)
                Text("→ \(entry.replacement)")
                    .font(AhakeySettingsTheme.rowSubtitleFont)
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(
                get: { entry.enabled },
                set: { enabled in
                    var next = entry
                    next.enabled = enabled
                    store.updateDictionaryEntry(next)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            Button {
                editingEntry = entry
                draftPhrase = entry.phrase
                draftReplacement = entry.replacement
                showsEditor = true
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("编辑")

            Button(role: .destructive) {
                store.deleteDictionaryEntry(id: entry.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("删除")
        }
        .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
        .padding(.vertical, 12)
    }

    private var dictionaryEditorSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editingEntry == nil ? "添加词条" : "编辑词条")
                .font(.headline)
            TextField("原词 / 短语", text: $draftPhrase)
                .textFieldStyle(.roundedBorder)
            TextField("替换为", text: $draftReplacement)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消") { showsEditor = false }
                Button("保存") {
                    saveEditor()
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || draftReplacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func saveEditor() {
        if var editing = editingEntry {
            editing.phrase = draftPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
            editing.replacement = draftReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
            store.updateDictionaryEntry(editing)
        } else {
            store.addDictionaryEntry(phrase: draftPhrase, replacement: draftReplacement)
        }
        showsEditor = false
    }
}
