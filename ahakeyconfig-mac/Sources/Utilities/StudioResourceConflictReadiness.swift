/// Native alerts capture their inherited enabled state when presented. Wait
/// for both the upload operation and its enclosing screen submission to finish.
enum StudioResourceConflictReadiness {
    static func mayPresent(hasConflict: Bool, editorEnabled: Bool, operationBusy: Bool) -> Bool {
        hasConflict && editorEnabled && !operationBusy
    }
}
