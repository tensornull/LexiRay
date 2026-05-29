#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/build/DerivedData/Build/Products/Debug/LexiRay.app"
TEXT_FILE="/tmp/lexiray-ui-smoke.txt"
LEXIRAY_HOME="$HOME/.lexiray"
PROVIDERS_FILE="$LEXIRAY_HOME/providers.json"
HISTORY_FILE="$LEXIRAY_HOME/history.json"
BACKUP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lexiray-ui-smoke.XXXXXX")"
LEXIRAY_HOME_EXISTED=0
SCREENSHOT_DIR="${LEXIRAY_UI_SMOKE_SCREENSHOT_DIR:-}"

cd "$ROOT_DIR"

if [[ -d "$LEXIRAY_HOME" ]]; then
  LEXIRAY_HOME_EXISTED=1
fi

backup_file() {
  local source="$1"
  local name="$2"
  if [[ -f "$source" ]]; then
    cp "$source" "$BACKUP_DIR/$name"
  fi
}

stop_workspace_app() {
  (pgrep -x "LexiRay" || true) | while read -r pid; do
    [[ -n "$pid" ]] || continue
    local process_path
    process_path="$(ps -p "$pid" -o args=)"
    case "$process_path" in
      "$APP_BUNDLE"/Contents/MacOS/LexiRay*) kill "$pid" >/dev/null 2>&1 || true ;;
    esac
  done

  sleep 1

  (pgrep -x "LexiRay" || true) | while read -r pid; do
    [[ -n "$pid" ]] || continue
    local process_path
    process_path="$(ps -p "$pid" -o args=)"
    case "$process_path" in
      "$APP_BUNDLE"/Contents/MacOS/LexiRay*) kill -9 "$pid" >/dev/null 2>&1 || true ;;
    esac
  done
}

restore_file() {
  local target="$1"
  local name="$2"
  if [[ -f "$BACKUP_DIR/$name" ]]; then
    mkdir -p "$(dirname "$target")"
    cp "$BACKUP_DIR/$name" "$target"
  else
    rm -f "$target"
  fi
}

cleanup() {
  stop_workspace_app
  restore_file "$PROVIDERS_FILE" providers.json
  restore_file "$HISTORY_FILE" history.json
  if [[ "$LEXIRAY_HOME_EXISTED" == 0 ]]; then
    rmdir "$LEXIRAY_HOME" 2>/dev/null || true
  fi
  rm -rf "$BACKUP_DIR"
}
trap cleanup EXIT

backup_file "$PROVIDERS_FILE" providers.json
backup_file "$HISTORY_FILE" history.json
mkdir -p "$LEXIRAY_HOME"
cat >"$PROVIDERS_FILE" <<'JSON'
{
  "version": 2,
  "preferredProvider": "systemDictionary",
  "providerOrder": [
    "systemDictionary"
  ],
  "providers": {
    "systemDictionary": {
      "providerID": "systemDictionary",
      "displayName": "",
      "baseURL": "",
      "model": "",
      "isEnabled": true,
      "apiKey": ""
    }
  }
}
JSON
cat >"$HISTORY_FILE" <<'JSON'
{
  "version": 1,
  "entries": [
    {
      "id": "11111111-1111-1111-1111-111111111111",
      "createdAt": 801000000,
      "request": {
        "text": "LexiRay seeded history text.",
        "llmInputText": "LexiRay seeded history text.",
        "sourceLanguage": "en",
        "targetLanguage": "zh-Hans",
        "selectionSource": "manual"
      },
      "entries": [
        {
          "providerConfigurationID": "systemDictionary",
          "providerID": "systemDictionary",
          "providerName": "System Dictionary",
          "status": {
            "type": "success",
            "result": {
              "translatedText": "Seeded history result.",
              "detectedLanguage": "en",
              "createdAt": 801000000
            }
          }
        }
      ]
    }
  ]
}
JSON
chmod 600 "$PROVIDERS_FILE" "$HISTORY_FILE"
if [[ -n "$SCREENSHOT_DIR" ]]; then
  mkdir -p "$SCREENSHOT_DIR"
fi

./script/build_and_run.sh --verify >/dev/null

swift - "$APP_BUNDLE" "$TEXT_FILE" "$SCREENSHOT_DIR" <<'SWIFT'
import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation

let appBundle = CommandLine.arguments[1]
let textFile = CommandLine.arguments[2]
let screenshotDir = CommandLine.arguments[3]

struct SmokeHotKey: Decodable {
  let keyCode: UInt32
  let modifiers: UInt32
}

