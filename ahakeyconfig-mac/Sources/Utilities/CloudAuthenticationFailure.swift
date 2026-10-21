import Foundation

/// A quota/permission 403 or a network failure is not proof of an expired login.
enum CloudAuthenticationFailure {
    static func matches(status: Int? = nil, code: Int? = nil, message: String = "") -> Bool {
        if status == 401 || code == 401 { return true }
        let value = message.lowercased().filter { !$0.isWhitespace }
        return ["未登录", "尚未登录", "登录已过期", "登录过期", "登录失效", "登录已失效", "请重新登录", "token无效", "无效的token", "tokenisinvalid", "token已失效", "token失效", "token过期", "token已过期", "invalidtoken", "tokeninvalid", "tokenexpired", "expiredtoken", "jwtexpired", "unauthorized"]
            .contains { value.contains($0) }
    }
}
