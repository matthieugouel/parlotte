#!/usr/bin/env swift
// Fast accessibility inspector & driver for Parlotte UI testing.
//
// Build:
//   swiftc .claude/skills/ax-inspect.swift -o .claude/skills/ax-inspect \
//     -framework AppKit -framework ApplicationServices
//
// Commands:
//   dump                            Dump all text/button/text-field elements
//   first N                         Show first N text elements
//   find TEXT                       Search elements whose value contains TEXT
//   tree [--json]                   Full structured tree (pretty or JSON)
//   select ROOM                     Select a sidebar room by displayed name
//   click-button X1 Y1 X2 Y2        Click the first AXButton in a bounding box
//   click-text LABEL                Click the first AXButton whose title/desc contains LABEL
//   set-field QUERY VALUE           Focus the matching AXTextField/AXTextArea, clear it, then type VALUE via real keystrokes (so SwiftUI @State updates).
//   type VALUE                      Type VALUE via real keystrokes into whatever element currently has focus.
//   press KEY                       Send a key press. Supports modifiers (cmd+k, shift+tab, ctrl+alt+a).
//                                   Keys: return, escape, tab, space, delete, up, down, left, right, home, end, a-z, 0-9
//   wait-for TEXT [TIMEOUT]         Poll until TEXT appears (timeout in seconds, default 5). Exits 0 on match, 1 on timeout.

import AppKit
import ApplicationServices
import Foundation

// MARK: - App / element helpers

func getParlotteApp() -> (AXUIElement, pid_t)? {
    let apps = NSWorkspace.shared.runningApplications
    guard let parlotte = apps.first(where: { $0.localizedName == "Parlotte" }) else {
        fputs("Parlotte is not running\n", stderr)
        return nil
    }
    return (AXUIElementCreateApplication(parlotte.processIdentifier), parlotte.processIdentifier)
}

func getWindow(_ app: AXUIElement) -> AXUIElement? {
    var windows: CFTypeRef?
    AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows)
    guard let arr = windows as? [AXUIElement], let win = arr.first else { return nil }
    return win
}

func getAttribute(_ elem: AXUIElement, _ attr: String) -> CFTypeRef? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(elem, attr as CFString, &value)
    return value
}

func getStringAttr(_ elem: AXUIElement, _ attr: String) -> String? {
    guard let val = getAttribute(elem, attr) else { return nil }
    return val as? String
}

func getChildren(_ elem: AXUIElement) -> [AXUIElement] {
    guard let children = getAttribute(elem, kAXChildrenAttribute) as? [AXUIElement] else { return [] }
    return children
}

func getPosition(_ elem: AXUIElement) -> (Double, Double)? {
    var pos: CFTypeRef?
    AXUIElementCopyAttributeValue(elem, kAXPositionAttribute as CFString, &pos)
    guard let axValue = pos else { return nil }
    var point = CGPoint.zero
    AXValueGetValue(axValue as! AXValue, .cgPoint, &point)
    return (Double(point.x), Double(point.y))
}

func getSize(_ elem: AXUIElement) -> (Double, Double)? {
    var sz: CFTypeRef?
    AXUIElementCopyAttributeValue(elem, kAXSizeAttribute as CFString, &sz)
    guard let axValue = sz else { return nil }
    var size = CGSize.zero
    AXValueGetValue(axValue as! AXValue, .cgSize, &size)
    return (Double(size.width), Double(size.height))
}

struct TextElement {
    let value: String
    let role: String
}

/// BFS walk of the accessibility tree. Much faster than recursive traversal.
func collectTexts(_ root: AXUIElement) -> [TextElement] {
    var result: [TextElement] = []
    var queue: [AXUIElement] = [root]
    while !queue.isEmpty {
        let elem = queue.removeFirst()
        let role = getStringAttr(elem, kAXRoleAttribute) ?? ""
        if role == "AXStaticText" || role == "AXButton" || role == "AXTextField" || role == "AXTextArea" {
            if let value = getStringAttr(elem, kAXValueAttribute), !value.isEmpty {
                result.append(TextElement(value: value, role: role))
            } else if let title = getStringAttr(elem, kAXTitleAttribute), !title.isEmpty {
                result.append(TextElement(value: title, role: role))
            }
        }
        queue.append(contentsOf: getChildren(elem))
    }
    return result
}

