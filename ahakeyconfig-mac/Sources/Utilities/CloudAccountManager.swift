import Foundation

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
    @Published private(set) var statusMessage = "尚未登录。"
    @Published var alertMessage: String?

    private let fallbackAPIBase = "https://typeless-220629-6-1398334410.sh.run.tcloudbase.com"
    private let tokenKey = "lab.jawa.ahakeyconfig.cloud.accessToken"
    private let rememberKey = "lab.jawa.ahakeyconfig.cloud.remember"
    private let phoneKey = "lab.jawa.ahakeyconfig.cloud.phone"
    private let passwordKey = "lab.jawa.ahakeyconfig.cloud.password"

    private init() {
        let defaults = UserDefaults.standard
        rememberPassword = defaults.bool(forKey: rememberKey)
        phone = defaults.string(forKey: phoneKey) ?? ""
        if rememberPassword {
            password = defaults.string(forKey: passwordKey) ?? ""
        }
        isLoggedIn = !accessToken.isEmpty
        if isLoggedIn {
            statusMessage = "已登录，等待刷新用户信息。"
        }
    }

    func login() {
        authenticate(path: "api/v1/auth/login", successMessage: "登录成功。")
    }

    func register() {
        authenticate(path: "api/v1/auth/register", successMessage: "注册成功。")
    }

    func logout() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
        AhaTypeTextOptimizer.shared.clearSessionKeepToggle()
        profile = nil
        isLoggedIn = false
        statusMessage = "已退出登录。"
    }

    func prepareForRelogin() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
        profile = nil
        isLoggedIn = false
        statusMessage = "请输入账号密码重新登录。"
    }

    func refreshProfile() {
        guard !accessToken.isEmpty else {
            logout()
            return
        }
        isBusy = true
        statusMessage = "正在刷新用户信息…"
        Task {
            defer { Task { @MainActor in self.isBusy = false } }
            do {
                let object = try await request(path: "api/v1/users/me", method: "GET", body: nil, authorized: true)
                let data = try payloadData(from: object, fallbackError: "获取用户信息失败")
                await MainActor.run {
                    self.applyProfile(data)
                    self.statusMessage = "用户信息已刷新。"
                }
            } catch {
                await MainActor.run {
                    self.alertMessage = error.localizedDescription
                    self.statusMessage = "刷新失败。"
                    if (error as? CloudAccountError)?.statusCode == 401 {
                        self.logout()
                    }
                }
            }
        }
    }

    func redeemCoupon() {
        let code = couponCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            alertMessage = "请输入兑换码。"
            return
        }
        isBusy = true
        statusMessage = "正在兑换免费券…"
        Task {
            defer { Task { @MainActor in self.isBusy = false } }
            do {
                let object = try await request(path: "api/v1/coupon/redeem", method: "POST", body: ["code": code], authorized: true)
                let data = try payloadData(from: object, fallbackError: "兑换失败")
                await MainActor.run {
                    self.couponCode = ""
                    self.applyProfile(data)
                    self.statusMessage = "兑换成功。"
                    self.alertMessage = "免费券已生效。"
                }
            } catch {
                await MainActor.run {
                    self.alertMessage = error.localizedDescription
                    self.statusMessage = "兑换失败。"
                }
            }
        }
    }

    func createWechatOrder(plan: CloudRechargePlan) {
        guard isLoggedIn else {
            alertMessage = "请先登录后再充值。"
            return
        }
        isBusy = true
        statusMessage = "正在创建微信支付订单…"
        Task {
            defer { Task { @MainActor in self.isBusy = false } }
            do {
                let object = try await request(
                    path: "api/v1/payment/wechat/native",
                    method: "POST",
                    body: ["plan": plan.rawValue, "description": plan.orderDescription],
                    authorized: true
                )
                let data = try payloadData(from: object, fallbackError: "创建支付订单失败")
                let codeURL = stringValue(data["code_url"])
                let h5URL = stringValue(data["h5_url"])
                let outTradeNo = stringValue(data["out_trade_no"])
                guard !outTradeNo.isEmpty else { throw CloudAccountError("云端未返回订单号，无法查询支付状态。") }
                guard !codeURL.isEmpty || !h5URL.isEmpty else { throw CloudAccountError("云端未返回可支付链接。") }
                let amountFen = intValue(data["amount_fen"])
                await MainActor.run {
                    self.paymentOrder = CloudPaymentOrder(
                        plan: plan,
                        amountFen: amountFen,
                        outTradeNo: outTradeNo,
                        codeURL: codeURL,
                        h5URL: h5URL,
                        status: "pending"
                    )
                    self.statusMessage = "订单已创建，请使用微信扫码支付。"
                    self.pollPaymentStatus(outTradeNo: outTradeNo)
                }
            } catch {
                await MainActor.run {
                    self.alertMessage = error.localizedDescription
                    self.statusMessage = "创建支付订单失败。"
                }
            }
        }
    }

    func clearPaymentOrder() {
        paymentOrder = nil
        statusMessage = "已关闭支付订单。"
    }

    var profileSummary: String {
        guard let profile else { return isLoggedIn ? "已登录，点击刷新获取用户信息。" : "登录后可启用 AhaType 云端整理。" }
        let phone = stringValue(profile["phone"])
        let validUntil = stringValue(profile["token_valid_until"])
        return [
            phone.isEmpty ? "" : "手机号：\(phone)",
            validUntil.isEmpty ? "有效期：无" : "有效期：\(validUntil)",
        ].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    func quotaText(_ period: String) -> String {
        guard let profile else { return "暂无" }
        let used = intValue(profile["used_\(period)"])
        let limit = intValue(profile["limit_\(period)"])
        if limit <= 0 {
            return used > 0 ? "已用 \(used) · 无上限" : "暂无"
        }
        return "\(used) / \(limit)"
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
                    let path = "api/v1/payment/wechat/order-status?out_trade_no=\(outTradeNo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? outTradeNo)"
                    let object = try await request(path: path, method: "GET", body: nil, authorized: true)
                    let data = try payloadData(from: object, fallbackError: "查询订单状态失败")
                    let status = stringValue(data["status"]).lowercased()
                    await MainActor.run {
                        if var order = self.paymentOrder, order.outTradeNo == outTradeNo {
                            order.status = status.isEmpty ? order.status : status
                            self.paymentOrder = order
                        }
                    }
                    if status == "paid" {
                        await MainActor.run {
                            self.statusMessage = "充值成功，正在刷新额度。"
                            self.paymentOrder = nil
                            self.refreshProfile()
                        }
                        return
                    }
                    if status == "failed" {
                        await MainActor.run {
                            self.statusMessage = "订单支付失败。"
                            self.alertMessage = "订单已标记为失败，请重新发起充值。"
                        }
                        return
                    }
                } catch {
                    // 轮询中允许单次失败，避免网络抖动中断支付流程。
                    continue
                }
            }
            await MainActor.run {
                if self.paymentOrder?.outTradeNo == outTradeNo {
                    self.statusMessage = "等待支付超时，可稍后刷新用户信息确认到账。"
                }
            }
        }
    }

    private func authenticate(path: String, successMessage: String) {
        let p = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty, !password.isEmpty else {
            alertMessage = "请输入手机号和密码。"
            return
        }
        isBusy = true
        statusMessage = "正在请求云端账号…"
        Task {
            defer { Task { @MainActor in self.isBusy = false } }
            do {
                let object = try await request(path: path, method: "POST", body: ["phone": p, "password": password], authorized: false)
                let data = try payloadData(from: object, fallbackError: successMessage)
                let token = stringValue(data["access_token"])
                guard !token.isEmpty else { throw CloudAccountError("云端未返回 access_token。") }
                await MainActor.run {
                    self.saveLogin(token: token)
                    self.statusMessage = successMessage
                }
                await MainActor.run {
                    self.refreshProfile()
                }
            } catch {
                await MainActor.run {
                    self.alertMessage = error.localizedDescription
                    self.statusMessage = "账号请求失败。"
                }
            }
        }
    }

    private func saveLogin(token: String) {
        let defaults = UserDefaults.standard
        defaults.set(token, forKey: tokenKey)
        defaults.set(rememberPassword, forKey: rememberKey)
        defaults.set(phone.trimmingCharacters(in: .whitespacesAndNewlines), forKey: phoneKey)
        if rememberPassword {
            defaults.set(password, forKey: passwordKey)
        } else {
            defaults.removeObject(forKey: passwordKey)
        }
        AhaTypeTextOptimizer.shared.patchCloudToken(token)
        isLoggedIn = true
    }

    private func applyProfile(_ profile: [String: Any]) {
        self.profile = profile
        isLoggedIn = true
        AhaTypeTextOptimizer.shared.patchCloudToken(accessToken)
        AhaTypeTextOptimizer.shared.setUserProfile(profile)
    }

    private func request(path: String, method: String, body: [String: Any]?, authorized: Bool) async throws -> [String: Any] {
        guard let url = URL(string: "\(apiBase)/\(path)") else {
            throw CloudAccountError("云端地址无效。")
        }
        var request = URLRequest(url: url, timeoutInterval: 90)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
            throw CloudAccountError("服务器返回非 JSON。", statusCode: statusCode)
        }
        if statusCode != 200 {
            throw CloudAccountError(stringValue(object["errorMsg"]).isEmpty ? "请求失败（HTTP \(statusCode)）。" : stringValue(object["errorMsg"]), statusCode: statusCode)
        }
        return object
    }

    private func payloadData(from object: [String: Any], fallbackError: String) throws -> [String: Any] {
        guard intValue(object["code"]) == 0 else {
            let msg = stringValue(object["errorMsg"])
            throw CloudAccountError(msg.isEmpty ? fallbackError : msg)
        }
        return object["data"] as? [String: Any] ?? [:]
    }

    private var accessToken: String {
        UserDefaults.standard.string(forKey: tokenKey) ?? ""
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

    private func intValue(_ value: Any?) -> Int {
        switch value {
        case let int as Int: return int
        case let number as NSNumber: return number.intValue
        case let string as String: return Int(string) ?? 0
        default: return 0
        }
    }

    private func formatFen(_ fen: Int) -> String {
        String(format: "%.2f 元", Double(max(0, fen)) / 100.0)
    }

    private func networkMessage(for error: Error) -> String {
        guard let urlError = error as? URLError else {
            return "云端连接失败：\(error.localizedDescription)"
        }
        switch urlError.code {
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected, .clientCertificateRequired:
            return "云端连接失败：TLS/SSL 校验未通过，请检查系统时间、网络代理/证书，或确认云端 HTTPS 证书配置正常。"
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet, .networkConnectionLost, .timedOut:
            return "云端连接失败：当前网络无法访问 AhaType 服务，请检查网络后重试。"
        default:
            return "云端连接失败：\(urlError.localizedDescription)"
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
        case .monthly: return "按月订阅"
        case .quarterly: return "按季订阅"
        case .yearly: return "按年订阅"
        }
    }

    var subtitle: String {
        switch self {
        case .monthly: return "30 天"
        case .quarterly: return "90 天"
        case .yearly: return "365 天"
        }
    }

    var orderDescription: String {
        switch self {
        case .monthly: return "包月充值"
        case .quarterly: return "包季充值"
        case .yearly: return "包年充值"
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
        String(format: "%.2f 元", Double(max(0, amountFen)) / 100.0)
    }
}
