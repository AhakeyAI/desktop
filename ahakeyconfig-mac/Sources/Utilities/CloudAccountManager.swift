import Foundation
import os.log
import AhaKeyConfigShared

private let cloudAccountLog = Logger(subsystem: "lab.jawa.ahakeyconfig", category: "CloudAccount")

@MainActor
final class CloudAccountManager: ObservableObject {
    static let shared = CloudAccountManager()

    @Published var phone = ""
    @Published var password = ""
    @Published var rememberPassword = false
    @Published var couponCode = ""
    @Published private(set) var isLoggedIn = false
    @Published private(set) var isBusy = false
    @Published private(set) var profile: [String: Any]?
    @Published private(set) var paymentOrder: CloudPaymentOrder?
    @Published private(set) var statusMessage = NSLocalizedString("尚未登录。", comment: "")
    @Published var alertMessage: String?

    private let fallbackAPIBase = "https://956798.xyz/prod-api"
    private let rememberKey = "lab.jawa.ahakeyconfig.cloud.remember"
    private let phoneKey = "lab.jawa.ahakeyconfig.cloud.phone"

    // 历史遗留：这些 Key 的值已迁移到钥匙串，保留 Key 仅用于一次性迁移。
    private let legacyTokenKey = "lab.jawa.ahakeyconfig.cloud.accessToken"
    private let legacyPasswordKey = "lab.jawa.ahakeyconfig.cloud.password"

    private let keychainService = "lab.jawa.ahakeyconfig.cloud"
    private enum KeychainAccount {
        static let accessToken = "accessToken"
        static let password = "password"
    }

    private init() {
        let defaults = UserDefaults.standard
        rememberPassword = defaults.bool(forKey: rememberKey)
        phone = defaults.string(forKey: phoneKey) ?? ""
        if rememberPassword,
           let savedPassword = AhaKeyKeychain.load(service: keychainService, account: KeychainAccount.password) {
            password = savedPassword
        }

        // 一次性迁移：旧版本 UserDefaults 中的 token / 密码迁移到钥匙串后清除旧值。
        if let legacyToken = defaults.string(forKey: legacyTokenKey), !legacyToken.isEmpty {
            try? AhaKeyKeychain.save(service: keychainService, account: KeychainAccount.accessToken, value: legacyToken)
            defaults.removeObject(forKey: legacyTokenKey)
        }
        if rememberPassword,
           let legacyPassword = defaults.string(forKey: legacyPasswordKey), !legacyPassword.isEmpty {
            try? AhaKeyKeychain.save(service: keychainService, account: KeychainAccount.password, value: legacyPassword)
            defaults.removeObject(forKey: legacyPasswordKey)
        }

        isLoggedIn = !accessToken.isEmpty
        if isLoggedIn {
            statusMessage = NSLocalizedString("已登录，等待刷新用户信息。", comment: "")
        }
    }

    func login() {
        authenticate(path: "api/v1/auth/login", successMessage: NSLocalizedString("登录成功。", comment: ""), fallbackError: NSLocalizedString("登录失败。", comment: ""))
    }

    func register() {
        authenticate(path: "api/v1/auth/register", successMessage: NSLocalizedString("注册成功。", comment: ""), fallbackError: NSLocalizedString("注册失败。", comment: ""))
    }

    func logout() {
        AhaKeyKeychain.delete(service: keychainService, account: KeychainAccount.accessToken)
        AhaKeyKeychain.delete(service: keychainService, account: KeychainAccount.password)
        AhaTypeTextOptimizer.shared.clearSessionKeepToggle()
        profile = nil
        isLoggedIn = false
        statusMessage = NSLocalizedString("已退出登录。", comment: "")
    }

    func prepareForRelogin() {
        AhaKeyKeychain.delete(service: keychainService, account: KeychainAccount.accessToken)
        profile = nil
        isLoggedIn = false
        statusMessage = NSLocalizedString("请输入账号密码重新登录。", comment: "")
    }

