import AppKit
import SwiftUI

/// 插件市场：默认「我的插件」；开源市场为次级入口子页。商店级版式（Hero / 货架 / 产品页）。
struct AhakeyPluginMarketPane: View {
    @Binding var section: AhakeyPluginMarketSection
    var onClose: () -> Void

    @State private var installed: [AhakeyInstalledPluginsStore.InstalledPlugin] = []
    @State private var showInstallGuide = false
    @State private var selectedInstalledId: String?
    @State private var selectedShelfId: String?

    init(section: Binding<AhakeyPluginMarketSection> = .constant(.mine), onClose: @escaping () -> Void) {
        self._section = section
        self.onClose = onClose
    }

    private var featuredItem: AhakeyPluginMarketItem? {
        AhakeyPluginMarketCatalog.items.first(where: { $0.status == .inDevelopment })
            ?? AhakeyPluginMarketCatalog.items.first
    }

    private var shelfItems: [AhakeyPluginMarketItem] {
        guard let featuredId = featuredItem?.id else {
            return AhakeyPluginMarketCatalog.items
        }
        return AhakeyPluginMarketCatalog.items.filter { $0.id != featuredId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            storeChrome
                .padding(.horizontal, AhakeyPluginMarketTheme.contentPadding)
                .padding(.top, 18)
                .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let selectedInstalledId,
                       let plugin = installed.first(where: { $0.id == selectedInstalledId }) {
                        installedProductPage(plugin)
                    } else if let selectedShelfId,
                              let item = AhakeyPluginMarketCatalog.items.first(where: { $0.id == selectedShelfId }) {
                        shelfProductPage(item)
                    } else {
                        storeHeader
                        switch section {
                        case .mine:
                            librarySection
                        case .store:
                            storefrontSection
                        }
                    }
                }
                .padding(.horizontal, AhakeyPluginMarketTheme.contentPadding)
                .padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AhakeyPluginMarketTheme.canvas)
        .featureCoachTip(.pluginComingSoon, isActive: true, alignment: .topTrailing)
        .onAppear(perform: refreshInstalled)
        .onChange(of: section) { newValue in
            clearDetailSelection()
            if newValue == .mine {
                refreshInstalled()
            }
        }
    }

    // MARK: - Chrome

    private var storeChrome: some View {
        HStack(spacing: 12) {
            Button(action: handleTopBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text(topBackTitle)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(AhakeyPluginMarketTheme.secondaryText)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
    }

    private var topBackTitle: String {
        if selectedInstalledId != nil || selectedShelfId != nil {
            return "返回列表"
        }
        if section == .store {
            return "返回我的插件"
        }
        return "返回"
    }

    private func handleTopBack() {
        if selectedInstalledId != nil || selectedShelfId != nil {
            clearDetailSelection()
            return
        }
        if section == .store {
            section = .mine
            return
        }
        onClose()
    }

    private var storeHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(section == .store ? "开源市场" : "插件市场")
                    .font(AhakeyPluginMarketTheme.storeTitleFont)
                    .foregroundStyle(AhakeyPluginMarketTheme.primaryText)
                Text(
                    section == .store
                        ? "发现开发中与示例插件"
                        : "管理本机已装扩展"
                )
                .font(AhakeyPluginMarketTheme.captionFont)
                .foregroundStyle(AhakeyPluginMarketTheme.secondaryText)
            }

            Spacer(minLength: 8)

            if section == .mine {
                Button {
                    clearDetailSelection()
                    section = .store
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("开源市场")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(AhakeyPluginMarketTheme.accent)
                    )
                }
                .buttonStyle(.plain)
                .help("浏览并下载开源插件（次级入口）")
            }
        }
    }

    // MARK: - Library（我的插件）

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 20) {
            libraryListBlock

            DisclosureGroup(isExpanded: $showInstallGuide) {
                installGuideBody
                    .padding(.top, 10)
            } label: {
                Text("安装教程")
                    .font(AhakeyPluginMarketTheme.captionFont)
                    .foregroundStyle(AhakeyPluginMarketTheme.tertiaryText)
            }
            .tint(AhakeyPluginMarketTheme.tertiaryText)
        }
    }

    private var libraryListBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("资料库 · 已安装")
                    .font(AhakeyPluginMarketTheme.sectionTitleFont)
                    .foregroundStyle(AhakeyPluginMarketTheme.primaryText)
                Spacer(minLength: 0)
                Button("刷新") {
                    refreshInstalled()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AhakeyPluginMarketTheme.accent)
            }

            if installed.isEmpty {
                emptyLibraryTile
            } else {
                ForEach(installed) { plugin in
                    libraryRow(plugin)
                }
            }
        }
    }

    private var emptyLibraryTile: some View {
        storeTile {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    iconTile(systemImage: "tray", tint: AhakeyPluginMarketTheme.tertiaryText)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("尚未安装插件")
                            .font(AhakeyPluginMarketTheme.tileTitleFont)
                            .foregroundStyle(AhakeyPluginMarketTheme.primaryText)
                        Text("从开源市场挑选扩展，或按教程放入本机插件目录。")
                            .font(AhakeyPluginMarketTheme.captionFont)
                            .foregroundStyle(AhakeyPluginMarketTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button {
                    section = .store
                } label: {
                    Text("去开源市场看看")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AhakeyPluginMarketTheme.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func libraryRow(_ plugin: AhakeyInstalledPluginsStore.InstalledPlugin) -> some View {
        Button {
            selectedShelfId = nil
            selectedInstalledId = plugin.id
        } label: {
            storeTile {
                HStack(spacing: 14) {
                    iconTile(systemImage: "puzzlepiece.extension")
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(plugin.name)
                                .font(AhakeyPluginMarketTheme.tileTitleFont)
                                .foregroundStyle(AhakeyPluginMarketTheme.primaryText)
                                .lineLimit(1)
                            statusPill(title: "已安装", tint: Color.green)
                        }
                        Text("v\(plugin.version) · \(plugin.id)")
                            .font(AhakeyPluginMarketTheme.metaFont)
                            .foregroundStyle(AhakeyPluginMarketTheme.tertiaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AhakeyPluginMarketTheme.tertiaryText)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var installGuideBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            guideStep(index: 1, title: "发现开源插件", detail: "从右上角进入「开源市场」挑选已开源的扩展能力。")
            Divider().background(AhakeyPluginMarketTheme.divider)
            guideStep(index: 2, title: "下载并安装到本机", detail: "安装目录：\(AhakeyPluginMarketCatalog.localInstallPathHint)")
            Divider().background(AhakeyPluginMarketTheme.divider)
            guideStep(index: 3, title: "宿主自动扫描加载", detail: "每个插件目录需包含 plugin.json；权限按白名单声明。")
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AhakeyPluginMarketTheme.tileBackground.opacity(0.7))
        )
    }

    private func guideStep(index: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(AhakeyPluginMarketTheme.accent)
                .frame(width: 20, height: 20)
                .background(Circle().fill(AhakeyPluginMarketTheme.accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AhakeyPluginMarketTheme.secondaryText)
                Text(detail)
                    .font(AhakeyPluginMarketTheme.captionFont)
                    .foregroundStyle(AhakeyPluginMarketTheme.tertiaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Storefront（开源市场）

    private var storefrontSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let featured = featuredItem {
                featuredHero(featured)
            }
            shelfGrid
            contributeFooter
        }
    }

    private func featuredHero(_ item: AhakeyPluginMarketItem) -> some View {
        Button {
            selectedInstalledId = nil
            selectedShelfId = item.id
        } label: {
            HStack(alignment: .center, spacing: 20) {
                iconTile(
                    systemImage: item.systemImage,
                    size: 72,
                    corner: 18,
                    tint: .white,
                    fill: Color.white.opacity(0.18)
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("精选")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.72))
                    Text(item.name)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(item.summary)
                        .font(AhakeyPluginMarketTheme.captionFont)
                        .foregroundStyle(Color.white.opacity(0.78))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("查看")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule(style: .continuous).fill(Color.white.opacity(0.22)))
                        .padding(.top, 4)
                }

                Spacer(minLength: 0)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AhakeyPluginMarketTheme.heroCornerRadius, style: .continuous)
                    .fill(AhakeyPluginMarketTheme.heroGradient)
            )
        }
        .buttonStyle(.plain)
    }

    private var shelfGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("全部插件")
                .font(AhakeyPluginMarketTheme.sectionTitleFont)
                .foregroundStyle(AhakeyPluginMarketTheme.primaryText)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ],
                spacing: 12
            ) {
                ForEach(shelfItems) { item in
                    shelfTile(item)
                }
            }
        }
    }

    private func shelfTile(_ item: AhakeyPluginMarketItem) -> some View {
        Button {
            selectedInstalledId = nil
            selectedShelfId = item.id
        } label: {
            storeTile {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        iconTile(systemImage: item.systemImage)
                        Spacer(minLength: 0)
                        statusPill(for: item.status)
                    }
                    Text(item.name)
                        .font(AhakeyPluginMarketTheme.tileTitleFont)
                        .foregroundStyle(AhakeyPluginMarketTheme.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(item.summary)
                        .font(AhakeyPluginMarketTheme.captionFont)
                        .foregroundStyle(AhakeyPluginMarketTheme.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    private var contributeFooter: some View {
        storeTile {
            VStack(alignment: .leading, spacing: 10) {
                Text("开发与贡献")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AhakeyPluginMarketTheme.secondaryText)
                Text("鼓励自行开发插件并开源回馈社区。本地可用 TypeScript SDK 示例起步。")
                    .font(AhakeyPluginMarketTheme.captionFont)
                    .foregroundStyle(AhakeyPluginMarketTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        revealSDKExamples()
                    } label: {
                        Label("查看 SDK 示例", systemImage: "folder")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)

                    Button("上传到社区") {}
                        .buttonStyle(.bordered)
                        .disabled(true)
                        .help("即将开放：提交开源插件到社区货架")

                    Spacer(minLength: 0)
                }
            }
        }
        .opacity(0.92)
    }

    // MARK: - Product pages

    private func installedProductPage(_ plugin: AhakeyInstalledPluginsStore.InstalledPlugin) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            productHero(
                systemImage: "puzzlepiece.extension",
                title: plugin.name,
                badge: statusPill(title: "已安装", tint: Color.green),
                meta: "\(plugin.id) · v\(plugin.version)"
            ) {
                HStack(spacing: 10) {
                    Button {
                        revealInFinder(path: plugin.directoryPath)
                    } label: {
                        Label("在 Finder 中显示", systemImage: "folder")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AhakeyPluginMarketTheme.accent)

                    Button("卸载") {}
                        .buttonStyle(.bordered)
                        .disabled(true)
                        .help("即将开放：从本机插件目录移除")

                    Text("卸载即将开放")
                        .font(AhakeyPluginMarketTheme.captionFont)
                        .foregroundStyle(AhakeyPluginMarketTheme.tertiaryText)

                    Spacer(minLength: 0)
                }
            }

            productDetailBlock {
                VStack(alignment: .leading, spacing: 12) {
                    Text("安装路径")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AhakeyPluginMarketTheme.secondaryText)
                    Text(plugin.directoryPath)
                        .font(AhakeyPluginMarketTheme.metaFont)
                        .foregroundStyle(AhakeyPluginMarketTheme.tertiaryText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    if !plugin.permissions.isEmpty {
                        Text("权限")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AhakeyPluginMarketTheme.secondaryText)
                        FlowPermissionChips(permissions: plugin.permissions)
                    }
                }
            }
        }
    }

    private func shelfProductPage(_ item: AhakeyPluginMarketItem) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            productHero(
                systemImage: item.systemImage,
                title: item.name,
                badge: statusPill(for: item.status),
                meta: "\(item.id) · v\(item.version)"
            ) {
                HStack(spacing: 10) {
                    Button("下载") {}
                        .buttonStyle(.bordered)
                        .disabled(true)
                        .help("即将开放：从开源仓库下载插件包")

                    Button("安装到本机") {}
                        .buttonStyle(.borderedProminent)
                        .tint(AhakeyPluginMarketTheme.accent)
                        .disabled(true)
                        .help("即将开放：安装到 \(AhakeyPluginMarketCatalog.localInstallPathHint)")

                    Text("即将开放")
                        .font(AhakeyPluginMarketTheme.captionFont)
                        .foregroundStyle(AhakeyPluginMarketTheme.tertiaryText)

                    Spacer(minLength: 0)
                }
            }

            productDetailBlock {
                VStack(alignment: .leading, spacing: 12) {
                    Text(item.summary)
                        .font(.system(size: 13))
                        .foregroundStyle(AhakeyPluginMarketTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("源码")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AhakeyPluginMarketTheme.secondaryText)
                    Text(item.repoPath)
                        .font(AhakeyPluginMarketTheme.metaFont)
                        .foregroundStyle(AhakeyPluginMarketTheme.tertiaryText)
                        .textSelection(.enabled)

                    Text("权限")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AhakeyPluginMarketTheme.secondaryText)
                    FlowPermissionChips(permissions: item.permissions)
                }
            }
        }
    }

    private func productHero<Badge: View, CTA: View>(
        systemImage: String,
        title: String,
        badge: Badge,
        meta: String,
        @ViewBuilder cta: () -> CTA
    ) -> some View {
        storeTile {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    iconTile(
                        systemImage: systemImage,
                        size: AhakeyPluginMarketTheme.productIconSize,
                        corner: 18
                    )
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(title)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(AhakeyPluginMarketTheme.primaryText)
                            badge
                        }
                        Text(meta)
                            .font(AhakeyPluginMarketTheme.metaFont)
                            .foregroundStyle(AhakeyPluginMarketTheme.tertiaryText)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                }
                cta()
            }
        }
    }

    private func productDetailBlock<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        storeTile {
            content()
        }
    }

    // MARK: - Store primitives

    private func storeTile<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AhakeyPluginMarketTheme.tileCornerRadius, style: .continuous)
                    .fill(AhakeyPluginMarketTheme.tileBackground)
            )
    }

    private func iconTile(
        systemImage: String,
        size: CGFloat = AhakeyPluginMarketTheme.iconTileSize,
        corner: CGFloat = AhakeyPluginMarketTheme.iconTileCorner,
        tint: Color = AhakeyPluginMarketTheme.accent,
        fill: Color? = nil
    ) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(fill ?? tint.opacity(0.12))
            )
    }

    private func statusPill(title: String, tint: Color) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint.opacity(0.95))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule(style: .continuous).fill(tint.opacity(0.14)))
    }

    private func statusPill(for status: AhakeyPluginMarketItem.Status) -> some View {
        statusPill(
            title: status.title,
            tint: status == .inDevelopment ? Color.orange : AhakeyPluginMarketTheme.accent
        )
    }

    // MARK: - Helpers

    private func clearDetailSelection() {
        selectedInstalledId = nil
        selectedShelfId = nil
    }

    private func refreshInstalled() {
        installed = AhakeyInstalledPluginsStore.discover()
    }

    private func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func revealSDKExamples() {
        let candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("sdks/typescript/examples"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("../sdks/typescript/examples"),
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent("sdks/typescript/examples"),
        ]
        if let existing = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            NSWorkspace.shared.activateFileViewerSelecting([existing])
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("sdks/typescript/examples", forType: .string)
    }
}

/// 权限标签横向换行。
private struct FlowPermissionChips: View {
    let permissions: [String]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 120), spacing: 6, alignment: .leading)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(permissions, id: \.self) { permission in
                Text(permission)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(AhakeyPluginMarketTheme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(AhakeyPluginMarketTheme.controlFill)
                    )
            }
        }
    }
}

/// 兼容旧引用名。
typealias AhakeyPluginMarketPlaceholderPane = AhakeyPluginMarketPane
