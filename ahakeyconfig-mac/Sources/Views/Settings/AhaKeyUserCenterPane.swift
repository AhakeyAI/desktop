import AppKit
import CoreImage
import SwiftUI

/// 用户中心弹窗：左导航（用户中心 / 设置 / 使用数据 / 关于我们 / 帮助 / 版本说明）+ 右内容。
struct AhaKeyUserCenterPane: View {
    @ObservedObject var bleManager: AhaKeyBLEManager
    @Binding var section: AhaKeyUserCenterSection
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            userCenterSidebar
                .frame(width: 188)
                .background(AhakeySettingsTheme.sidebarBackground)

            Rectangle()
                .fill(AhakeySettingsTheme.divider)
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    Text(section.title)
                        .font(AhakeySettingsTheme.pageTitleFont)
                        .foregroundStyle(AhakeySettingsTheme.primaryText)
                    Spacer(minLength: 0)
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AhakeySettingsTheme.secondaryText)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(AhakeySettingsTheme.controlFill)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("关闭")
                    .keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 16)

                ScrollView(.vertical, showsIndicators: true) {
                    sectionContent
                        .padding(.horizontal, 28)
                        .padding(.bottom, 28)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(AhakeySettingsTheme.contentBackground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AhakeySettingsTheme.contentBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var userCenterSidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(AhaKeyUserCenterSection.primarySections) { item in
                sidebarRow(item)
            }

            Rectangle()
                .fill(AhakeySettingsTheme.divider)
                .frame(height: 1)
                .padding(.vertical, 10)
                .padding(.horizontal, 8)

            ForEach(AhaKeyUserCenterSection.secondarySections) { item in
                sidebarRow(item)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private func sidebarRow(_ item: AhaKeyUserCenterSection) -> some View {
        Button {
            section = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
                if item.showsExternalLinkHint {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                }
            }
            .foregroundStyle(
                section == item
                    ? AhakeySettingsTheme.primaryText
                    : AhakeySettingsTheme.secondaryText
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(section == item ? AhakeySettingsTheme.controlFill : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .account:
            AhaKeyUserCenterContent(showsHero: false, layoutStyle: .referenceRows)
        case .settings:
            AhaKeyUserCenterSettingsContent(
                bleManager: bleManager,
                onOpenAccount: { section = .account }
            )
        case .usageData:
            AhaKeyUserCenterUsageDataContent()
        case .about:
            AhaKeyUserCenterAboutContent()
        case .help:
            AhaKeyUserCenterHelpContent(onCloseUserCenter: onClose)
        case .releaseNotes:
            AhaKeyUserCenterReleaseNotesContent()
        }
    }
}

/// 可复用的用户中心账户内容（整页与 Studio Sheet 共用）。
struct AhaKeyUserCenterContent: View {
    enum LayoutStyle {
        case stackedCards
        case referenceRows
    }

    var showsHero: Bool = true
    var layoutStyle: LayoutStyle = .stackedCards

    @StateObject private var account = CloudAccountManager.shared
    @StateObject private var optimizer = AhaTypeTextOptimizer.shared
    @FocusState private var focusedLoginField: LoginField?
    @State private var hoveredPlan: CloudRechargePlan?
    @State private var showsUpgradePanel = false
    @State private var showsGiftPanel = false
    @State private var showMembership = false
    @State private var installedPluginCount = 0

    private enum LoginField {
        case phone
        case password
    }

    private var shelfPluginCount: Int { AhakeyPluginMarketCatalog.items.count }

    var body: some View {
        Group {
            switch layoutStyle {
            case .stackedCards:
                stackedBody
            case .referenceRows:
                referenceBody
            }
        }
        .alert("云端账号", isPresented: Binding(
            get: { account.alertMessage != nil },
            set: { if !$0 { account.alertMessage = nil } }
        )) {
            Button("好", role: .cancel) { account.alertMessage = nil }
        } message: {
            Text(account.alertMessage ?? "")
        }
        .onAppear {
            refreshCommunityStats()
            optimizer.refreshFromDisk()
            if account.isLoggedIn {
                account.refreshProfile()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    focusedLoginField = .phone
                }
            }
        }
    }

    private var stackedBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            if showsHero {
                UserCenterHero(
                    isLoggedIn: account.isLoggedIn,
                    isBusy: account.isBusy,
                    title: heroTitle,
                    subtitle: heroSubtitle,
                    avatarInitial: account.avatarInitial
                )
            }

            if account.isLoggedIn {
                profileCard
                ahaTypeCard
                billingCard
                couponCard
            } else {
                loginCard
                ahaTypeCard
            }
        }
    }

    private var referenceBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            communityIdentityCard
            communityStatsCard
            communityLinksCard

            if account.isLoggedIn {
                AhaKeySettingsDisclosureSection(
                    title: "会员与额度",
                    subtitle: "订阅、礼品卡与云端整理",
                    isExpanded: $showMembership
                ) {
                    membershipSection
                }

                HStack {
                    Spacer(minLength: 0)
                    Button("退出") { account.logout() }
                        .buttonStyle(UserCenterDangerButtonStyle())
                        .disabled(account.isBusy)
                        .frame(height: 36)
                }
                .padding(.top, 4)
            } else {
                loginCard
                ahaTypeCard
            }
        }
    }

    private var communityIdentityCard: some View {
        AhakeySettingsCard(sectionTitle: nil) {
            HStack(alignment: .center, spacing: 16) {
                UserCenterAvatar(
                    initial: account.isLoggedIn ? account.avatarInitial : "?",
                    size: 56
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(communityDisplayName)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AhakeySettingsTheme.primaryText)
                            .lineLimit(1)

                        Text(account.isLoggedIn ? "社区成员" : "访客")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(
                                account.isLoggedIn
                                    ? AhakeySettingsTheme.accentBlue
                                    : AhakeySettingsTheme.tertiaryText
                            )
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(
                                        account.isLoggedIn
                                            ? AhakeySettingsTheme.accentBlue.opacity(0.14)
                                            : AhakeySettingsTheme.controlFill
                                    )
                            )
                    }

                    Text(communityTagline)
                        .font(AhakeySettingsTheme.rowSubtitleFont)
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if account.isLoggedIn, !account.phoneDisplay.isEmpty {
                        Text(account.phoneDisplay)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                            .textSelection(.enabled)
                    }
                }

                Spacer(minLength: 0)

                if account.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 16)
        }
    }

    private var communityDisplayName: String {
        if account.isLoggedIn {
            let title = account.sidebarTitle
            if !title.isEmpty { return title }
            if !account.phoneDisplay.isEmpty { return account.phoneDisplay }
            return "AhaKey 成员"
        }
        return "加入开源社区"
    }

    private var communityTagline: String {
        if account.isLoggedIn {
            return "发现、安装并回馈开源插件；你的本机扩展与社区货架相连。"
        }
        return "登录后同步会员额度；浏览开源市场、安装插件与贡献无需等待。"
    }

    private var communityStatsCard: some View {
        AhakeySettingsCard(sectionTitle: "社区摘要") {
            HStack(spacing: 12) {
                communityStatTile(
                    title: "本机插件",
                    value: "\(installedPluginCount)",
                    detail: "已安装"
                )
                communityStatTile(
                    title: "开源货架",
                    value: "\(shelfPluginCount)",
                    detail: "可发现"
                )
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 14)
        }
    }

    private func communityStatTile(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AhakeySettingsTheme.tertiaryText)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(AhakeySettingsTheme.primaryText)
            Text(detail)
                .font(AhakeySettingsTheme.rowSubtitleFont)
                .foregroundStyle(AhakeySettingsTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AhakeySettingsTheme.controlFill)
        )
    }

    private var communityLinksCard: some View {
        AhakeySettingsCard(sectionTitle: "社区入口") {
            communityLinkRow(
                title: "开源市场",
                detail: "浏览开发中与示例插件货架",
                systemImage: "bag"
            ) {
                StudioNavigationRouter.shared.openPluginMarket(section: .store)
            }
            AhakeySettingsCardDivider()
            communityLinkRow(
                title: "我的插件",
                detail: "本机已装列表与安装教程",
                systemImage: "puzzlepiece.extension"
            ) {
                StudioNavigationRouter.shared.openPluginMarket(section: .mine)
            }
            AhakeySettingsCardDivider()
            communityLinkRow(
                title: "开发与贡献",
                detail: "SDK 示例与回馈社区货架",
                systemImage: "hammer"
            ) {
                StudioNavigationRouter.shared.openPluginMarket(section: .store)
            }
        }
    }

    private func communityLinkRow(
        title: String,
        detail: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AhakeySettingsTheme.accentBlue)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AhakeySettingsTheme.accentBlue.opacity(0.12))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AhakeySettingsTheme.rowTitleFont)
                        .foregroundStyle(AhakeySettingsTheme.primaryText)
                    Text(detail)
                        .font(AhakeySettingsTheme.rowSubtitleFont)
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AhakeySettingsTheme.tertiaryText)
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private var membershipSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            membershipSummaryRows
            if showsUpgradePanel {
                billingCard
            }
            if showsGiftPanel {
                couponCard
            }
            ahaTypeCard
        }
    }

    private var heroTitle: String {
        if account.isLoggedIn {
            let title = account.sidebarTitle
            return title.isEmpty ? "社区成员" : title
        }
        return "加入开源社区"
    }

    private var heroSubtitle: String {
        if account.isLoggedIn {
            return "参与 AhaKey 开源插件生态"
        }
        return "登录后同步额度；插件市场随时可逛"
    }

    private var subscriptionStatusText: String {
        let valid = account.validUntilDisplay
        if valid.isEmpty || valid.contains("无") {
            return "Free"
        }
        return valid
    }

    // MARK: - Membership rows

    private var membershipSummaryRows: some View {
        AhakeySettingsCard(sectionTitle: nil) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("订阅")
                            .font(AhakeySettingsTheme.rowTitleFont)
                            .foregroundStyle(AhakeySettingsTheme.primaryText)
                        Text(subscriptionStatusText)
                            .font(AhakeySettingsTheme.rowSubtitleFont)
                            .foregroundStyle(AhakeySettingsTheme.secondaryText)
                    }
                    Spacer(minLength: 8)
                    Button("升级") {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showsUpgradePanel.toggle()
                            if showsUpgradePanel { showsGiftPanel = false }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AhakeySettingsTheme.accentBlue)
                }
                .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
                .padding(.vertical, 14)

                AhakeySettingsCardDivider()

                HStack(alignment: .center, spacing: 12) {
                    Text("礼品卡")
                        .font(AhakeySettingsTheme.rowTitleFont)
                        .foregroundStyle(AhakeySettingsTheme.primaryText)
                    Spacer(minLength: 8)
                    Button("兑换") {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showsGiftPanel.toggle()
                            if showsGiftPanel { showsUpgradePanel = false }
                        }
                    }
                    .buttonStyle(UserCenterSecondaryButtonStyle())
                    .frame(height: 32)
                }
                .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
                .padding(.vertical, 14)
            }
        }
    }

    private func refreshCommunityStats() {
        installedPluginCount = AhakeyInstalledPluginsStore.discover().count
    }

    // MARK: - Login

    private var loginCard: some View {
        AhakeySettingsCard(sectionTitle: "登录") {
            VStack(alignment: .leading, spacing: 14) {
                UserCenterLabeledField(label: "手机号") {
                    TextField("", text: $account.phone, prompt: Text("11 位手机号").foregroundColor(AhakeySettingsTheme.tertiaryText))
                        .textFieldStyle(.plain)
                        .focused($focusedLoginField, equals: .phone)
                        .onSubmit { focusedLoginField = .password }
                }

                UserCenterLabeledField(label: "密码") {
                    SecureField("", text: $account.password, prompt: Text("输入密码").foregroundColor(AhakeySettingsTheme.tertiaryText))
                        .textFieldStyle(.plain)
                        .focused($focusedLoginField, equals: .password)
                        .onSubmit { account.login() }
                }

                Toggle("记住密码", isOn: $account.rememberPassword)
                    .toggleStyle(.switch)
                    .font(AhakeySettingsTheme.rowSubtitleFont)
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)

                HStack(spacing: 10) {
                    UserCenterPrimaryButton(
                        title: "登录",
                        isBusy: account.isBusy,
                        action: { account.login() }
                    )

                    Button("注册") { account.register() }
                        .buttonStyle(UserCenterSecondaryButtonStyle())
                        .disabled(account.isBusy)
                        .frame(height: 36)
                }

                if !account.statusMessage.isEmpty {
                    Text(account.statusMessage)
                        .font(AhakeySettingsTheme.rowSubtitleFont)
                        .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Profile

    private var profileCard: some View {
        AhakeySettingsCard(sectionTitle: "账户") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 14) {
                    UserCenterAvatar(initial: account.avatarInitial, size: 44)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.phoneDisplay.isEmpty ? "已登录" : account.phoneDisplay)
                            .font(AhakeySettingsTheme.rowTitleFont)
                            .foregroundStyle(AhakeySettingsTheme.primaryText)
                            .textSelection(.enabled)
                        Text(account.validUntilDisplay.isEmpty ? "账户正常" : account.validUntilDisplay)
                            .font(AhakeySettingsTheme.rowSubtitleFont)
                            .foregroundStyle(AhakeySettingsTheme.secondaryText)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    UserCenterQuotaMetric(label: "每日", value: account.quotaText("daily"))
                    UserCenterQuotaMetric(label: "每周", value: account.quotaText("weekly"))
                    UserCenterQuotaMetric(label: "每月", value: account.quotaText("monthly"))
                }

                HStack(spacing: 10) {
                    UserCenterPrimaryButton(
                        title: "刷新资料",
                        isBusy: account.isBusy,
                        action: { account.refreshProfile() }
                    )
                    .frame(maxWidth: 140)

                    Button("切换账号") {
                        account.prepareForRelogin()
                        focusedLoginField = .phone
                    }
                    .buttonStyle(UserCenterSecondaryButtonStyle())
                    .disabled(account.isBusy)
                    .frame(height: 36)

                    Button("退出登录") { account.logout() }
                        .buttonStyle(UserCenterDangerButtonStyle())
                        .disabled(account.isBusy)
                        .frame(height: 36)
                }

                if !account.statusMessage.isEmpty {
                    Text(account.statusMessage)
                        .font(AhakeySettingsTheme.rowSubtitleFont)
                        .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Billing

    private var billingCard: some View {
        AhakeySettingsCard(sectionTitle: "订阅与充值") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    ForEach(CloudRechargePlan.allCases) { plan in
                        UserCenterPlanTile(
                            plan: plan,
                            priceText: account.priceText(for: plan),
                            isHovered: hoveredPlan == plan,
                            isDisabled: account.isBusy
                        ) {
                            account.createWechatOrder(plan: plan)
                        }
                        .onHover { hovering in
                            hoveredPlan = hovering ? plan : (hoveredPlan == plan ? nil : hoveredPlan)
                        }
                    }
                }

                if let order = account.paymentOrder {
                    paymentOrderBlock(order)
                }
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Coupon

    private var couponCard: some View {
        AhakeySettingsCard(sectionTitle: "免费券") {
            HStack(spacing: 10) {
                UserCenterFieldChrome {
                    TextField("", text: $account.couponCode, prompt: Text("输入兑换码").foregroundColor(AhakeySettingsTheme.tertiaryText))
                        .textFieldStyle(.plain)
                }

                Button("兑换") { account.redeemCoupon() }
                    .buttonStyle(UserCenterSecondaryButtonStyle())
                    .disabled(account.isBusy)
                    .frame(width: 72, height: 36)
            }
            .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
            .padding(.vertical, 14)
        }
    }

    // MARK: - AhaType

    private var ahaTypeCard: some View {
        AhakeySettingsCard(sectionTitle: "AhaType") {
            AhakeySettingsToggleRow(
                title: "启用云端整理",
                subtitle: account.isLoggedIn
                    ? "转写完成后经云端整理再粘贴；失败时回退原文。"
                    : "登录后可开启云端整理。",
                isOn: Binding(
                    get: { optimizer.isEnabled },
                    set: { enabled in
                        if enabled, !account.isLoggedIn {
                            account.alertMessage = "请先登录后再开启 AhaType 云端整理。"
                            return
                        }
                        optimizer.setEnabled(enabled)
                    }
                )
            )

            if !account.isLoggedIn {
                AhakeySettingsCardDivider()
                Text("去上方登录后即可开启")
                    .font(AhakeySettingsTheme.rowSubtitleFont)
                    .foregroundStyle(AhakeySettingsTheme.accentBlue)
                    .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
                    .padding(.vertical, 10)
            } else if !optimizer.statusMessage.isEmpty || !optimizer.lastQuotaSummary.isEmpty {
                AhakeySettingsCardDivider()
                VStack(alignment: .leading, spacing: 4) {
                    if !optimizer.statusMessage.isEmpty {
                        Text(optimizer.statusMessage)
                            .font(AhakeySettingsTheme.rowSubtitleFont)
                            .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                    }
                    if !optimizer.lastQuotaSummary.isEmpty {
                        Text(optimizer.lastQuotaSummary)
                            .font(.system(size: 11))
                            .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                    }
                }
                .padding(.horizontal, AhakeySettingsTheme.rowPaddingH)
                .padding(.vertical, 10)
            }
        }
    }

    @ViewBuilder
    private func paymentOrderBlock(_ order: CloudPaymentOrder) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                if let image = makeQRCodeImage(from: order.paymentURL) {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 120, height: 120)
                        .padding(8)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("\(order.plan.title) · \(order.amountText)")
                        .font(AhakeySettingsTheme.rowTitleFont)
                        .foregroundStyle(AhakeySettingsTheme.primaryText)
                    Text("微信扫码完成支付，成功后自动刷新额度")
                        .font(AhakeySettingsTheme.rowSubtitleFont)
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                    Text("订单 \(order.outTradeNo)")
                        .font(.system(size: 11))
                        .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                        .textSelection(.enabled)
                    Text("状态 \(order.status)")
                        .font(.system(size: 11))
                        .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                }
            }

            HStack(spacing: 8) {
                Button("复制链接") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(order.paymentURL, forType: .string)
                }
                .buttonStyle(UserCenterSecondaryButtonStyle())
                .frame(height: 32)

                Button("刷新到账") { account.refreshCurrentPaymentOrder() }
                    .buttonStyle(UserCenterSecondaryButtonStyle())
                    .disabled(account.isBusy)
                    .frame(height: 32)

                Button("关闭") { account.clearPaymentOrder() }
                    .buttonStyle(.plain)
                    .font(AhakeySettingsTheme.rowSubtitleFont)
                    .foregroundStyle(AhakeySettingsTheme.tertiaryText)
                    .frame(height: 32)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AhakeySettingsTheme.controlFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AhakeySettingsTheme.divider.opacity(0.9), lineWidth: 1)
        )
    }

    private func makeQRCodeImage(from text: String) -> NSImage? {
        guard let data = text.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let representation = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}

