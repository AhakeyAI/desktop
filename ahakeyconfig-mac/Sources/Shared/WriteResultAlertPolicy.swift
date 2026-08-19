public enum WriteResultAlertChoice {
    case continueEditing
    case completeEditing
}

public enum WriteResultAlertPolicy {
    public static func shouldExitEditing(for choice: WriteResultAlertChoice) -> Bool {
        choice == .completeEditing
    }
}
