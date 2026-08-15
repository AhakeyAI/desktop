import Foundation

enum AhaKeyConfigurationTransport: Equatable {
    case unavailable
    case usb
    case bluetooth
}

/// USB and BLE expose the same configuration functions through different
/// primitives. This model keeps UI and feature code transport-neutral.
struct AhaKeyTransportCapabilities: Equatable {
    let preferredTransport: AhaKeyConfigurationTransport
    let canSendCommands: Bool
    let canReceiveResponses: Bool
    let canTransferBulkData: Bool

    var isConfigurationReady: Bool {
        canSendCommands && canReceiveResponses
    }

    static func resolve(
        isUSBConnected: Bool,
        isBLEConnected: Bool,
        commandCharReady: Bool,
        dataCharReady: Bool,
        notifyCharReady: Bool
    ) -> AhaKeyTransportCapabilities {
        if isUSBConnected {
            return AhaKeyTransportCapabilities(
                preferredTransport: .usb,
                canSendCommands: true,
                canReceiveResponses: true,
                canTransferBulkData: true
            )
        }

        guard isBLEConnected else {
            return AhaKeyTransportCapabilities(
                preferredTransport: .unavailable,
                canSendCommands: false,
                canReceiveResponses: false,
                canTransferBulkData: false
            )
        }

        return AhaKeyTransportCapabilities(
            preferredTransport: .bluetooth,
            canSendCommands: commandCharReady,
            canReceiveResponses: dataCharReady || notifyCharReady,
            canTransferBulkData: commandCharReady && dataCharReady
        )
    }
}