// MARK: - Private components

private struct UserCenterHero: View {
    let isLoggedIn: Bool
    let isBusy: Bool
    let title: String
    let subtitle: String
    let avatarInitial: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            UserCenterAvatar(initial: avatarInitial, size: 60)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(AhakeySettingsTheme.pageTitleFont)
                    .foregroundStyle(AhakeySettingsTheme.primaryText)
                    .lineLimit(1)

                Text(subtitle)
                    .font(AhakeySettingsTheme.rowSubtitleFont)
                    .foregroundStyle(AhakeySettingsTheme.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if isBusy {
                ProgressView()
                    .controlSize(.small)
            } else if isLoggedIn {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 0.35, green: 0.82, blue: 0.48))
                        .frame(width: 7, height: 7)
                    Text("已登录")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AhakeySettingsTheme.secondaryText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(AhakeySettingsTheme.controlFill)
                )
            }
        }
        .padding(.vertical, 4)
    }
}

private struct UserCenterAvatar: View {
    let initial: String
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.85), AhakeySettingsTheme.accentBlue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(initial)
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

private struct UserCenterLabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AhakeySettingsTheme.rowSubtitleFont)
                .foregroundStyle(AhakeySettingsTheme.secondaryText)
            UserCenterFieldChrome(content: content)
        }
    }
}

