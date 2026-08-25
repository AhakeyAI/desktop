import AhaKeyConfigShared
import Foundation
import IOKit.hid

struct AhaKeyUSBDeviceIdentity: Equatable {
    static let currentVendorID = 0x07D7
    static let currentProductID = 0x501A
    static let legacyVendorID = 0x413C
    static let legacyProductID = 0x2107

    let vendorID: Int
    let productID: Int
    let productName: String
    let serialNumber: String

    var shortIdentifier: String {
        AhaKeyDevicePresentation.shortIdentifier(from: serialNumber) ?? "—"
    }

    var transportDescription: String {
        String(format: "USB %04X:%04X", vendorID, productID)
    }
}

/// Vendor-defined USB HID interface used by current firmware for configuration traffic.
/// Both product identities are enumerated during migration; the manager's negotiated
/// protocol gate decides whether this physical interface may carry commands.
final class AhaKeyUSBHIDTransport {
    var onConnected: ((AhaKeyUSBDeviceIdentity) -> Void)?
    var onDisconnected: (() -> Void)?
    var onFrame: ((Data) -> Void)?
    var onError: ((Error) -> Void)?

    private let manager: IOHIDManager
    private var device: IOHIDDevice?
    private(set) var connectedIdentity: AhaKeyUSBDeviceIdentity?
    private var reportBuffer = [UInt8](repeating: 0, count: AhaKeyUSBHIDReportCodec.reportSize + 1)

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let identities = [
            (AhaKeyUSBDeviceIdentity.currentVendorID, AhaKeyUSBDeviceIdentity.currentProductID),
            (AhaKeyUSBDeviceIdentity.legacyVendorID, AhaKeyUSBDeviceIdentity.legacyProductID),
        ]
        let matching = identities.map { vendorID, productID in
            [
                kIOHIDVendorIDKey as String: vendorID,
                kIOHIDProductIDKey as String: productID,
                kIOHIDPrimaryUsagePageKey as String: 0xFF00,
            ]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
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
            onError?(AhaKeyUSBTransportError.openFailed(result))
        }
    }

    /// 停止 USB 占用（WBS-5.5：Agent 独占时 Studio 不得再作为竞争方持有 USB HID）。
    func stop() {
        if let device {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            self.device = nil
        }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func sendCommand(_ frame: Data) throws {
        try send(report: AhaKeyUSBHIDReportCodec.report(channel: .command, payload: frame))
    }

    func sendData(_ data: Data) async throws {
        for report in try AhaKeyUSBHIDReportCodec.dataReports(for: data) {
            if Task.isCancelled { throw CancellationError() }
            try send(report: report)
            try await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    private func attach(_ candidate: IOHIDDevice) {
        guard device == nil else { return }
        let result = IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            onError?(AhaKeyUSBTransportError.openFailed(result))
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
        let attachedIdentity = identity(for: candidate)
        connectedIdentity = attachedIdentity
        onConnected?(attachedIdentity)
    }

    private func remove(_ candidate: IOHIDDevice) {
        guard let device, device == candidate else { return }
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        self.device = nil
        connectedIdentity = nil
        onDisconnected?()
    }

    private func send(report: Data) throws {
        guard let device else { throw AhaKeyUSBTransportError.notConnected }
        let result = report.withUnsafeBytes { bytes in
            IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                0,
                bytes.bindMemory(to: UInt8.self).baseAddress!,
                report.count
            )
        }
        guard result == kIOReturnSuccess else { throw AhaKeyUSBTransportError.writeFailed(result) }
    }

    private func receive(_ report: Data) {
        guard let frame = AhaKeyUSBHIDReportCodec.protocolFrame(from: report) else { return }
        onFrame?(frame)
    }

    private func identity(for device: IOHIDDevice) -> AhaKeyUSBDeviceIdentity {
        func number(_ key: String) -> Int {
            (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
        }
        func string(_ key: String) -> String {
            IOHIDDeviceGetProperty(device, key as CFString) as? String ?? ""
        }
        return AhaKeyUSBDeviceIdentity(
            vendorID: number(kIOHIDVendorIDKey as String),
            productID: number(kIOHIDProductIDKey as String),
            productName: string(kIOHIDProductKey as String),
            serialNumber: string(kIOHIDSerialNumberKey as String)
        )
    }
}

enum AhaKeyUSBTransportError: LocalizedError {
    case notConnected
    case openFailed(IOReturn)
    case writeFailed(IOReturn)

    var errorDescription: String? {
        switch self {
        case .notConnected: return NSLocalizedString("USB HID 设备未连接", comment: "")
        case let .openFailed(code): return String(format: NSLocalizedString("无法打开 USB HID 设备（%d）", comment: ""), code)
        case let .writeFailed(code): return String(format: NSLocalizedString("USB HID 写入失败（%d）", comment: ""), code)
        }
    }
}
