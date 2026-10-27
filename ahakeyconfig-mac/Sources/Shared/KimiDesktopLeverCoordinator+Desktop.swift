import Foundation

extension KimiDesktopLeverCoordinator.Dependencies {
    public static func desktop(state: KimiDesktopLeverState = .init(),
        authority: @escaping @Sendable () async -> KimiDesktopLeverCoordinator.Authority,
        controlEnabled: @escaping @Sendable () -> Bool = { ApprovalAutomationControl.isEnabled(.kimi) }) -> Self {
        @Sendable func bridge(_ target: KimiDesktopLeverState.Target, operation: KimiDesktopLeverState.Lease? = nil,
                    managing: Bool = false) throws -> KimiDesktopPermissionBridge {
            let snapshot = try state.snapshot()
            let preferred = snapshot.grants.first(where: { $0.target == target })?.preferredServerID ??
                snapshot.leases.first(where: { $0.target == target })?.preferredServerID
            let candidates = KimiDesktopInstanceDiscovery.scan(homes: [URL(fileURLWithPath: target.home, isDirectory: true)]).instances
            let instance: KimiDesktopInstanceDiscovery.Instance
            if let preferred, let exact = candidates.first(where: { $0.registration.serverID == preferred }) { instance = exact }
            else if candidates.count == 1 { instance = candidates[0] }
            else { throw KimiDesktopPermissionBridge.Failure.instanceChanged }
            return KimiDesktopPermissionBridge(instance: instance, authorization: { id, desired in
                guard id == target.sessionID, let snapshot = try? state.snapshot() else { return false }
                let granted = snapshot.grants.contains { $0.target == target }
                let pending = snapshot.leases.first { $0.target == target }
                guard let desired else { return granted || pending != nil }
                guard let operation, pending?.operationID == operation.operationID else { return false }
                let current = await authority()
                return Self.permitsWrite(lease: operation, desired: desired, granted: granted,
                    controlEnabled: controlEnabled(), authority: current, managing: managing)
            })
        }
        return Self(authority: authority, controlEnabled: controlEnabled, read: { target in
            try await bridge(target).readPermission(sessionID: target.sessionID)
        }, write: { lease, expected, desired, managing in
            try await bridge(lease.target, operation: lease, managing: managing)
                .setPermission(sessionID: lease.target.sessionID, expecting: expected, to: desired)
        })
    }
    static func permitsWrite(lease: KimiDesktopLeverState.Lease, desired: KimiDesktopPermissionBridge.Mode,
        granted: Bool, controlEnabled: Bool, authority: KimiDesktopLeverCoordinator.Authority, managing: Bool) -> Bool {
        if managing {
            guard granted, controlEnabled else { return false }
            return desired == .auto ? authority == .automatic : desired == .manual && authority == .manual
        }
        return desired == lease.baseline && (!granted || !controlEnabled || authority == .unmanaged)
    }

}