func collectAllElements(_ root: AXUIElement) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var queue: [AXUIElement] = [root]
    while !queue.isEmpty {
        let elem = queue.removeFirst()
        result.append(elem)
        queue.append(contentsOf: getChildren(elem))
    }
    return result
}

/// Collect all descriptive strings on an element. Used by match helpers.
func elementHaystack(_ elem: AXUIElement) -> String {
    var parts: [String] = []
    for attr in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute,
                 kAXPlaceholderValueAttribute, kAXHelpAttribute, kAXRoleDescriptionAttribute] {
        if let s = getStringAttr(elem, attr), !s.isEmpty {
            parts.append(s)
        }
    }
    return parts.joined(separator: " | ")
}

// MARK: - Keycode map

let keyCodeMap: [String: CGKeyCode] = [
    "return": 0x24, "enter": 0x24,
    "escape": 0x35, "esc": 0x35,
    "tab": 0x30,
    "space": 0x31,
    "delete": 0x33, "backspace": 0x33,
    "forwarddelete": 0x75,
    "up": 0x7E, "down": 0x7D, "left": 0x7B, "right": 0x7C,
    "home": 0x73, "end": 0x77,
    "pageup": 0x74, "pagedown": 0x79,
    // Letters (US layout)
    "a": 0x00, "b": 0x0B, "c": 0x08, "d": 0x02, "e": 0x0E, "f": 0x03,
    "g": 0x05, "h": 0x04, "i": 0x22, "j": 0x26, "k": 0x28, "l": 0x25,
    "m": 0x2E, "n": 0x2D, "o": 0x1F, "p": 0x23, "q": 0x0C, "r": 0x0F,
    "s": 0x01, "t": 0x11, "u": 0x20, "v": 0x09, "w": 0x0D, "x": 0x07,
    "y": 0x10, "z": 0x06,
    // Digits
    "0": 0x1D, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15,
    "5": 0x17, "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19,
]

/// Post a CGEvent keystroke targeting the given pid.
func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = [], pid: pid_t) {
    let source = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
    let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    down?.flags = flags
    up?.flags = flags
    down?.postToPid(pid)
    up?.postToPid(pid)
}

/// Type a string by posting one CGEvent per character via
/// `keyboardSetUnicodeString`. This flows through the standard input
/// pipeline (unlike setting AXValue directly), so SwiftUI's @State bindings
/// update correctly.
///
/// Posts characters in small batches with generous pacing to avoid
/// overwhelming the event queue.
func typeUnicode(_ text: String, pid: pid_t) {
    let source = CGEventSource(stateID: .hidSystemState)
    for char in text {
        let utf16 = Array(String(char).utf16)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { continue }
        utf16.withUnsafeBufferPointer { buf in
            if let base = buf.baseAddress {
                down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: base)
                up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: base)
            }
        }
        down.postToPid(pid)
        usleep(3_000)
        up.postToPid(pid)
        usleep(3_000)
    }
}

/// Focus a field and clear its contents via AX API, then let the caller
/// type fresh text via keystrokes.
func focusAndClear(_ field: AXUIElement, pid: pid_t) {
    AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    // Wait for focus to settle.
    usleep(50_000)
    // Clear the field via AXValue — this doesn't need binding propagation,
    // it just resets the editor contents.
    AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, "" as CFTypeRef)
    usleep(20_000)
}

func parsePress(_ spec: String) -> (CGKeyCode, CGEventFlags)? {
    // e.g. "cmd+k", "shift+tab", "return", "ctrl+alt+a"
    let parts = spec.lowercased().split(separator: "+").map(String.init)
    guard let keyName = parts.last, let keyCode = keyCodeMap[keyName] else { return nil }

    var flags: CGEventFlags = []
    for mod in parts.dropLast() {
        switch mod {
        case "cmd", "command", "meta": flags.insert(.maskCommand)
        case "shift": flags.insert(.maskShift)
        case "ctrl", "control": flags.insert(.maskControl)
        case "alt", "option", "opt": flags.insert(.maskAlternate)
        case "fn": flags.insert(.maskSecondaryFn)
        default: return nil
        }
    }
    return (keyCode, flags)
}

// MARK: - Match helpers

