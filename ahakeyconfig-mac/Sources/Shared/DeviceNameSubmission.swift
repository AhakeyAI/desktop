import Foundation

/// Opcode 0x01 acknowledges an in-memory name change. It cannot prove that the
/// advertising name changed or survived power loss; 0x04 persists key_bund only.
public enum DeviceNameSubmission {
    public static let maximumBytes = 15
    public enum ValidationError: Error, Equatable { case empty, invalidCharacters, tooLong(byteCount: Int) }
    public enum Failure: Error { case invalidReply, rejected, unconfirmed }
    public struct Receipt: Equatable {
        public let acceptedName: String
    }
    public static func validate(_ raw: String) -> Result<String, ValidationError> {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .failure(.empty) }
        guard !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return .failure(.invalidCharacters) }
        guard name.utf8.count <= maximumBytes else { return .failure(.tooLong(byteCount: name.utf8.count)) }
        return .success(name)
    }
    public static func request(_ raw: String) throws -> Data {
        let name = try validate(raw).get()
        return Data([0xAA, 0xBB, 0x01]) + Data(name.utf8) + Data([0xCC, 0xDD])
    }
    public static func validRequest(_ data: Data) -> Bool {
        guard data.count >= 6, data.prefix(3) == Data([0xAA, 0xBB, 0x01]),
              data.suffix(2) == Data([0xCC, 0xDD]),
              let value = String(data: data.dropFirst(3).dropLast(2), encoding: .utf8),
              case .success(let normalized) = validate(value) else { return false }
        return normalized == value
    }
    @MainActor
    public static func submit(_ raw: String, checkSession: () throws -> Void,
                              exchange: (Data) async throws -> Data) async throws -> Receipt {
        let name = try validate(raw).get()
        let command = try request(name)
        try Task.checkCancellation(); try checkSession()
        let reply: Data
        do { reply = try await exchange(command) }
        catch { throw Failure.unconfirmed }
        try Task.checkCancellation(); try checkSession()
        guard reply.count == 6, reply.prefix(3) == Data([0xAA, 0xBB, 0x01]),
              reply.suffix(2) == Data([0xCC, 0xDD]) else { throw Failure.invalidReply }
        guard reply[3] == 0 else { throw Failure.rejected }
        return Receipt(acceptedName: name)
    }
}

extension DeviceNameSubmission.Failure: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidReply: return NSLocalizedString("设备改名回包无法确认，请重新连接核对名称。", comment: "")
        case .rejected: return NSLocalizedString("键盘未接受新名称，请稍后再试。", comment: "")
        case .unconfirmed: return NSLocalizedString("改名结果未确认，可能已生效；请重新连接核对，不要重复提交。", comment: "")
        }
    }
}
