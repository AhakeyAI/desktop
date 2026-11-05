import Foundation
import AhaKeyConfigShared

/// Three user-facing states; the firmware's idle slot follows Completed.
enum StudioScreenArtworkPlan {
    static func entries(mode: Int, presentation: WS3PresentationMode) -> [UInt8] {
        guard (0..<4).contains(mode) else { return [] }
        return presentation == .multi ? [16, 17, 18] : (1...3).map { UInt8(mode * 4 + $0) }
    }
    static func pending(mode: Int, presentation: WS3PresentationMode, dirty: Set<UInt8>) -> [UInt8] {
        var result = entries(mode: mode, presentation: presentation).filter { dirty.contains($0) }
        if presentation == .single, (0..<4).contains(mode), dirty.contains(UInt8(mode * 4)) {
            result.append(UInt8(mode * 4))
        }
        return result
    }
    static func fallback(_ payload: WS3ResourcePayload) throws -> WS3ResourcePayload {
        guard payload.entryID < 16, payload.entryID % 4 == 3 else { throw Failure.notCompleted }
        let target = payload.entryID - 3
        let limit = Int(WS3ResourceReadback.maximumFrames(target))
        let sourceCount = Int(payload.frameCount), count = min(sourceCount, limit)
        let frames = (0..<count).map { index -> Data in
            let source = count == 1 ? 0 : index * (sourceCount - 1) / (count - 1)
            let offset = source * Int(WS3ResourceReadback.frameBytes)
            return payload.bytes.subdata(in: offset..<(offset + 25_600))
        }
        return try WS3ResourcePayload(entryID: target, frames: frames)
    }
    enum Failure: Error { case notCompleted }
}
