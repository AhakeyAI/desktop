import Foundation
import AppKit
import CoreServices
import AhaKeyConfigShared

/// Read-only Apple Events, not AppleScript or a shell. Queries an already
/// running process and cannot launch a terminal, execute text, or send keys.
enum TerminalSelectionQuery {
    enum Provider: String, CaseIterable, Sendable {
        case terminal = "com.apple.Terminal"
        case iTerm = "com.googlecode.iterm2"
    }
    enum Failure: Error, Equatable { case invalidTarget, invalidDescriptor, authorizationRequired, noTTY, staleTarget }
    private static let queue = DispatchQueue(label: "lab.jawa.ahakeyconfig.terminal-selection", qos: .utility)

    static func readTTY(processID: Int32, provider: Provider) async throws -> String {
        try Task.checkCancellation()
        let launchedAt = await MainActor.run { () -> Date? in
            guard let app = NSRunningApplication(processIdentifier: processID), app.bundleIdentifier == provider.rawValue,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == processID else { return nil }
            return app.launchDate
        }
        guard let launchedAt else { throw Failure.invalidTarget }
        let path: String = try await withCheckedThrowingContinuation { continuation in
            queue.async {
                autoreleasepool {
                    do {
                        let target = NSAppleEventDescriptor(processIdentifier: processID)
                        guard AEDeterminePermissionToAutomateTarget(target.aeDesc, code("core"), code("getd"), false) == noErr else {
                            throw Failure.authorizationRequired
                        }
                        let request = try makeGetTTYEvent(processID: processID, provider: provider)
                        let reply = try request.sendEvent(options: [.waitForReply, .neverInteract, .dontRecord], timeout: 1)
                        guard let path = parseTTY(reply) else { throw Failure.noTTY }
                        continuation.resume(returning: path)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }
        let stillCurrent = await MainActor.run {
            let app = NSRunningApplication(processIdentifier: processID)
            return app?.bundleIdentifier == provider.rawValue && app?.launchDate == launchedAt &&
                NSWorkspace.shared.frontmostApplication?.processIdentifier == processID
        }
        try Task.checkCancellation()
        guard stillCurrent else { throw Failure.staleTarget }
        return path
    }

    /// Only the explicit opt-in/permission action calls this; refresh never asks.
    static func requestAuthorization(processID: Int32, provider: Provider) async -> Bool {
        let valid = await MainActor.run { NSRunningApplication(processIdentifier: processID)?.bundleIdentifier == provider.rawValue }
        guard valid, processID > 1 else { return false }
        return await withCheckedContinuation { continuation in
            queue.async {
                autoreleasepool {
                    let target = NSAppleEventDescriptor(processIdentifier: processID)
                    let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, code("core"), code("getd"), true)
                    continuation.resume(returning: status == noErr)
                }
            }
        }
    }

    /// Descriptor construction is independently testable without contacting apps
    /// or prompting for automation permission.
    static func makeGetTTYEvent(processID: Int32, provider: Provider) throws -> NSAppleEventDescriptor {
        guard processID > 1 else { throw Failure.invalidTarget }
        let container: NSAppleEventDescriptor
        let ttyProperty: String
        switch provider {
        case .terminal:
            let window = try object(desired: "cwin", form: "indx", key: NSAppleEventDescriptor(int32: 1), container: .null())
            container = try property("tcnt", of: window)
            ttyProperty = "ttty"
        case .iTerm:
            let window = try property("Crwn", of: .null())
            container = try property("Wcsn", of: window)
            ttyProperty = "Stty"
        }
        let request = NSAppleEventDescriptor.appleEvent(withEventClass: code("core"), eventID: code("getd"),
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: processID), returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))
        request.setParam(try property(ttyProperty, of: container), forKeyword: code("----"))
        return request
    }
    static func parseTTY(_ reply: NSAppleEventDescriptor) -> String? {
        if let error = reply.paramDescriptor(forKeyword: code("errn")), error.int32Value != 0 { return nil }
        guard let path = reply.paramDescriptor(forKeyword: code("----"))?.stringValue,
              WS3TerminalTaskIdentity.validTTYPath(path) else { return nil }
        return path
    }
    static func code(_ text: String) -> UInt32 {
        precondition(text.utf8.count == 4)
        return text.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }
    private static func property(_ id: String, of container: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        try object(desired: "prop", form: "prop", key: NSAppleEventDescriptor(typeCode: code(id)), container: container)
    }
    private static func object(desired: String, form: String, key: NSAppleEventDescriptor,
        container: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: code(desired)), forKeyword: code("want"))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: code(form)), forKeyword: code("form"))
        record.setDescriptor(key, forKeyword: code("seld"))
        record.setDescriptor(container, forKeyword: code("from"))
        guard let object = record.coerce(toDescriptorType: code("obj ")) else { throw Failure.invalidDescriptor }
        return object
    }
}
