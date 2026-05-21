#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/build/DerivedData/Build/Products/Debug/LexiRay.app"
TEXT_FILE="/tmp/lexiray-ui-smoke.txt"

cd "$ROOT_DIR"

./script/build_and_run.sh --verify >/dev/null

swift - "$APP_BUNDLE" "$TEXT_FILE" <<'SWIFT'
import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation

let appBundle = CommandLine.arguments[1]
let textFile = CommandLine.arguments[2]

struct SmokeHotKey: Decodable {
  let keyCode: UInt32
  let modifiers: UInt32
}

func loadTranslateHotKey() -> (keyCode: CGKeyCode, flags: CGEventFlags) {
  let fallback = SmokeHotKey(
    keyCode: UInt32(kVK_ANSI_T),
    modifiers: UInt32(cmdKey) | UInt32(optionKey) | UInt32(shiftKey)
  )
  let domain = UserDefaults.standard.persistentDomain(forName: "io.github.tensornull.lexiray")
  let data = domain?["translateHotKey"] as? Data
  let hotKey = data.flatMap { try? JSONDecoder().decode(SmokeHotKey.self, from: $0) } ?? fallback

  var flags: CGEventFlags = []
  if hotKey.modifiers & UInt32(controlKey) != 0 {
    flags.insert(.maskControl)
  }
  if hotKey.modifiers & UInt32(optionKey) != 0 {
    flags.insert(.maskAlternate)
  }
  if hotKey.modifiers & UInt32(shiftKey) != 0 {
    flags.insert(.maskShift)
  }
  if hotKey.modifiers & UInt32(cmdKey) != 0 {
    flags.insert(.maskCommand)
  }

  return (CGKeyCode(hotKey.keyCode), flags)
}

try "LexiRay smoke selection text.\n中文划词翻译测试。\n".write(
  toFile: textFile,
  atomically: true,
  encoding: .utf8
)

func allWindows() -> [[String: Any]] {
  CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
}

func windowOwner(_ window: [String: Any]) -> String {
  window[kCGWindowOwnerName as String] as? String ?? ""
}

func windowName(_ window: [String: Any]) -> String {
  window[kCGWindowName as String] as? String ?? ""
}

func windowBounds(_ window: [String: Any]) -> CGRect {
  guard let dictionary = window[kCGWindowBounds as String] as? NSDictionary else {
    return .zero
  }
  return CGRect(dictionaryRepresentation: dictionary) ?? .zero
}

func windows(owner: String, name: String? = nil) -> [CGRect] {
  allWindows().compactMap { window in
    guard windowOwner(window) == owner else {
      return nil
    }
    if let name, windowName(window) != name {
      return nil
    }
    return windowBounds(window)
  }
}

func panelWindows() -> [CGRect] {
  windows(owner: "LexiRay").filter { rect in
    rect.width >= 560 && rect.width <= 720 && rect.height >= 250 && rect.height <= 650
  }
}

func lexirayMainWindows() -> [CGRect] {
  windows(owner: "LexiRay").filter { rect in
    rect.width >= 650 && rect.height >= 420
  }
}

func appIsRunning(bundleIdentifier: String) -> Bool {
  !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
}

func panelAXSizes() -> [CGSize] {
  lexirayAXElements().compactMap { element in
    var sizeValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
          let sizeValue
    else {
      return nil
    }

    let axValue = sizeValue as! AXValue
    var size = CGSize.zero
    guard AXValueGetValue(axValue, .cgSize, &size),
          size.width >= 560 && size.width <= 720 && size.height >= 250 && size.height <= 650
    else {
      return nil
    }
    return size
  }
}

func lexirayAXElements() -> [AXUIElement] {
  guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.tensornull.lexiray").first else {
    return []
  }

  let root = AXUIElementCreateApplication(app.processIdentifier)
  func collect(_ element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    var elements = [element]
    guard depth < 8 else {
      return elements
    }

    var value: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
       let children = value as? [AXUIElement] {
      for child in children {
        elements += collect(child, depth: depth + 1)
      }
    }

    return elements
  }

  return collect(root)
}

func axString(_ element: AXUIElement, _ attribute: String) -> String {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
    return ""
  }
  return value as? String ?? ""
}