func firstEditableMatch(_ root: AXUIElement, query: String) -> AXUIElement? {
    let queryLower = query.lowercased()
    for elem in collectAllElements(root) {
        let role = getStringAttr(elem, kAXRoleAttribute) ?? ""
        guard role == "AXTextField" || role == "AXTextArea" else { continue }
        let haystack = elementHaystack(elem).lowercased()
        if haystack.contains(queryLower) {
            return elem
        }
    }
    return nil
}

func firstButtonMatching(_ root: AXUIElement, query: String) -> AXUIElement? {
    let queryLower = query.lowercased()
    for elem in collectAllElements(root) {
        let role = getStringAttr(elem, kAXRoleAttribute) ?? ""
        guard role == "AXButton" else { continue }
        let haystack = elementHaystack(elem).lowercased()
        if haystack.contains(queryLower) {
            return elem
        }
    }
    return nil
}

// MARK: - Tree dump

func buildTreeDict(_ elem: AXUIElement) -> [String: Any] {
    var dict: [String: Any] = [:]
    if let role = getStringAttr(elem, kAXRoleAttribute) { dict["role"] = role }
    if let title = getStringAttr(elem, kAXTitleAttribute), !title.isEmpty { dict["title"] = title }
    if let value = getStringAttr(elem, kAXValueAttribute), !value.isEmpty { dict["value"] = value }
    if let desc = getStringAttr(elem, kAXDescriptionAttribute), !desc.isEmpty { dict["description"] = desc }
    if let (x, y) = getPosition(elem) { dict["position"] = [x, y] }
    if let (w, h) = getSize(elem) { dict["size"] = [w, h] }

    let children = getChildren(elem)
    if !children.isEmpty {
        dict["children"] = children.map(buildTreeDict)
    }
    return dict
}

func printTree(_ elem: AXUIElement, indent: Int = 0) {
    let pad = String(repeating: "  ", count: indent)
    let role = getStringAttr(elem, kAXRoleAttribute) ?? "?"
    var line = "\(pad)[\(role)]"
    if let title = getStringAttr(elem, kAXTitleAttribute), !title.isEmpty { line += " title=\"\(title)\"" }
    if let value = getStringAttr(elem, kAXValueAttribute), !value.isEmpty {
        let v = value.count > 60 ? String(value.prefix(57)) + "..." : value
        line += " value=\"\(v)\""
    }
    if let desc = getStringAttr(elem, kAXDescriptionAttribute), !desc.isEmpty { line += " desc=\"\(desc)\"" }
    if let (x, y) = getPosition(elem) { line += " pos=(\(Int(x)),\(Int(y)))" }
    print(line)
    for child in getChildren(elem) {
        printTree(child, indent: indent + 1)
    }
}

// MARK: - Commands

let args = CommandLine.arguments
let command = args.count > 1 ? args[1] : "dump"

guard let (app, pid) = getParlotteApp(), let window = getWindow(app) else {
    exit(1)
}

