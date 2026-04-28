import ApplicationServices
import Foundation

enum InjectorError: Error, CustomStringConvertible {
    case emptyInput
    case notTrusted
    case noFocusedElement
    case attrReadFailed(String, AXError)
    case attrNotSettable(String)
    case attrWriteFailed(String, AXError)
    case invalidRange
    case emptyValue

    var description: String {
        switch self {
        case .emptyInput:
            return "empty input"
        case .notTrusted:
            return "accessibility not trusted"
        case .noFocusedElement:
            return "no focused element"
        case .attrReadFailed(let attr, let code):
            return "read \(attr) failed: \(code.rawValue)"
        case .attrNotSettable(let attr):
            return "attribute not settable: \(attr)"
        case .attrWriteFailed(let attr, let code):
            return "write \(attr) failed: \(code.rawValue)"
        case .invalidRange:
            return "invalid selected range"
        case .emptyValue:
            return "focused value is empty or unavailable"
        }
    }
}

func readInput() -> String {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

func copyAttribute(_ element: AXUIElement, _ attr: CFString) throws -> AnyObject {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attr, &value)
    guard error == .success, let value else {
        throw InjectorError.attrReadFailed(attr as String, error)
    }
    return value
}

func ensureSettable(_ element: AXUIElement, _ attr: CFString) throws {
    var settable = DarwinBoolean(false)
    let error = AXUIElementIsAttributeSettable(element, attr, &settable)
    guard error == .success else {
        throw InjectorError.attrReadFailed(attr as String, error)
    }
    guard settable.boolValue else {
        throw InjectorError.attrNotSettable(attr as String)
    }
}

func focusedElement() throws -> AXUIElement {
    guard AXIsProcessTrusted() else {
        throw InjectorError.notTrusted
    }
    let systemWide = AXUIElementCreateSystemWide()
    guard let value = try? copyAttribute(systemWide, kAXFocusedUIElementAttribute as CFString),
          CFGetTypeID(value) == AXUIElementGetTypeID() else {
        throw InjectorError.noFocusedElement
    }
    return unsafeBitCast(value, to: AXUIElement.self)
}

func readSelectedRange(_ element: AXUIElement) throws -> CFRange {
    let value = try copyAttribute(element, kAXSelectedTextRangeAttribute as CFString)
    guard CFGetTypeID(value) == AXValueGetTypeID() else {
        throw InjectorError.invalidRange
    }
    let axValue = unsafeBitCast(value, to: AXValue.self)
    guard AXValueGetType(axValue) == .cfRange else {
        throw InjectorError.invalidRange
    }
    var range = CFRange()
    guard AXValueGetValue(axValue, .cfRange, &range) else {
        throw InjectorError.invalidRange
    }
    return range
}

func writeSelectedRange(_ element: AXUIElement, _ range: CFRange) throws {
    var mutableRange = range
    guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else {
        throw InjectorError.invalidRange
    }
    try ensureSettable(element, kAXSelectedTextRangeAttribute as CFString)
    let error = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
    guard error == .success else {
        throw InjectorError.attrWriteFailed(kAXSelectedTextRangeAttribute as String, error)
    }
}

func insertText(_ text: String) throws -> String {
    let trimmed = text
    guard !trimmed.isEmpty else {
        throw InjectorError.emptyInput
    }

    let element = try focusedElement()
    let currentValueAny = try copyAttribute(element, kAXValueAttribute as CFString)
    guard let currentValue = currentValueAny as? String else {
        throw InjectorError.emptyValue
    }

    let range = try readSelectedRange(element)
    let currentNSString = currentValue as NSString
    let replacementRange = NSRange(location: range.location, length: range.length)
    guard replacementRange.location != NSNotFound,
          replacementRange.location + replacementRange.length <= currentNSString.length else {
        throw InjectorError.invalidRange
    }

    let insertedNSString = trimmed as NSString
    let updated = currentNSString.replacingCharacters(in: replacementRange, with: trimmed)

    try ensureSettable(element, kAXValueAttribute as CFString)
    let setError = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, updated as CFTypeRef)
    guard setError == .success else {
        throw InjectorError.attrWriteFailed(kAXValueAttribute as String, setError)
    }

    let caret = CFRange(location: replacementRange.location + insertedNSString.length, length: 0)
    try? writeSelectedRange(element, caret)
    return "inserted via AX value replacement"
}

do {
    let text = readInput()
    let message = try insertText(text)
    print(message)
    exit(0)
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