func axFrame(_ element: AXUIElement) -> CGRect? {
  var positionValue: CFTypeRef?
  var sizeValue: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
        let positionValue,
        let sizeValue
  else {
    return nil
  }

  var position = CGPoint.zero
  var size = CGSize.zero
  guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
  else {
    return nil
  }

  return CGRect(origin: position, size: size)
}

func floatingSourceEditor() -> AXUIElement? {
  lexirayAXElements().first { element in
    axString(element, kAXIdentifierAttribute) == "FloatingPanelSourceEditor"
      || axString(element, kAXDescriptionAttribute) == "Source Text"
  }
}

func focusAndReplaceSourceText(_ text: String) -> Bool {
  guard let editor = floatingSourceEditor() else {
    return false
  }

  if AXUIElementSetAttributeValue(editor, kAXFocusedAttribute as CFString, kCFBooleanTrue) != .success,
     let frame = axFrame(editor) {
    click(CGPoint(x: frame.midX, y: frame.midY))
  }

  RunLoop.current.run(until: Date().addingTimeInterval(0.2))

  if AXUIElementSetAttributeValue(editor, kAXValueAttribute as CFString, text as CFString) == .success {
    return true
  }

  NSPasteboard.general.clearContents()
  NSPasteboard.general.setString(text, forType: .string)
  press(0, flags: .maskCommand)
  RunLoop.current.run(until: Date().addingTimeInterval(0.05))
  press(9, flags: .maskCommand)
  RunLoop.current.run(until: Date().addingTimeInterval(0.2))

  return true
}

func pressLexiRayButton(description: String) -> Bool {
  guard let button = lexirayAXElements().first(where: { element in
    axString(element, kAXRoleAttribute) == "AXButton"
      && axString(element, kAXDescriptionAttribute) == description
  }) else {
    return false
  }

  return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
}

func waitFor(_ description: String, timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    if condition() {
      return true
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
  }
  print("UI_SMOKE_TIMEOUT: \(description)")
  return false
}

func activate(bundleIdentifier: String) {
  guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
    return
  }

  if #available(macOS 14.0, *) {
    app.activate(options: [.activateAllWindows])
  } else {
    app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
  }
}

func click(_ point: CGPoint) {
  let source = CGEventSource(stateID: .hidSystemState)
  CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
    .post(tap: .cghidEventTap)
  RunLoop.current.run(until: Date().addingTimeInterval(0.05))
  CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?
    .post(tap: .cghidEventTap)
  CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?
    .post(tap: .cghidEventTap)
}

func press(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
  let source = CGEventSource(stateID: .hidSystemState)
  let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
  let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
  down?.flags = flags
  up?.flags = flags
  down?.post(tap: .cghidEventTap)
  up?.post(tap: .cghidEventTap)
}

func closeLexiRayMainWindow() -> Bool {
  guard let window = lexirayMainWindows().first else {
    return false
  }

  click(CGPoint(x: window.minX + 26, y: window.minY + 26))
  return true
}

guard waitFor("LexiRay main window after launch", timeout: 10, { !lexirayMainWindows().isEmpty }) else {
  print("UI_SMOKE_FAIL: LexiRay main window did not appear after launch")
  exit(1)
}

activate(bundleIdentifier: "io.github.tensornull.lexiray")
RunLoop.current.run(until: Date().addingTimeInterval(0.3))
guard closeLexiRayMainWindow() else {
  print("UI_SMOKE_FAIL: LexiRay main window was not reachable")
  exit(1)
}

guard waitFor("LexiRay main window closes", timeout: 5, { lexirayMainWindows().isEmpty }) else {
  print("UI_SMOKE_FAIL: LexiRay main window did not close")
  exit(1)
}

guard appIsRunning(bundleIdentifier: "io.github.tensornull.lexiray") else {
  print("UI_SMOKE_FAIL: LexiRay quit after closing the main window")
  exit(1)
}

NSWorkspace.shared.open(
  [URL(fileURLWithPath: textFile)],
  withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
  configuration: NSWorkspace.OpenConfiguration()
) { _, error in
  if let error {
    print("UI_SMOKE_FAIL: failed to open TextEdit: \(error.localizedDescription)")
    exit(1)
  }
}