switch command {
case "dump":
    let texts = collectTexts(window)
    print("total: \(texts.count)")
    for (i, t) in texts.enumerated() {
        print("\(i + 1) [\(t.role)]: \(t.value)")
    }

case "first":
    let n = args.count > 2 ? Int(args[2]) ?? 20 : 20
    let texts = collectTexts(window)
    print("total: \(texts.count)")
    for (i, t) in texts.enumerated().prefix(n) {
        print("\(i + 1) [\(t.role)]: \(t.value)")
    }

case "find":
    let query = args.count > 2 ? args[2] : ""
    let texts = collectTexts(window)
    var hits = 0
    for (i, t) in texts.enumerated() {
        if t.value.localizedCaseInsensitiveContains(query) {
            print("\(i + 1) [\(t.role)]: \(t.value)")
            hits += 1
        }
    }
    if hits == 0 { exit(1) }

case "tree":
    if args.dropFirst(2).contains("--json") {
        let dict = buildTreeDict(window)
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
           let s = String(data: data, encoding: .utf8) {
            print(s)
        }
    } else {
        printTree(window)
    }

case "click-button":
    guard args.count >= 6,
          let x1 = Double(args[2]), let y1 = Double(args[3]),
          let x2 = Double(args[4]), let y2 = Double(args[5]) else {
        fputs("Usage: click-button x1 y1 x2 y2\n", stderr)
        exit(1)
    }
    for elem in collectAllElements(window) {
        let role = getStringAttr(elem, kAXRoleAttribute) ?? ""
        if role == "AXButton", let (px, py) = getPosition(elem),
           px >= x1, px <= x2, py >= y1, py <= y2 {
            AXUIElementPerformAction(elem, kAXPressAction as CFString)
            print("clicked button at \(px),\(py)")
            exit(0)
        }
    }
    print("no button found in range")
    exit(1)

case "click-text":
    let query = args.count > 2 ? args[2] : ""
    guard !query.isEmpty else {
        fputs("Usage: click-text LABEL\n", stderr)
        exit(1)
    }
    guard let button = firstButtonMatching(window, query: query) else {
        print("no button matching '\(query)'")
        exit(1)
    }
    let err = AXUIElementPerformAction(button, kAXPressAction as CFString)
    if err == .success {
        let desc = getStringAttr(button, kAXTitleAttribute) ?? getStringAttr(button, kAXDescriptionAttribute) ?? "?"
        print("clicked '\(desc)'")
    } else {
        fputs("press failed: \(err.rawValue)\n", stderr)
        exit(1)
    }

case "select":
    let roomName = args.count > 2 ? args[2] : ""
    for elem in collectAllElements(window) {
        let role = getStringAttr(elem, kAXRoleAttribute) ?? ""
        guard role == "AXRow" else { continue }
        for child in collectAllElements(elem) {
            let childRole = getStringAttr(child, kAXRoleAttribute) ?? ""
            if childRole == "AXStaticText",
               getStringAttr(child, kAXValueAttribute) == roomName {
                var settable: DarwinBoolean = false
                AXUIElementIsAttributeSettable(elem, kAXSelectedAttribute as CFString, &settable)
                if settable.boolValue {
                    AXUIElementSetAttributeValue(elem, kAXSelectedAttribute as CFString, true as CFTypeRef)
                    print("selected \(roomName)")
                    exit(0)
                }
            }
        }
    }
    print("room '\(roomName)' not found")
    exit(1)

case "set-field":
    guard args.count >= 4 else {
        fputs("Usage: set-field QUERY VALUE\n", stderr)
        exit(1)
    }
    let query = args[2]
    let value = args[3]
    guard let field = firstEditableMatch(window, query: query) else {
        print("no text field matching '\(query)'")
        exit(1)
    }
    // Bring Parlotte to the foreground so keystrokes are delivered.
    if let running = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == pid }) {
        running.activate(options: [])
        usleep(20_000)
    }
    focusAndClear(field, pid: pid)
    typeUnicode(value, pid: pid)
    print("set '\(query)' to '\(value)'")

case "type":
    guard args.count >= 3 else {
        fputs("Usage: type VALUE\n", stderr)
        exit(1)
    }
    let value = args[2]
    if let running = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == pid }) {
        running.activate(options: [])
        usleep(20_000)
    }
    typeUnicode(value, pid: pid)
    print("typed '\(value)'")

case "press":
    guard args.count >= 3 else {
        fputs("Usage: press KEY (e.g. return, escape, cmd+k)\n", stderr)
        exit(1)
    }
    guard let (keyCode, flags) = parsePress(args[2]) else {
        fputs("unknown key spec: \(args[2])\n", stderr)
        exit(1)
    }
    // Bring Parlotte to the foreground so keystrokes target it.
    if let running = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == pid }) {
        running.activate(options: [])
        usleep(20_000)
    }
    postKey(keyCode, flags: flags, pid: pid)
    print("pressed \(args[2])")

case "wait-for":
    guard args.count >= 3 else {
        fputs("Usage: wait-for TEXT [TIMEOUT_SECONDS]\n", stderr)
        exit(1)
    }
    let query = args[2]
    let timeout = args.count > 3 ? (Double(args[3]) ?? 5) : 5
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        // Re-query the window each iteration — the tree can change.
        guard let liveWindow = getWindow(app) else { break }
        for t in collectTexts(liveWindow) {
            if t.value.localizedCaseInsensitiveContains(query) {
                print("found: \(t.value)")
                exit(0)
            }
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    print("timeout: '\(query)' not found within \(timeout)s")
    exit(1)

default:
    fputs("Unknown command: \(command)\n", stderr)
    fputs("""
    Commands: dump | first N | find TEXT | tree [--json]
              select ROOM | click-button X1 Y1 X2 Y2 | click-text LABEL
              set-field QUERY VALUE | type VALUE | press KEY
              wait-for TEXT [TIMEOUT]
    """, stderr)
    exit(1)
}