private struct UserCenterFieldChrome<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .font(AhakeySettingsTheme.rowTitleFont)
            .foregroundStyle(AhakeySettingsTheme.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AhakeySettingsTheme.controlFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AhakeySettingsTheme.divider.opacity(0.95), lineWidth: 1)
            )
    }
}

private struct UserCenterQuotaMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AhakeySettingsTheme.tertiaryText)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AhakeySettingsTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AhakeySettingsTheme.controlFill)
        )
    }
}

private struct UserCenterPlanTile: View {
    let plan: CloudRechargePlan
    let priceText: String
    let isHovered: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(plan.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AhakeySettingsTheme.primaryText)
                Text(priceText)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AhakeySettingsTheme.accentBlue)
                Text(plan.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(AhakeySettingsTheme.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AhakeySettingsTheme.controlFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isHovered ? AhakeySettingsTheme.accentBlue.opacity(0.55) : AhakeySettingsTheme.divider.opacity(0.9),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
    }
}

private struct UserCenterPrimaryButton: View {
    let title: String
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AhakeySettingsTheme.accentBlue.opacity(isBusy ? 0.7 : 1))
            )
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }
}

private struct UserCenterSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(AhakeySettingsTheme.primaryText)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AhakeySettingsTheme.controlFill)
                    .opacity(configuration.isPressed ? 0.75 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AhakeySettingsTheme.divider, lineWidth: 1)
            )
    }
}

private struct UserCenterDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(AhakeySettingsTheme.dangerText)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AhakeySettingsTheme.controlFill.opacity(configuration.isPressed ? 0.75 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AhakeySettingsTheme.dangerText.opacity(0.35), lineWidth: 1)
            )
    }
}