    /// retryDelays 非空时按给定间隔（秒）做有限重试（登录后/启动拉取用），最终失败给出明确提示。
    func refreshProfile(showAlertOnFailure: Bool = true,
                        forceRefresh: Bool = true,
                        successMessage: String = NSLocalizedString("用户信息已刷新。", comment: ""),
                        retryDelays: [TimeInterval] = []) {
        guard !accessToken.isEmpty else {
            logout()
            return
        }
        isBusy = true
        statusMessage = NSLocalizedString("正在刷新用户信息…", comment: "")
        Task {
            defer { Task { @MainActor in self.isBusy = false } }
            var attempt = 0
            while true {
                attempt += 1
                cloudAccountLog.info("refreshProfile 开始（第 \(attempt) 次尝试）")
                do {
                    let object = try await request(
                        path: cacheBustedPath("api/v1/auth/users/me", enabled: forceRefresh),
                        method: "GET",
                        body: nil,
                        authorized: true,
                        bypassCache: forceRefresh
                    )
                    let data = try payloadData(from: object, fallbackError: NSLocalizedString("获取用户信息失败", comment: ""))
                    guard QuotaProfileNormalizer.normalize(data).recognizedAnyField else {
                        cloudAccountLog.warning("refreshProfile 返回数据未识别到任何已知字段，视为拉取失败")
                        throw CloudAccountError(NSLocalizedString("云端返回的用户信息缺少可识别字段。", comment: ""))
                    }
                    await MainActor.run {
                        self.applyProfile(data)
                        self.statusMessage = successMessage
                    }
                    cloudAccountLog.info("refreshProfile 成功（第 \(attempt) 次尝试）")
                    return
                } catch {
                    let statusCode = (error as? CloudAccountError)?.statusCode
                    cloudAccountLog.error("refreshProfile 失败（第 \(attempt) 次尝试，HTTP \(statusCode ?? -1)）：\(error.localizedDescription)")
                    // 401 任何路径都退出登录，不再停留在假登录态。
                    if statusCode == 401 {
                        cloudAccountLog.warning("refreshProfile 收到 401，退出登录")
                        await MainActor.run {
                            self.logout()
                            self.statusMessage = NSLocalizedString("登录已过期，请重新登录。", comment: "")
                        }
                        return
                    }
                    if attempt <= retryDelays.count {
                        let delay = retryDelays[attempt - 1]
                        cloudAccountLog.info("refreshProfile 将于 \(delay)s 后重试")
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        continue
                    }
                    await MainActor.run {
                        if showAlertOnFailure {
                            self.alertMessage = error.localizedDescription
                            self.statusMessage = NSLocalizedString("刷新失败。", comment: "")
                        } else if retryDelays.isEmpty {
                            self.statusMessage = NSLocalizedString("已登录，用户信息稍后可刷新。", comment: "")
                        } else {
                            self.statusMessage = NSLocalizedString("配额拉取失败，请打开云端账号手动刷新。", comment: "")
                        }
                    }
                    return
                }
            }
        }
    }