RunLoop.current.run(until: Date().addingTimeInterval(1))
activate(bundleIdentifier: "com.apple.TextEdit")
RunLoop.current.run(until: Date().addingTimeInterval(0.5))

let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
if frontmost == "com.apple.loginwindow" {
  print("UI_SMOKE_FAIL: GUI session is shielded by loginwindow; unlock/foreground the desktop session and rerun script/ui_smoke.sh")
  exit(2)
}

guard waitFor("TextEdit smoke document", timeout: 10, { !windows(owner: "TextEdit").isEmpty }) else {
  exit(1)
}

let textWindow = windows(owner: "TextEdit", name: "lexiray-ui-smoke.txt").first ?? windows(owner: "TextEdit")[0]
click(CGPoint(x: textWindow.midX, y: textWindow.midY))
RunLoop.current.run(until: Date().addingTimeInterval(0.2))
press(0, flags: .maskCommand)
RunLoop.current.run(until: Date().addingTimeInterval(0.2))
let translateHotKey = loadTranslateHotKey()
press(translateHotKey.keyCode, flags: translateHotKey.flags)

guard waitFor("LexiRay floating panel after translate hotkey", timeout: 20, { !panelWindows().isEmpty }) else {
  print("UI_SMOKE_FAIL: panel did not appear after selecting TextEdit text")
  exit(1)
}

let firstPanel = panelWindows()[0]
let measuredPanelHeight = panelAXSizes().first?.height ?? firstPanel.height
if measuredPanelHeight > 560 {
  print("UI_SMOKE_FAIL: short floating panel is too tall: \(measuredPanelHeight)")
  exit(1)
}

guard waitFor("floating source editor", timeout: 5, { floatingSourceEditor() != nil }) else {
  print("UI_SMOKE_FAIL: source editor was not reachable")
  exit(1)
}

let editedSmokeText = "LexiRay edited smoke text."
guard focusAndReplaceSourceText(editedSmokeText) else {
  print("UI_SMOKE_FAIL: source editor did not accept focus")
  exit(1)
}

guard waitFor("source editor accepts text", timeout: 5, {
  guard let editor = floatingSourceEditor() else {
    return false
  }
  return axString(editor, kAXValueAttribute).contains(editedSmokeText)
}) else {
  print("UI_SMOKE_FAIL: source editor did not accept edited text")
  exit(1)
}

press(36, flags: .maskCommand)
RunLoop.current.run(until: Date().addingTimeInterval(0.5))

click(CGPoint(x: max(30, firstPanel.minX - 120), y: max(30, firstPanel.minY - 120)))
guard waitFor("unpinned panel hide after outside click", { panelWindows().isEmpty }) else {
  print("UI_SMOKE_FAIL: unpinned panel did not hide after outside click")
  exit(1)
}

activate(bundleIdentifier: "com.apple.TextEdit")
RunLoop.current.run(until: Date().addingTimeInterval(0.2))
click(CGPoint(x: textWindow.midX, y: textWindow.midY))
RunLoop.current.run(until: Date().addingTimeInterval(0.2))
press(0, flags: .maskCommand)
RunLoop.current.run(until: Date().addingTimeInterval(0.2))
press(translateHotKey.keyCode, flags: translateHotKey.flags)

guard waitFor("LexiRay floating panel for pin check", timeout: 20, { !panelWindows().isEmpty }) else {
  print("UI_SMOKE_FAIL: panel did not appear for pin check")
  exit(1)
}

guard pressLexiRayButton(description: "Pin") else {
  print("UI_SMOKE_FAIL: pin button was not reachable")
  exit(1)
}

let pinnedPanel = panelWindows()[0]
click(CGPoint(x: max(30, pinnedPanel.minX - 120), y: max(30, pinnedPanel.minY - 120)))
guard waitFor("pinned panel remains after outside click", { !panelWindows().isEmpty }) else {
  print("UI_SMOKE_FAIL: pinned panel hid after outside click")
  exit(1)
}

guard pressLexiRayButton(description: "Close") else {
  print("UI_SMOKE_FAIL: close button was not reachable")
  exit(1)
}

guard waitFor("close button hides pinned panel", { panelWindows().isEmpty }) else {
  print("UI_SMOKE_FAIL: close button did not hide panel")
  exit(1)
}

print("UI_SMOKE_PASS")
SWIFT
