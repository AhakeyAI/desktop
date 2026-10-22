/// Keep the user's editing context separate from live device state. Voice and
/// status routing still consume the reported hardware mode independently.
enum StudioModeSelection {
    static func followingDevice(current: AhaKeyModeSlot, reportedMode: Int?,
                                isEditing: Bool, hasFixedKeyTarget: Bool) -> AhaKeyModeSlot {
        guard !isEditing, !hasFixedKeyTarget, let reportedMode,
              let mode = AhaKeyModeSlot(rawValue: reportedMode) else { return current }
        return mode
    }
}
