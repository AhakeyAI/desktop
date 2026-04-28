import ApplicationServices
import AVFoundation
import Foundation

private let voiceTriggerKeyCode: CGKeyCode = 79   // F18
private let pasteKeyCode: CGKeyCode = 9           // V

private func emit(_ payload: [String: Any]) {
    guard JSONSerialization.isValidJSONObject(payload),
          let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
        return
    }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A]))
    fflush(stdout)
}

private func emitError(_ message: String, inputMonitoring: Bool? = nil, accessibility: Bool? = nil) {
    var payload: [String: Any] = [
        "type": "error",
        "message": message,
    ]
    if let inputMonitoring {
        payload["input_monitoring"] = inputMonitoring
    }
    if let accessibility {
        payload["accessibility"] = accessibility
    }
    emit(payload)
}

private func preflightPayload() -> [String: Any] {
    let inputMonitoring = CGPreflightListenEventAccess()
    let accessibility = AXIsProcessTrusted() && CGPreflightPostEventAccess()
    return [
        "type": "preflight",
        "input_monitoring": inputMonitoring,
        "accessibility": accessibility,
    ]
}

private func doPreflight() -> Int32 {
    emit(preflightPayload())
    return 0
}

private func microphoneAuthorizationStatusString() -> String {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
        return "authorized"
    case .denied:
        return "denied"
    case .restricted:
        return "restricted"
    case .notDetermined:
        return "not_determined"
    @unknown default:
        return "unknown"
    }
}

private func doMicrophonePreflight() -> Int32 {
    let status = microphoneAuthorizationStatusString()
    emit([
        "type": "mic_preflight",
        "status": status,
        "granted": status == "authorized",
    ])
    return 0
}

private func doMicrophoneRequest() -> Int32 {
    let currentStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    switch currentStatus {
    case .authorized:
        emit([
            "type": "mic_request",
            "status": "authorized",
            "granted": true,
        ])
        return 0

    case .denied:
        emit([
            "type": "mic_request",
            "status": "denied",
            "granted": false,
        ])
        return 0

    case .restricted:
        emit([
            "type": "mic_request",
            "status": "restricted",
            "granted": false,
        ])
        return 0

    case .notDetermined:
        let semaphore = DispatchSemaphore(value: 0)
        var granted = false
        AVCaptureDevice.requestAccess(for: .audio) { ok in
            granted = ok
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 20.0)
        let status = microphoneAuthorizationStatusString()
        emit([
            "type": "mic_request",
            "status": status,
            "granted": granted || status == "authorized",
        ])
        return 0

    @unknown default:
        emit([
            "type": "mic_request",
            "status": "unknown",
            "granted": false,
        ])
        return 0
    }
}

private func doClick(x: Double, y: Double) -> Int32 {
    guard CGPreflightPostEventAccess() else {
        emitError("accessibility_required", accessibility: false)
        return 2
    }

    let point = CGPoint(x: x, y: y)
    guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
          let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
        emitError("click_event_create_failed")
        return 3
    }

    down.post(tap: .cghidEventTap)
    usleep(18_000)
    up.post(tap: .cghidEventTap)
    return 0
}

private func doPaste() -> Int32 {
    guard CGPreflightPostEventAccess() else {
        emitError("accessibility_required", accessibility: false)
        return 2
    }

    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: pasteKeyCode, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: pasteKeyCode, keyDown: false) else {
        emitError("paste_event_create_failed")
        return 3
    }

    down.flags = .maskCommand
    up.flags = .maskCommand
    down.post(tap: .cghidEventTap)
    usleep(20_000)
    up.post(tap: .cghidEventTap)
    return 0
}

private func readStdinText() -> String {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

private func doTypeText() -> Int32 {
    guard CGPreflightPostEventAccess() else {
        emitError("accessibility_required", accessibility: false)
        return 2
    }

    let text = readStdinText()
    if text.isEmpty {
        emitError("empty_input")
        return 3
    }

    for scalar in text.utf16 {
        var unit = scalar
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
            emitError("type_event_create_failed")
            return 4
        }
        withUnsafePointer(to: &unit) { pointer in
            down.keyboardSetUnicodeString(stringLength: 1, unicodeString: pointer)
            up.keyboardSetUnicodeString(stringLength: 1, unicodeString: pointer)
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        usleep(6_000)
    }

    return 0
}

private final class MonitorState {
    static let shared = MonitorState()

    func handle(eventType: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch eventType {
        case .leftMouseDown:
            let point = event.location
            emit([
                "type": "pointer",
                "x": point.x,
                "y": point.y,
            ])
            return Unmanaged.passUnretained(event)

        case .keyDown:
            if CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)) == voiceTriggerKeyCode {
                emit(["type": "key_down"])
                return nil
            }
            return Unmanaged.passUnretained(event)

        case .keyUp:
            if CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)) == voiceTriggerKeyCode {
                emit(["type": "key_up"])
                return nil
            }
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }
}

private func doMonitor() -> Int32 {
    let inputMonitoring = CGPreflightListenEventAccess()
    let accessibility = AXIsProcessTrusted() && CGPreflightPostEventAccess()
    guard inputMonitoring && accessibility else {
        emitError(
            "permissions_required",
            inputMonitoring: inputMonitoring,
            accessibility: accessibility
        )
        return 2
    }

    let mask =
        (1 << CGEventType.keyDown.rawValue) |
        (1 << CGEventType.keyUp.rawValue) |
        (1 << CGEventType.leftMouseDown.rawValue)

    let callback: CGEventTapCallBack = { _, type, event, _ in
        return MonitorState.shared.handle(eventType: type, event: event)
    }

    guard let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: CGEventMask(mask),
        callback: callback,
        userInfo: nil
    ) else {
        emitError(
            "event_tap_create_failed",
            inputMonitoring: inputMonitoring,
            accessibility: accessibility
        )
        return 3
    }

    guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
        emitError("runloop_source_failed")
        return 4
    }

    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    emit(["type": "ready"])
    CFRunLoopRun()
    return 0
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("usage: voice_input_bridge <preflight|mic-preflight|mic-request|monitor|click|paste|type>\n", stderr)
    exit(64)
}

switch args[1] {
case "preflight":
    exit(doPreflight())

case "mic-preflight":
    exit(doMicrophonePreflight())

case "mic-request":
    exit(doMicrophoneRequest())

case "monitor":
    exit(doMonitor())

case "click":
    guard args.count >= 4,
          let x = Double(args[2]),
          let y = Double(args[3]) else {
        fputs("usage: voice_input_bridge click <x> <y>\n", stderr)
        exit(64)
    }
    exit(doClick(x: x, y: y))

case "paste":
    exit(doPaste())

case "type":
    exit(doTypeText())

default:
    fputs("unknown mode\n", stderr)
    exit(64)
}
