import Foundation
import IOKit.hid

/// USB configuration interface exposed by the firmware alongside the keyboard HID interface.
/// Windows uses the same VID/PID and 64-byte reports on interface MI_01.
final class AhaKeyUSBHIDTransport {
    static let vendorID = 0x413C
    static let productID = 0x2107
    static let reportSize = 64
    static let commandChannel: UInt8 = 0xA1
    static let dataChannel: UInt8 = 0xA2

    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?
    var onFrame: ((Data) -> Void)?
    var onError: ((Error) -> Void)?

    private let manager: IOHIDManager
    private var device: IOHIDDevice?
    private var reportBuffer = [UInt8](repeating: 0, count: reportSize + 1)

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: Self.vendorID,
            kIOHIDProductIDKey as String: Self.productID,
            kIOHIDPrimaryUsagePageKey as String: 0xFF00,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerRegisterDeviceMatchingCallback(
            manager,
            { context, _, _, device in
                guard let context else { return }
                Unmanaged<AhaKeyUSBHIDTransport>.fromOpaque(context).takeUnretainedValue().attach(device)
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
        IOHIDManagerRegisterDeviceRemovalCallback(
            manager,
            { context, _, _, device in
                guard let context else { return }
                Unmanaged<AhaKeyUSBHIDTransport>.fromOpaque(context).takeUnretainedValue().remove(device)
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    deinit {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    var isConnected: Bool { device != nil }

    func start() {
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            onError?(USBTransportError.openFailed(result))
        }
    }

    func sendCommand(_ frame: Data) throws {
        guard frame.count <= Self.reportSize - 2 else { throw USBTransportError.commandTooLarge }
        try send(channel: Self.commandChannel, payload: frame)
    }

    func sendData(_ data: Data) async throws {
        var offset = 0
        while offset < data.count {
            let end = min(offset + Self.reportSize - 2, data.count)
            try send(channel: Self.dataChannel, payload: Data(data[offset ..< end]))
            offset = end
            try await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    private func attach(_ candidate: IOHIDDevice) {
        guard device == nil else { return }
        let result = IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            onError?(USBTransportError.openFailed(result))
            return
        }
        device = candidate
        IOHIDDeviceRegisterInputReportCallback(
            candidate,
            &reportBuffer,
            reportBuffer.count,
            { context, _, _, _, _, report, reportLength in
                guard let context else { return }
                let transport = Unmanaged<AhaKeyUSBHIDTransport>.fromOpaque(context).takeUnretainedValue()
                transport.receive(Data(bytes: report, count: reportLength))
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
        onConnected?()
    }

    private func remove(_ candidate: IOHIDDevice) {
        guard let device, device == candidate else { return }
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        self.device = nil
        onDisconnected?()
    }

    private func send(channel: UInt8, payload: Data) throws {
        guard let device else { throw USBTransportError.notConnected }
        var report = [UInt8](repeating: 0, count: Self.reportSize)
        report[0] = channel
        report[1] = UInt8(payload.count)
        payload.copyBytes(to: &report[2], count: payload.count)
        let result = IOHIDDeviceSetReport(
            device,
            kIOHIDReportTypeOutput,
            0,
            report,
            report.count
        )
        guard result == kIOReturnSuccess else { throw USBTransportError.writeFailed(result) }
    }

    private func receive(_ report: Data) {
        guard let start = report.indices.first(where: { index in
            index + 1 < report.endIndex && report[index] == 0xAA && report[index + 1] == 0xBB
        }) else { return }
        var end = start + 3
        while end + 1 < report.endIndex {
            if report[end] == 0xCC && report[end + 1] == 0xDD {
                onFrame?(Data(report[start ... end + 1]))
                return
            }
            end += 1
        }
    }
}

enum USBTransportError: LocalizedError {
    case notConnected
    case commandTooLarge
    case openFailed(IOReturn)
    case writeFailed(IOReturn)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "USB HID device is not connected"
        case .commandTooLarge: return "USB command exceeds 62-byte payload limit"
        case let .openFailed(code): return "Could not open USB HID device (\(code))"
        case let .writeFailed(code): return "USB HID write failed (\(code))"
        }
    }
}