    func redeemCoupon() {
        let code = couponCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            alertMessage = NSLocalizedString("请输入兑换码。", comment: "")
            return
        }
        isBusy = true
        statusMessage = NSLocalizedString("正在兑换免费券…", comment: "")
        Task {
            defer { Task { @MainActor in self.isBusy = false } }
            do {
                let object = try await request(path: "api/v1/coupon/redeem", method: "POST", body: ["code": code], authorized: true)
                let data = try payloadData(from: object, fallbackError: NSLocalizedString("兑换失败", comment: ""))
                await MainActor.run {
                    self.couponCode = ""
                    self.applyProfile(data)
                    self.statusMessage = NSLocalizedString("兑换成功。", comment: "")
                    self.alertMessage = NSLocalizedString("免费券已生效。", comment: "")
                }
            } catch {
                await MainActor.run {
                    self.alertMessage = error.localizedDescription
                    self.statusMessage = NSLocalizedString("兑换失败。", comment: "")
                }
            }
        }
    }

    func createWechatOrder(plan: CloudRechargePlan) {
        guard isLoggedIn else {
            alertMessage = NSLocalizedString("请先登录后再充值。", comment: "")
            return
        }
        isBusy = true
        statusMessage = NSLocalizedString("正在创建微信支付订单…", comment: "")
        Task {
            defer { Task { @MainActor in self.isBusy = false } }
            do {
                let object = try await request(
                    path: "api/v1/payment/wechat/native",
                    method: "POST",
                    body: ["plan": plan.rawValue, "description": plan.orderDescription],
                    authorized: true
                )
                let data = try payloadData(from: object, fallbackError: NSLocalizedString("创建支付订单失败", comment: ""))
                let codeURL = firstString(in: data, keys: ["code_url", "codeUrl"])
                let h5URL = firstString(in: data, keys: ["h5_url", "h5Url", "mweb_url", "mwebUrl"])
                let outTradeNo = firstString(in: data, keys: ["out_trade_no", "outTradeNo"])
                guard !outTradeNo.isEmpty else { throw CloudAccountError(NSLocalizedString("云端未返回订单号，无法查询支付状态。", comment: "")) }
                guard !codeURL.isEmpty || !h5URL.isEmpty else { throw CloudAccountError(NSLocalizedString("云端未返回可支付链接。", comment: "")) }
                let amountFen = firstInt(in: data, keys: ["amount_fen", "amountFen"])
                await MainActor.run {
                    self.paymentOrder = CloudPaymentOrder(
                        plan: plan,
                        amountFen: amountFen,
                        outTradeNo: outTradeNo,
                        codeURL: codeURL,
                        h5URL: h5URL,
                        status: "pending"
                    )
                    self.statusMessage = NSLocalizedString("订单已创建，请使用微信扫码支付。", comment: "")
                    self.pollPaymentStatus(outTradeNo: outTradeNo)
                }
            } catch {
                await MainActor.run {
                    if (error as? CloudAccountError)?.statusCode == 401 {
                        // 会话已失效：登出回到登录界面，不再停留在"点了订阅只弹请先登录"的假登录态。
                        self.logout()
                        self.alertMessage = NSLocalizedString("登录已过期，请重新登录。", comment: "")
                    } else {
                        self.alertMessage = error.localizedDescription
                    }
                    self.statusMessage = NSLocalizedString("创建支付订单失败。", comment: "")
                }
            }
        }
    }

    func clearPaymentOrder() {
        paymentOrder = nil
        statusMessage = NSLocalizedString("已关闭支付订单。", comment: "")
    }

    func refreshCurrentPaymentOrder() {
        guard let order = paymentOrder else {
            refreshProfile()
            return
        }
        isBusy = true
        statusMessage = NSLocalizedString("正在查询订单状态…", comment: "")
        Task {
            defer { Task { @MainActor in self.isBusy = false } }
            do {
                let data = try await fetchPaymentStatus(outTradeNo: order.outTradeNo)
                await MainActor.run {
                    _ = self.applyPaymentStatus(data, outTradeNo: order.outTradeNo, notifyPending: true)
                }
            } catch {
                await MainActor.run {
                    self.alertMessage = error.localizedDescription
                    self.statusMessage = NSLocalizedString("订单状态查询失败。", comment: "")
                }
            }
        }
    }

    var profileSummary: String {
        guard let profile else { return isLoggedIn ? NSLocalizedString("已登录，点击刷新获取用户信息。", comment: "") : NSLocalizedString("登录后可启用 AhaType 云端整理。", comment: "") }
        let phone = stringValue(profile["phone"])
        let validUntil = stringValue(profile["token_valid_until"])
        return [
            phone.isEmpty ? "" : String(format: NSLocalizedString("手机号：%@", comment: ""), phone),
            validUntil.isEmpty ? NSLocalizedString("有效期：无", comment: "") : String(format: NSLocalizedString("有效期：%@", comment: ""), validUntil),
        ].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    func quotaText(_ period: String) -> String {
        guard let profile else { return NSLocalizedString("暂无", comment: "") }
        let used = intValue(profile["used_\(period)"])
        let limit = intValue(profile["limit_\(period)"])
        if limit <= 0 {
            return used > 0 ? String(format: NSLocalizedString("已用 %d · 无上限", comment: ""), used) : NSLocalizedString("暂无", comment: "")
        }
        // 展示 剩余/额度：剩余 = limit - used，下限钳到 0。
        return "\(max(0, limit - used)) / \(limit)"
    }

    /// 当期剩余额度：优先月度（limit_monthly - used_monthly），月度字段缺失时退而取每周/每日。
    /// 常驻展示：profile 未加载或没有任何可用周期时显示 "0"（未充值即 0）。只显示剩余数值，不带总额度。
    var remainingQuotaText: String {
        guard let profile else { return "0" }
        for period in ["monthly", "weekly", "daily"] {
            guard let rawLimit = profile["limit_\(period)"], !(rawLimit is NSNull) else { continue }
            let limit = intValue(rawLimit)
            guard limit > 0 else { continue }
            let used = intValue(profile["used_\(period)"])
            return "\(max(0, limit - used))"
        }
        return "0"
    }

    /// 余额展示：仅当 profile 识别到余额字段时返回值，没有就不渲染该行。
    /// 余额单位待后端确认，这里原值透传不换算。
    var balanceText: String? {
        guard let profile else { return nil }
        for key in ["token_balance", "typeless_balance", "balance"] {
            if let value = profile[key], !(value is NSNull) {
                let text = stringValue(value)
                if !text.isEmpty { return text }
            }
        }
        return nil
    }

    func priceText(for plan: CloudRechargePlan) -> String {
        let fallback = plan.fallbackAmountFen
        guard let prices = (profile?["policy"] as? [String: Any])?["recharge_prices_fen"] as? [String: Any] else {
            return formatFen(fallback)
        }
        let amount = intValue(prices[plan.rawValue])
        return formatFen(amount > 0 ? amount : fallback)
    }

    private func pollPaymentStatus(outTradeNo: String) {
        Task {
            let deadline = Date().addingTimeInterval(180)
            while Date() < deadline {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if self.paymentOrder?.outTradeNo != outTradeNo { return }
                do {
                    let data = try await fetchPaymentStatus(outTradeNo: outTradeNo)
                    let finished = await MainActor.run {
                        self.applyPaymentStatus(data, outTradeNo: outTradeNo, notifyPending: false)
                    }
                    if finished {
                        return
                    }
                } catch {
                    // 轮询中允许单次失败，避免网络抖动中断支付流程。
                    continue
                }
            }
            await MainActor.run {
                if self.paymentOrder?.outTradeNo == outTradeNo {
                    self.statusMessage = NSLocalizedString("等待支付超时，可稍后刷新用户信息确认到账。", comment: "")
                }
            }
        }
    }

    private func fetchPaymentStatus(outTradeNo: String) async throws -> [String: Any] {
        let encoded = outTradeNo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? outTradeNo
        let path = cacheBustedPath("api/v1/payment/wechat/order-status?outTradeNo=\(encoded)", enabled: true)
        let object = try await request(
            path: path,
            method: "GET",
            body: nil,
            authorized: true,
            bypassCache: true
        )
        let data = try payloadData(from: object, fallbackError: NSLocalizedString("查询订单状态失败", comment: ""))
        return data
    }

    @discardableResult
    private func applyPaymentStatus(_ data: [String: Any], outTradeNo: String, notifyPending: Bool) -> Bool {
        let status = normalizedPaymentStatus(from: data)
        let normalized = status.isEmpty ? "pending" : status
        if var order = paymentOrder, order.outTradeNo == outTradeNo {
            order.status = normalized
            paymentOrder = order
        }
        if isPaidPaymentStatus(normalized) {
            statusMessage = NSLocalizedString("充值成功，正在刷新额度。", comment: "")
            paymentOrder = nil
            // 服务端在订单 paid 时已返回最新 profile，直接用；否则回退到独立刷新。
            if let profileFromServer = data["profile"] as? [String: Any] {
                applyProfile(profileFromServer)
                statusMessage = NSLocalizedString("充值到账已刷新。", comment: "")
            } else {
                refreshProfile(
                    forceRefresh: true,
                    successMessage: NSLocalizedString("充值到账已刷新。", comment: "")
                )
            }
            return true
        }
        if isFailedPaymentStatus(normalized) {
            statusMessage = NSLocalizedString("订单支付失败。", comment: "")
            alertMessage = NSLocalizedString("订单已标记为失败，请重新发起充值。", comment: "")
            return true
        }
        statusMessage = NSLocalizedString("订单尚未到账，请稍后再刷新。", comment: "")
        if notifyPending {
            alertMessage = NSLocalizedString("当前订单仍未到账，请确认微信支付已完成后再刷新。", comment: "")
        }
        return false
    }

    private func authenticate(path: String, successMessage: String, fallbackError: String) {
        let p = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty, !password.isEmpty else {
            alertMessage = NSLocalizedString("请输入手机号和密码。", comment: "")
            return
        }
        isBusy = true
        statusMessage = NSLocalizedString("正在请求云端账号…", comment: "")
        Task {
            defer { Task { @MainActor in self.isBusy = false } }
            do {
                let object = try await request(path: path, method: "POST", body: ["phone": p, "password": password], authorized: false)
                let data = try payloadData(from: object, fallbackError: fallbackError)
                let token = firstString(in: data, keys: ["access_token", "token"])
                guard !token.isEmpty else { throw CloudAccountError(NSLocalizedString("云端未返回 access_token。", comment: "")) }
                await MainActor.run {
                    self.saveLogin(token: token, authData: data)
                    self.statusMessage = successMessage
                }
                cloudAccountLog.info("云端账号认证成功（\(path)）")
                // 登录后静默拉 profile，失败做有限重试，不再无声。
                await MainActor.run {
                    self.refreshProfile(showAlertOnFailure: false, retryDelays: [2, 5, 10])
                }
            } catch {
                cloudAccountLog.error("云端账号认证失败（\(path)）：\(error.localizedDescription)")
                await MainActor.run {
                    self.alertMessage = error.localizedDescription
                    self.statusMessage = NSLocalizedString("账号请求失败。", comment: "")
                }
            }
        }
    }

    private func saveLogin(token: String, authData: [String: Any] = [:]) {
        let defaults = UserDefaults.standard
        try? AhaKeyKeychain.save(service: keychainService, account: KeychainAccount.accessToken, value: token)
        defaults.set(rememberPassword, forKey: rememberKey)
        defaults.set(phone.trimmingCharacters(in: .whitespacesAndNewlines), forKey: phoneKey)
        if rememberPassword {
            try? AhaKeyKeychain.save(service: keychainService, account: KeychainAccount.password, value: password)
        } else {
            AhaKeyKeychain.delete(service: keychainService, account: KeychainAccount.password)
        }
        // 清除可能残留的 UserDefaults 敏感值。
        defaults.removeObject(forKey: legacyTokenKey)
        defaults.removeObject(forKey: legacyPasswordKey)
        AhaTypeTextOptimizer.shared.patchCloudToken(token)
        seedLocalProfile(token: token, authData: authData)
        isLoggedIn = true
    }

    /// 返回是否真正应用了 profile：标准化后一个可识别字段都没有时视为拉取失败，
    /// 保留旧 profile，不再存空 profile（避免 UI 全显示"暂无"）。
    @discardableResult
    private func applyProfile(_ profile: [String: Any]) -> Bool {
        let result = QuotaProfileNormalizer.normalize(profile)
        guard result.recognizedAnyField else {
            cloudAccountLog.warning("applyProfile 未识别到任何已知字段，保留旧 profile")
            return false
        }
        var normalized = result.profile
        if stringValue(normalized["token_valid_until"]).isEmpty, let validUntil = jwtExpirationString(accessToken) {
            normalized["token_valid_until"] = validUntil
        }
        if let balanceKey = result.balanceKey {
            cloudAccountLog.info("profile 命中余额字段：\(balanceKey)")
        }
        self.profile = normalized
        isLoggedIn = true
        AhaTypeTextOptimizer.shared.patchCloudToken(accessToken)
        AhaTypeTextOptimizer.shared.setUserProfile(normalized)
        return true
    }

    private func seedLocalProfile(token: String, authData: [String: Any]) {
        var profile = normalizedProfile(authData)
        let phoneValue = firstString(in: authData, keys: ["phone", "mobile", "username"])
        profile["phone"] = phoneValue.isEmpty ? phone.trimmingCharacters(in: .whitespacesAndNewlines) : phoneValue
        let userID = firstString(in: authData, keys: ["id", "user_id", "userId"])
        if !userID.isEmpty {
            profile["user_id"] = userID
            profile["id"] = userID
        }
        if let validUntil = jwtExpirationString(token) {
            profile["token_valid_until"] = validUntil
        }
        self.profile = profile
        AhaTypeTextOptimizer.shared.setUserProfile(profile)
    }

    private func normalizedProfile(_ raw: [String: Any]) -> [String: Any] {
        var profile = QuotaProfileNormalizer.normalize(raw).profile
        if stringValue(profile["token_valid_until"]).isEmpty, let validUntil = jwtExpirationString(accessToken) {
            profile["token_valid_until"] = validUntil
        }
        return profile
    }

    private func request(path: String,
                         method: String,
                         body: [String: Any]?,
                         authorized: Bool,
                         bypassCache: Bool = false) async throws -> [String: Any] {
        guard let url = URL(string: "\(apiBase)/\(path)") else {
            throw CloudAccountError(NSLocalizedString("云端地址无效。", comment: ""))
        }
        var request = URLRequest(url: url, timeoutInterval: 90)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if bypassCache {
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("no-cache, no-store, max-age=0", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        }
        if authorized {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CloudAccountError(networkMessage(for: error))
        }
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudAccountError(NSLocalizedString("服务器返回非 JSON。", comment: ""), statusCode: statusCode)
        }
        if statusCode != 200 {
            throw CloudAccountError(responseMessage(object).isEmpty ? String(format: NSLocalizedString("请求失败（HTTP %d）。", comment: ""), statusCode) : responseMessage(object), statusCode: statusCode)
        }
        return object
    }

    private func cacheBustedPath(_ path: String, enabled: Bool) -> String {
        guard enabled else { return path }
        let separator = path.contains("?") ? "&" : "?"
        return "\(path)\(separator)_refresh=\(UUID().uuidString)"
    }

    private func payloadData(from object: [String: Any], fallbackError: String) throws -> [String: Any] {
        let code = intValue(object["code"])
        guard code == 0 || code == 200 else {
            let msg = responseMessage(object)
            // 后端把鉴权失败包在 HTTP 200 里返回（如 {"code":500,"data":401,"msg":"未登录或Token无效"}），
            // 映射为 statusCode 401，让 refreshProfile 的统一 401 登出逻辑真正生效。
            let authFailed = code == 401 || intValue(object["data"]) == 401
            throw CloudAccountError(msg.isEmpty ? fallbackError : msg, statusCode: authFailed ? 401 : nil)
        }
        return object["data"] as? [String: Any] ?? [:]
    }

    private var accessToken: String {
        AhaKeyKeychain.load(service: keychainService, account: KeychainAccount.accessToken) ?? ""
    }

    private var apiBase: String {
        for key in ["VIBE_TYPELESS_API_BASE", "VIBE_API_BASE"] {
            let v = normalizeAPIBase(ProcessInfo.processInfo.environment[key] ?? "")
            if !v.isEmpty { return v }
        }
        return normalizeAPIBase(fallbackAPIBase)
    }

    private func normalizeAPIBase(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        if !value.isEmpty, !value.contains("://") {
            value = "https://\(value)"
        }
        return value
    }

    private func stringValue(_ value: Any?) -> String {
        switch value {
        case let string as String: return string
        case let number as NSNumber: return number.stringValue
        default: return ""
        }
    }

    private func firstString(in object: [String: Any], keys: [String]) -> String {
        for key in keys {
            let value = stringValue(object[key]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return ""
    }

    private func firstInt(in object: [String: Any], keys: [String]) -> Int {
        for key in keys {
            let value = intValue(object[key])
            if value != 0 { return value }
        }
        return 0
    }

    private func normalizedPaymentStatus(from data: [String: Any]) -> String {
        firstString(in: data, keys: ["status", "tradeState", "trade_state", "payStatus", "pay_status", "orderStatus", "order_status"])
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
    }

    private func isPaidPaymentStatus(_ status: String) -> Bool {
        let normalized = status.lowercased().replacingOccurrences(of: "-", with: "_")
        return [
            "paid",
            "success",
            "succeeded",
            "complete",
            "completed",
            "pay_success",
            "trade_success",
            "wechat_success",
            "finished",
            "done",
            "1",
        ].contains(normalized)
    }

    private func isFailedPaymentStatus(_ status: String) -> Bool {
        let normalized = status.lowercased().replacingOccurrences(of: "-", with: "_")
        return [
            "failed",
            "failure",
            "fail",
            "closed",
            "cancelled",
            "canceled",
            "expired",
            "timeout",
            "trade_closed",
            "pay_error",
            "2",
        ].contains(normalized)
    }

    private func responseMessage(_ object: [String: Any]) -> String {
        firstString(in: object, keys: ["errorMsg", "msg", "message", "error"])
    }

    private func jwtExpirationString(_ token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let exp = Double(intValue(object["exp"]))
        guard exp > 0 else { return nil }
        let date = Date(timeIntervalSince1970: exp)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private func intValue(_ value: Any?) -> Int {
        switch value {
        case let int as Int: return int
        case let number as NSNumber: return number.intValue
        case let string as String: return Int(string) ?? 0
        default: return 0
        }
    }

    private func formatFen(_ fen: Int) -> String {
        String(format: NSLocalizedString("%.2f 元", comment: ""), Double(max(0, fen)) / 100.0)
    }

    private func networkMessage(for error: Error) -> String {
        guard let urlError = error as? URLError else {
            return String(format: NSLocalizedString("云端连接失败：%@", comment: ""), error.localizedDescription)
        }
        switch urlError.code {
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected, .clientCertificateRequired:
            return NSLocalizedString("云端连接失败：TLS/SSL 校验未通过，请检查系统时间、网络代理/证书，或确认云端 HTTPS 证书配置正常。", comment: "")
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet, .networkConnectionLost, .timedOut:
            return NSLocalizedString("云端连接失败：当前网络无法访问 AhaType 服务，请检查网络后重试。", comment: "")
        default:
            return String(format: NSLocalizedString("云端连接失败：%@", comment: ""), urlError.localizedDescription)
        }
    }
}

struct CloudAccountError: LocalizedError {
    let message: String
    let statusCode: Int?

    init(_ message: String, statusCode: Int? = nil) {
        self.message = message
        self.statusCode = statusCode
    }

    var errorDescription: String? { message }
}

enum CloudRechargePlan: String, CaseIterable, Identifiable {
    case monthly
    case quarterly
    case yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthly: return NSLocalizedString("按月订阅", comment: "")
        case .quarterly: return NSLocalizedString("按季订阅", comment: "")
        case .yearly: return NSLocalizedString("按年订阅", comment: "")
        }
    }

    var subtitle: String {
        switch self {
        case .monthly: return NSLocalizedString("30 天", comment: "")
        case .quarterly: return NSLocalizedString("90 天", comment: "")
        case .yearly: return NSLocalizedString("365 天", comment: "")
        }
    }

    var orderDescription: String {
        switch self {
        case .monthly: return NSLocalizedString("包月充值", comment: "")
        case .quarterly: return NSLocalizedString("包季充值", comment: "")
        case .yearly: return NSLocalizedString("包年充值", comment: "")
        }
    }

    var fallbackAmountFen: Int {
        switch self {
        case .monthly: return 100
        case .quarterly: return 270
        case .yearly: return 999
        }
    }
}

struct CloudPaymentOrder: Equatable {
    let plan: CloudRechargePlan
    let amountFen: Int
    let outTradeNo: String
    let codeURL: String
    let h5URL: String
    var status: String

    var paymentURL: String {
        codeURL.isEmpty ? h5URL : codeURL
    }

    var amountText: String {
        String(format: NSLocalizedString("%.2f 元", comment: ""), Double(max(0, amountFen)) / 100.0)
    }
}
