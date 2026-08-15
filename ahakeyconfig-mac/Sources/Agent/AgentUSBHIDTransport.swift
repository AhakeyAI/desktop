import Foundation
import IOKit.hid

/// USB command channel used by the background Agent for live state updates.
/// The main app owns configuration/bulk transfers; the Agent only sends short
/// commands such as 0x90 and status queries while it is the selected owner.
final class AgentUSBHIDTransport {
    static let vendorID = 0x413C
    static let productID = 0x2107
    static let reportSize = 64
    static let commandChannel: UInt8 = 0xA1

    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?
    var onFrame: ((Data) -> Void)?
    var onError: ((String) -> Void)?

    private let manager: IOHIDManager
    private var device: IOHIDDevice?
    private var reportBuffer = [UInt8](repeating: 0, count: reportSize + 1)
    private var managerIsOpen = false
    private var retryTimer: Timer?

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
                Unmanaged<AgentUSBHIDTransport>.fromOpaque(context).takeUnretainedValue().attach(device)
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
        IOHIDManagerRegisterDeviceRemovalCallback(
            manager,
            { context, _, _, device in
                guard let context else { return }
                Unmanaged<AgentUSBHIDTransport>.fromOpaque(context).takeUnretainedValue().remove(device)
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    deinit {
        retryTimer?.invalidate()
        if let device {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        if managerIsOpen {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    var isConnected: Bool { device != nil }

    func start() {
        attemptOpenAndDiscover()
    }

    func sendCommand(_ payload: Data) throws {
        guard let device else { throw AgentUSBError.notConnected }
        guard payload.count <= Self.reportSize - 2 else { throw AgentUSBError.commandTooLarge }
        var report = [UInt8](repeating: 0, count: Self.reportSize)
        report[0] = Self.commandChannel
        report[1] = UInt8(payload.count)
        payload.copyBytes(to: &report[2], count: payload.count)
        let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, report, report.count)
        guard result == kIOReturnSuccess else { throw AgentUSBError.writeFailed(result) }
    }

    private func attemptOpenAndDiscover() {
        if !managerIsOpen {
            let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            if result == kIOReturnSuccess {
                managerIsOpen = true
            }
        }
        discoverMatchingDevices()
        if device == nil { scheduleRetry() }
    }

    private func discoverMatchingDevices() {
        guard device == nil,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>
        else { return }
        for candidate in devices where device == nil {
            attach(candidate)
        }
    }

    private func scheduleRetry() {
        guard retryTimer == nil, device == nil else { return }
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.attemptOpenAndDiscover()
        }
        retryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func attach(_ candidate: IOHIDDevice) {
        guard device == nil else { return }
        let result = IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            onError?("USB HID open failed (\(result))")
            scheduleRetry()
            return
        }
        device = candidate
        retryTimer?.invalidate()
        retryTimer = nil
        IOHIDDeviceScheduleWithRunLoop(candidate, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceRegisterInputReportCallback(
            candidate,
            &reportBuffer,
            reportBuffer.count,
            { context, _, _, _, _, report, reportLength in
                guard let context else { return }
                let transport = Unmanaged<AgentUSBHIDTransport>.fromOpaque(context).takeUnretainedValue()
                transport.receive(Data(bytes: report, count: reportLength))
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
        onConnected?()
    }

    private func remove(_ candidate: IOHIDDevice) {
        guard let device, device == candidate else { return }
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        self.device = nil
        onDisconnected?()
        scheduleRetry()
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

private enum AgentUSBError: Error {
    case notConnected
    case commandTooLarge
    case writeFailed(IOReturn)
}
