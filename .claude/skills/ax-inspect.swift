#!/usr/bin/env swift
// Fast accessibility inspector for Parlotte UI testing.
// Usage: swift scripts/ax-inspect.swift [command]
// Commands:
//   dump           - Dump all text elements
//   first N        - Show first N text elements (after header)
//   find TEXT      - Search for text containing TEXT
//   click-button X1 Y1 X2 Y2 - Click first AXButton in the coordinate range
//   select ROOM    - Select a room by name in the sidebar

import AppKit
import ApplicationServices
import Foundation

func getParlotteApp() -> AXUIElement? {
    let apps = NSWorkspace.shared.runningApplications
    guard let parlotte = apps.first(where: { $0.localizedName == "Parlotte" }) else {
        fputs("Parlotte is not running\n", stderr)
        return nil
    }
    return AXUIElementCreateApplication(parlotte.processIdentifier)
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

struct TextElement {
    let value: String
    let role: String
}

// Walk the tree iteratively (BFS) — much faster than recursive
func collectTexts(_ root: AXUIElement) -> [TextElement] {
    var result: [TextElement] = []
    var queue: [AXUIElement] = [root]

    while !queue.isEmpty {
        let elem = queue.removeFirst()
        let role = getStringAttr(elem, kAXRoleAttribute) ?? ""

        if role == "AXStaticText" || role == "AXButton" || role == "AXTextField" {
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

// MARK: - Commands

let args = CommandLine.arguments
let command = args.count > 1 ? args[1] : "dump"

guard let app = getParlotteApp(), let window = getWindow(app) else {
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
    for (i, t) in texts.enumerated() {
        if t.value.localizedCaseInsensitiveContains(query) {
            print("\(i + 1) [\(t.role)]: \(t.value)")
        }
    }

case "click-button":
    // click-button x1 y1 x2 y2 — click first AXButton within the bounding box
    guard args.count >= 6,
          let x1 = Double(args[2]), let y1 = Double(args[3]),
          let x2 = Double(args[4]), let y2 = Double(args[5]) else {
        fputs("Usage: click-button x1 y1 x2 y2\n", stderr)
        exit(1)
    }
    let allElems = collectAllElements(window)
    for elem in allElems {
        let role = getStringAttr(elem, kAXRoleAttribute) ?? ""
        if role == "AXButton", let (px, py) = getPosition(elem) {
            if px >= x1 && px <= x2 && py >= y1 && py <= y2 {
                AXUIElementPerformAction(elem, kAXPressAction as CFString)
                print("clicked button at \(px),\(py)")
                exit(0)
            }
        }
    }
    print("no button found in range")

case "select":
    // select ROOM_NAME — select a room in the sidebar
    let roomName = args.count > 2 ? args[2] : ""
    let allElems = collectAllElements(window)
    for elem in allElems {
        let role = getStringAttr(elem, kAXRoleAttribute) ?? ""
        if role == "AXRow" {
            let children = collectAllElements(elem)
            for child in children {
                let childRole = getStringAttr(child, kAXRoleAttribute) ?? ""
                if childRole == "AXStaticText" {
                    let val = getStringAttr(child, kAXValueAttribute) ?? ""
                    if val == roomName {
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
        }
    }
    print("room '\(roomName)' not found")

default:
    fputs("Unknown command: \(command)\n", stderr)
    fputs("Commands: dump, first N, find TEXT, click-button X1 Y1 X2 Y2, select ROOM\n", stderr)
    exit(1)
}