func loadTranslateHotKey() -> (keyCode: CGKeyCode, flags: CGEventFlags) {
  let fallback = SmokeHotKey(
    keyCode: UInt32(kVK_ANSI_A),
    modifiers: UInt32(controlKey) | UInt32(optionKey)
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

func windowID(_ window: [String: Any]) -> UInt32? {
  window[kCGWindowNumber as String] as? UInt32
}

func lexirayMainWindowInfo() -> [String: Any]? {
  allWindows().first { window in
    guard windowOwner(window) == "LexiRay" else {
      return false
    }
    let rect = windowBounds(window)
    return rect.width >= 650 && rect.height >= 420
  }
}

func floatingPanelWindowInfo() -> [String: Any]? {
  allWindows().first { window in
    guard windowOwner(window) == "LexiRay" else {
      return false
    }
    let rect = windowBounds(window)
    return rect.width >= 560 && rect.width <= 980 && rect.height >= 250 && rect.height <= 780
  }
}

func captureWindowIfRequested(_ window: [String: Any]?, name: String) {
  guard !screenshotDir.isEmpty,
        let window,
        let id = windowID(window)
  else {
    return
  }

  let outputURL = URL(fileURLWithPath: screenshotDir).appendingPathComponent("\(name).png")
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
  process.arguments = ["-x", "-l", "\(id)", outputURL.path]
  do {
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
      print("UI_SMOKE_FAIL: failed to capture \(name)")
      exit(1)
    }
  } catch {
    print("UI_SMOKE_FAIL: failed to capture \(name): \(error.localizedDescription)")
    exit(1)
  }
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
    rect.width >= 560 && rect.width <= 980 && rect.height >= 250 && rect.height <= 780
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
          size.width >= 560 && size.width <= 980 && size.height >= 250 && size.height <= 780
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
    guard depth < 14 else {
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

func axElement(identifier: String) -> AXUIElement? {
  lexirayAXElements().first { element in
    axString(element, kAXIdentifierAttribute) == identifier
  }
}

func axVisibleText(_ element: AXUIElement) -> String {
  [
    axString(element, kAXTitleAttribute),
    axString(element, kAXDescriptionAttribute),
    axString(element, kAXValueAttribute)
  ]
  .joined(separator: " ")
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
  let elements = lexirayAXElements()
  return elements.first { element in
    axString(element, kAXRoleAttribute) == "AXTextArea"
      && axString(element, kAXIdentifierAttribute) == "FloatingPanelSourceEditor"
  } ?? elements.first { element in
    axString(element, kAXIdentifierAttribute) == "FloatingPanelSourceEditor"
      || axString(element, kAXDescriptionAttribute) == "Source Text"
  }
}

func floatingSourceText() -> String {
  guard let editor = floatingSourceEditor() else {
    return ""
  }

  return axString(editor, kAXValueAttribute)
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

func focusFloatingSourceEditor() -> Bool {
  guard let editor = floatingSourceEditor() else {
    return false
  }

  _ = AXUIElementSetAttributeValue(editor, kAXFocusedAttribute as CFString, kCFBooleanTrue)
  if let frame = axFrame(editor) {
    click(CGPoint(x: frame.midX, y: frame.midY))
  }

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

func pressLexiRayButton(identifier: String) -> Bool {
  guard let button = lexirayAXElements().first(where: { element in
    axString(element, kAXRoleAttribute) == "AXButton"
      && axString(element, kAXIdentifierAttribute) == identifier
  }) else {
    return false
  }

  if AXUIElementPerformAction(button, kAXPressAction as CFString) == .success {
    return true
  }

  guard let frame = axFrame(button) else {
    return false
  }

  click(CGPoint(x: frame.midX, y: frame.midY))
  return true
}

func pressLexiRayElement(identifier: String) -> Bool {
  guard let element = axElement(identifier: identifier) else {
    return false
  }

  if let frame = axFrame(element) {
    click(CGPoint(x: frame.midX, y: frame.midY))
    return true
  }

  return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
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

if !waitFor("LexiRay main window after launch", timeout: 10, { !lexirayMainWindows().isEmpty }) {
  NSWorkspace.shared.open(URL(fileURLWithPath: appBundle))
}

guard waitFor("LexiRay main window after reopen", timeout: 5, { !lexirayMainWindows().isEmpty }) else {
  print("UI_SMOKE_FAIL: LexiRay main window did not appear after launch")
  exit(1)
}

activate(bundleIdentifier: "io.github.tensornull.lexiray")
RunLoop.current.run(until: Date().addingTimeInterval(0.3))
captureWindowIfRequested(lexirayMainWindowInfo(), name: "dashboard")
activate(bundleIdentifier: "io.github.tensornull.lexiray")
RunLoop.current.run(until: Date().addingTimeInterval(0.2))

guard pressLexiRayElement(identifier: "SidebarProviders") else {
  print("UI_SMOKE_FAIL: providers sidebar item was not reachable")
  exit(1)
}

guard waitFor("provider header and add button", timeout: 5, {
  axElement(identifier: "ProviderHeaderTitle") != nil && axElement(identifier: "ProviderAddMenuButton") != nil
}) else {
  print("UI_SMOKE_FAIL: provider header controls were not reachable")
  exit(1)
}

if let headerFrame = axElement(identifier: "ProviderHeaderTitle").flatMap(axFrame),
   let addFrame = axElement(identifier: "ProviderAddMenuButton").flatMap(axFrame),
   abs(headerFrame.midY - addFrame.midY) > 14 {
  print("UI_SMOKE_FAIL: add provider button is not aligned with provider title")
  exit(1)
}

if lexirayAXElements().contains(where: { axVisibleText($0).contains("<->") }) {
  print("UI_SMOKE_FAIL: provider page still shows a language direction pill")
  exit(1)
}
captureWindowIfRequested(lexirayMainWindowInfo(), name: "providers")

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

let translateHotKey = loadTranslateHotKey()
activate(bundleIdentifier: "io.github.tensornull.lexiray")
RunLoop.current.run(until: Date().addingTimeInterval(0.2))
press(translateHotKey.keyCode, flags: translateHotKey.flags)
guard waitFor("empty selection opens blank composer", timeout: 5, { !panelWindows().isEmpty && floatingSourceEditor() != nil }) else {
  print("UI_SMOKE_FAIL: empty selection did not open a blank floating composer")
  exit(1)
}
if lexirayAXElements().contains(where: { axVisibleText($0).contains("No Translation") }) {
  print("UI_SMOKE_FAIL: empty selection shows a no-translation warning")
  exit(1)
}
guard pressLexiRayButton(identifier: "xmark") else {
  print("UI_SMOKE_FAIL: close button was not reachable after empty selection")
  exit(1)
}
guard waitFor("blank composer closes", timeout: 5, { panelWindows().isEmpty }) else {
  print("UI_SMOKE_FAIL: blank composer did not close")
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
let seededHistoryText = "LexiRay seeded history text."
let selectedHistoryText = "LexiRay smoke selection text."
guard focusAndReplaceSourceText(editedSmokeText) else {
  print("UI_SMOKE_FAIL: source editor did not accept focus")
  exit(1)
}

guard waitFor("source editor accepts text", timeout: 5, {
  floatingSourceText().contains(editedSmokeText)
}) else {
  print("UI_SMOKE_FAIL: source editor did not accept edited text")
  exit(1)
}

guard pressLexiRayButton(identifier: "xmark.circle.fill") else {
  print("UI_SMOKE_FAIL: clear source button was not reachable")
  exit(1)
}

guard waitFor("source editor clears", timeout: 5, {
  floatingSourceText().isEmpty
}) else {
  print("UI_SMOKE_FAIL: source editor did not clear")
  exit(1)
}

if lexirayAXElements().contains(where: { axVisibleText($0).contains("No Translation") }) {
  print("UI_SMOKE_FAIL: blank source shows a no-translation warning")
  exit(1)
}
captureWindowIfRequested(floatingPanelWindowInfo(), name: "floating-empty")

guard focusFloatingSourceEditor() else {
  print("UI_SMOKE_FAIL: source editor did not accept focus before history navigation")
  exit(1)
}

press(126)
guard waitFor("up arrow restores latest history", timeout: 5, {
  let sourceText = floatingSourceText()
  return sourceText.contains(seededHistoryText) || sourceText.contains(selectedHistoryText)
}) else {
  print("UI_SMOKE_FAIL: up arrow did not restore translation history")
  exit(1)
}

if !floatingSourceText().contains(seededHistoryText) {
  press(126)
  guard waitFor("second up arrow restores seeded history", timeout: 5, {
    floatingSourceText().contains(seededHistoryText)
  }) else {
    print("UI_SMOKE_FAIL: up arrow did not continue to older translation history")
    exit(1)
  }
}
captureWindowIfRequested(floatingPanelWindowInfo(), name: "floating-history")

var returnedToBlankComposer = false
for _ in 0..<3 {
  press(125)
  let deadline = Date().addingTimeInterval(2)
  while Date() < deadline {
    if floatingSourceText().isEmpty {
      returnedToBlankComposer = true
      break
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
  }
  if returnedToBlankComposer {
    break
  }
}

guard returnedToBlankComposer else {
  print("UI_SMOKE_FAIL: down arrow did not leave history browsing")
  exit(1)
}

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

guard pressLexiRayButton(identifier: "xmark") else {
  print("UI_SMOKE_FAIL: close button was not reachable")
  exit(1)
}

guard waitFor("close button hides pinned panel", { panelWindows().isEmpty }) else {
  print("UI_SMOKE_FAIL: close button did not hide panel")
  exit(1)
}

print("UI_SMOKE_PASS")
SWIFT
