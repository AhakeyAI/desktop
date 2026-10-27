import Foundation
import CoreFoundation

/// Talks only to an existing official Code Desktop. No start/create/takeover,
/// prompts, approval replies, debug endpoints or replacement TUI are exposed.
public actor KimiDesktopPermissionBridge {
    public enum Mode: String, Codable, Sendable { case manual, yolo, auto }
    public enum Failure: Error, Equatable {
        case unauthorized, invalidTarget, instanceChanged, invalidResponse, rejected, unavailable
        case conflict(Mode), notApplied
    }
    public struct Session: Equatable, Sendable { public let id: String; public let title: String }
    public struct Page: Equatable, Sendable {
        public let loadedSessions: [Session]
        public let nextPageToken: String?
    }
    public struct Receipt: Equatable, Sendable { public let mode: Mode; public let attemptedWrite: Bool }
    // nil ID is explicit directory inspection; non-nil IDs need an exact grant.
    public typealias Authorization = @Sendable (String?, Mode?) async -> Bool
    typealias Exchange = @Sendable (String?, Mode?, String, String, [URLQueryItem], Data?) async throws -> Data
    private let authorization: Authorization
    private let exchange: Exchange

    public init(instance: KimiDesktopInstanceDiscovery.Instance, authorization: @escaping Authorization) {
        self.authorization = authorization
        self.exchange = { id, mode, method, path, query, body in
            try await KimiDesktopPermissionHTTP.exchange(instance: instance, authorization: authorization,
                sessionID: id, writeMode: mode, method: method, path: path, query: query, body: body)
        }
    }
    init(authorization: @escaping Authorization, exchange: @escaping Exchange) {
        self.authorization = authorization; self.exchange = exchange
    }
    /// New grants are offered for loaded conversations only. A prior exact grant
    /// may subsequently resume the same conversation in its original application.
    public func loadedSessions(pageToken: String? = nil) async throws -> Page {
        guard pageToken.map({ !$0.isEmpty && $0.utf8.count <= 2048 &&
            !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }) ?? true else { throw Failure.invalidTarget }
        var query = [URLQueryItem(name: "view", value: "flat"), URLQueryItem(name: "page_size", value: "32")]
        if let pageToken { query.append(URLQueryItem(name: "page_token", value: pageToken)) }
        let data = try await perform(id: nil, method: "GET", path: "/api/v2/sessions", query: query)
        let object = try Self.envelope(data)
        guard let items = object["items"] as? [[String: Any]], items.count <= 32,
              let more = Self.boolean(object["has_more"]) else { throw Failure.invalidResponse }
        let token = object["next_page_token"] as? String
        guard more ? (token.map { !$0.isEmpty && $0.utf8.count <= 2048 } ?? false) :
              (object["next_page_token"] == nil || object["next_page_token"] is NSNull) else { throw Failure.invalidResponse }
        var sessions: [Session] = [], ids = Set<String>()
        for item in items {
            guard let id = item["id"] as? String, Self.validSessionID(id), ids.insert(id).inserted,
                  let meta = item["meta"] as? [String: Any], let archived = Self.boolean(meta["archived"]),
                  let activity = item["activity"] as? [String: Any] else { throw Failure.invalidResponse }
            guard !archived, let model = activity["model"] as? String, !model.isEmpty else { continue }
            guard let title = meta["title"] as? String ?? (meta["title"] is NSNull ? "" : nil),
                  title.utf8.count <= 2048 else { throw Failure.invalidResponse }
            // Discard prompt, cwd and model values; retain selection metadata only.
            sessions.append(.init(id: id, title: title.components(separatedBy: .newlines).first ?? ""))
        }
        return Page(loadedSessions: sessions, nextPageToken: more ? token : nil)
    }
    public func readPermission(sessionID: String) async throws -> Mode {
        let data = try await perform(id: sessionID, method: "GET", path: Self.path(sessionID, "status"))
        guard let raw = try Self.envelope(data)["permission"] as? String, let mode = Mode(rawValue: raw) else { throw Failure.invalidResponse }
        return mode
    }
    /// Caller must persist recovery intent first. Comparison is a fresh conflict
    /// check, not an upstream atomic CAS. Every write needs independent readback.
    public func setPermission(sessionID: String, expecting expected: Mode, to desired: Mode) async throws -> Receipt {
        let before = try await readPermission(sessionID: sessionID)
        guard before == expected else { throw Failure.conflict(before) }
        if before == desired { return Receipt(mode: before, attemptedWrite: false) }
        let body = try JSONSerialization.data(withJSONObject: ["agent_config": ["permission_mode": desired.rawValue]])
        do {
            let reply = try await perform(id: sessionID, mode: desired, method: "POST", path: Self.path(sessionID, "profile"), body: body)
            guard try Self.envelope(reply)["id"] as? String == sessionID else { throw Failure.invalidResponse }
        } catch Failure.unavailable {
            // A lost reply is ambiguous; do not retry the POST or discard ownership.
        }
        let actual = try await readPermission(sessionID: sessionID)
        guard actual == desired else { throw Failure.notApplied }
        return Receipt(mode: actual, attemptedWrite: true)
    }
    private func perform(id: String?, mode: Mode? = nil, method: String, path: String,
                         query: [URLQueryItem] = [], body: Data? = nil) async throws -> Data {
        try Task.checkCancellation()
        guard id.map(Self.validSessionID) ?? true else { throw Failure.invalidTarget }
        guard await authorization(id, mode) else { throw Failure.unauthorized }
        let data = try await exchange(id, mode, method, path, query, body)
        try Task.checkCancellation()
        guard await authorization(id, mode) else { throw Failure.unauthorized }
        guard data.count <= 262_144 else { throw Failure.invalidResponse }
        return data
    }
    static func validSessionID(_ id: String) -> Bool {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-".utf8)
        return (1...128).contains(id.utf8.count) && id.utf8.allSatisfy(allowed.contains)
    }
    private static func path(_ id: String, _ suffix: String) -> String { "/api/v1/sessions/\(id)/\(suffix)" }
    private static func boolean(_ value: Any?) -> Bool? {
        guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
        return n.boolValue
    }
    private static func envelope(_ data: Data) throws -> [String: Any] {
        guard data.count <= 262_144, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = object["code"] as? NSNumber, CFGetTypeID(code) != CFBooleanGetTypeID(), code.stringValue == "0" else { throw Failure.rejected }
        guard let body = object["data"] as? [String: Any] else { throw Failure.invalidResponse }
        return body
    }
}

private enum KimiDesktopPermissionHTTP {
    typealias Failure = KimiDesktopPermissionBridge.Failure
    private final class RedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    static func exchange(instance: KimiDesktopInstanceDiscovery.Instance, authorization: KimiDesktopPermissionBridge.Authorization,
        sessionID: String?, writeMode: KimiDesktopPermissionBridge.Mode?, method: String, path: String,
        query: [URLQueryItem], body: Data?) async throws -> Data {
        func current() -> Bool {
            KimiDesktopInstanceDiscovery.scan(homes: [instance.homeDirectory]).instances.contains { candidate in
                let a = candidate.registration, b = instance.registration
                return a.serverID == b.serverID && a.pid == b.pid && a.host == b.host && a.port == b.port &&
                    a.startedMilliseconds == b.startedMilliseconds && a.serverVersion == b.serverVersion &&
                    candidate.process == instance.process && candidate.installedVersion == instance.installedVersion &&
                    candidate.homeDirectory == instance.homeDirectory
            }
        }
        guard await authorization(sessionID, writeMode) else { throw Failure.unauthorized }
        guard current() else { throw Failure.instanceChanged }
        let credential: KimiLocalBearerCredential
        do {
            credential = try KimiPrivateCredentialFile.read(instance.homeDirectory.appendingPathComponent("server.token"),
                userAuthorized: true, verifyOwner: current)
        } catch { throw Failure.instanceChanged }
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.urlCache = nil; config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 3; config.timeoutIntervalForResource = 5
        let session = URLSession(configuration: config, delegate: RedirectBlocker(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        func request(_ method: String, _ path: String, _ query: [URLQueryItem] = [], _ body: Data? = nil) async throws -> Data {
            try Task.checkCancellation()
            guard await authorization(sessionID, writeMode) else { throw Failure.unauthorized }
            guard current() else { throw Failure.instanceChanged }
            var parts = URLComponents()
            parts.scheme = "http"; parts.host = instance.registration.host; parts.port = Int(instance.registration.port)
            parts.path = path; parts.queryItems = query.isEmpty ? nil : query
            guard let url = parts.url else { throw Failure.invalidTarget }
            var request = URLRequest(url: url)
            request.httpMethod = method; request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
            credential.withAuthorizationHeader { request.setValue($0, forHTTPHeaderField: "Authorization") }
            do {
                let (bytes, response) = try await session.bytes(for: request)
                guard let response = response as? HTTPURLResponse, response.url == url,
                      response.statusCode == 200, response.expectedContentLength <= 262_144 else { throw Failure.rejected }
                var data = Data()
                for try await byte in bytes {
                    guard data.count < 262_144 else { throw Failure.invalidResponse }
                    data.append(byte)
                }
                guard current() else { throw Failure.instanceChanged }
                return data
            } catch is CancellationError { throw CancellationError() }
            catch let failure as Failure { throw failure }
            catch { throw Failure.unavailable }
        }
        let meta = try await request("GET", "/api/v1/meta")
        guard KimiDesktopServerMetadata.parse(meta, expected: instance.registration) != nil else { throw Failure.instanceChanged }
        return try await request(method, path, query, body)
    }
}
