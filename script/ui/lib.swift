// Shared GUI scenario harness. Concatenated before each scenario file by
// script/ui/run.sh and executed as one Swift script:
//   cat lib.swift scenarios/<name>.swift | swift - <app> <workdir> <shotdir> <name>
import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation

let appBundle = CommandLine.arguments[1]
let workDir = CommandLine.arguments[2]
let shotDir = CommandLine.arguments[3]
let scenarioName = CommandLine.arguments[4]

let lexirayBundleID = "io.github.tensornull.lexiray"
let seededHistoryText = "LexiRay seeded history text."
let richWrapHistoryText = "LexiRay rich wrap history text."
let selectionSmokeText = "LexiRay smoke selection text."
let appExecutablePrefix = appBundle + "/Contents/MacOS/"
let lexirayHomeURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".lexiray", isDirectory: true)
let providersFileURL = lexirayHomeURL.appendingPathComponent("providers.json")

// MARK: - Target app resolution
// Two LexiRay copies can run at once (workspace build + installed release).
// Every lookup must pin the workspace copy by executable path, never by name
// or bundle identifier alone.

func lexirayInstances() -> [NSRunningApplication] {
  NSRunningApplication.runningApplications(withBundleIdentifier: lexirayBundleID)
}

func workspaceInstance() -> NSRunningApplication? {
  lexirayInstances().first { $0.executableURL?.path.hasPrefix(appExecutablePrefix) == true }
}

func foreignInstances() -> [NSRunningApplication] {
  lexirayInstances().filter { $0.executableURL?.path.hasPrefix(appExecutablePrefix) != true }
}

// MARK: - Outcome

func fail(_ message: String) -> Never {
  if !shotDir.isEmpty {
    let outputURL = URL(fileURLWithPath: shotDir).appendingPathComponent("FAIL-\(scenarioName).png")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", outputURL.path]
    try? process.run()
    process.waitUntilExit()
  }
  print("UI_FAIL[\(scenarioName)]: \(message)")
  exit(1)
}

func blocked(_ message: String) -> Never {
  print("UI_BLOCKED[\(scenarioName)]: \(message)")
  exit(2)
}

func pass() -> Never {
  print("UI_PASS[\(scenarioName)]")
  exit(0)
}

func require(_ condition: Bool, _ message: String) {
  if !condition {
    fail(message)
  }
}

// MARK: - Window inspection

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

func windowOwnerPID(_ window: [String: Any]) -> pid_t? {
  (window[kCGWindowOwnerPID as String] as? Int).map(pid_t.init)
}

func lexirayWindowInfos() -> [[String: Any]] {
  guard let pid = workspaceInstance()?.processIdentifier else {
    return []
  }
  return allWindows().filter { windowOwnerPID($0) == pid }
}

func lexirayMainWindowInfo() -> [String: Any]? {
  lexirayWindowInfos().first { window in
    let rect = windowBounds(window)
    return rect.width >= 650 && rect.height >= 420
  }
}

func floatingPanelWindowInfo() -> [String: Any]? {
  lexirayWindowInfos().first { window in
    let rect = windowBounds(window)
    return rect.width >= 560 && rect.width <= 980 && rect.height >= 180 && rect.height <= 780
  }
}

func panelWindows() -> [CGRect] {
  lexirayWindowInfos().map(windowBounds).filter { rect in
    rect.width >= 560 && rect.width <= 980 && rect.height >= 180 && rect.height <= 780
  }
}

func lexirayMainWindows() -> [CGRect] {
  lexirayWindowInfos().map(windowBounds).filter { rect in
    rect.width >= 650 && rect.height >= 420
  }
}

// MARK: - Screenshots

func snap(_ name: String, window: [String: Any]?) {
  guard !shotDir.isEmpty else {
    return
  }
  guard let window, let id = windowID(window) else {
    fail("screenshot \(name): target window was not found")
  }

  let outputURL = URL(fileURLWithPath: shotDir).appendingPathComponent("\(name).png")
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
  process.arguments = ["-x", "-l", "\(id)", outputURL.path]
  do {
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
      fail("screenshot \(name): screencapture exited \(process.terminationStatus)")
    }
  } catch {
    fail("screenshot \(name): \(error.localizedDescription)")
  }
}

func snapMain(_ name: String) {
  snap(name, window: lexirayMainWindowInfo())
}

func snapPanel(_ name: String) {
  snap(name, window: floatingPanelWindowInfo())
}

// MARK: - Accessibility tree

func lexirayAXElements() -> [AXUIElement] {
  guard let app = workspaceInstance() else {
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
          size.width >= 560 && size.width <= 980 && size.height >= 180 && size.height <= 780
    else {
      return nil
    }
    return size
  }
}

func lexirayVisibleTextContains(_ needle: String) -> Bool {
  lexirayAXElements().contains { axVisibleText($0).contains(needle) }
}

func visibleStaticTextOverflowingFloatingPanelRightBoundary() -> [String] {
  guard let panelInfo = floatingPanelWindowInfo() else {
    return ["floating panel window was not found"]
  }

  let panelFrame = windowBounds(panelInfo)
  let rightLimit = panelFrame.maxX - 8
  return lexirayAXElements().compactMap { element in
    guard axString(element, kAXRoleAttribute) == "AXStaticText",
          let frame = axFrame(element),
          frame.intersects(panelFrame),
          frame.width > 1,
          frame.maxX > rightLimit
    else {
      return nil
    }

    let text = axVisibleText(element).replacingOccurrences(of: "\n", with: " ")
    return "\(String(text.prefix(80))) maxX=\(frame.maxX) limit=\(rightLimit)"
  }
}

func floatingPanelSize() -> CGSize? {
  floatingPanelWindowInfo().map(windowBounds)?.size
}

func floatingPanelAXWindow() -> AXUIElement? {
  guard let panelInfo = floatingPanelWindowInfo() else {
    return nil
  }

  let panelFrame = windowBounds(panelInfo)
  return lexirayAXElements().first { element in
    guard axString(element, kAXRoleAttribute) == "AXWindow",
          let frame = axFrame(element)
    else {
      return false
    }

    return abs(frame.midX - panelFrame.midX) < 8
      && abs(frame.midY - panelFrame.midY) < 8
      && abs(frame.width - panelFrame.width) < 8
      && abs(frame.height - panelFrame.height) < 8
  }
}

func setFloatingPanelSize(_ size: CGSize) -> Bool {
  guard let window = floatingPanelAXWindow() else {
    return false
  }

  var requestedSize = size
  guard let value = AXValueCreate(.cgSize, &requestedSize) else {
    return false
  }

  let result = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
  RunLoop.current.run(until: Date().addingTimeInterval(0.25))
  return result == .success
}

// MARK: - Source editor

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

// MARK: - Controls

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

// MARK: - Input events

func click(_ point: CGPoint) {
  let source = CGEventSource(stateID: .hidSystemState)
  let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
  let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
  let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
  // Force a plain left click: lingering synthetic modifier state can otherwise
  // turn this into Control-click and open a context menu.
  move?.flags = []
  down?.flags = []
  up?.flags = []
  move?.post(tap: .cghidEventTap)
  RunLoop.current.run(until: Date().addingTimeInterval(0.05))
  down?.post(tap: .cghidEventTap)
  up?.post(tap: .cghidEventTap)
}

func scroll(at point: CGPoint, deltaY: Int32) {
  let source = CGEventSource(stateID: .hidSystemState)
  let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
  move?.flags = []
  move?.post(tap: .cghidEventTap)
  RunLoop.current.run(until: Date().addingTimeInterval(0.05))

  let wheel = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 1, wheel1: deltaY, wheel2: 0, wheel3: 0)
  wheel?.location = point
  wheel?.post(tap: .cghidEventTap)
}

/// Scrolls the main window until the identified element is fully visible.
/// Snapshot evidence must show the asserted UI, not just satisfy AX queries
/// against offscreen elements.
func scrollMainWindowToReveal(identifier: String, maxAttempts: Int = 30) -> Bool {
  for _ in 0 ..< maxAttempts {
    guard let windowInfo = lexirayMainWindowInfo() else {
      return false
    }
    let window = windowBounds(windowInfo)
    if let frame = axElement(identifier: identifier).flatMap(axFrame),
       frame.minY >= window.minY, frame.maxY <= window.maxY {
      return true
    }
    scroll(at: CGPoint(x: window.midX, y: window.midY), deltaY: -160)
    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
  }
  return false
}

func modifierKeyCodes(_ flags: CGEventFlags) -> [CGKeyCode] {
  var codes: [CGKeyCode] = []
  if flags.contains(.maskControl) {
    codes.append(CGKeyCode(kVK_Control))
  }
  if flags.contains(.maskAlternate) {
    codes.append(CGKeyCode(kVK_Option))
  }
  if flags.contains(.maskShift) {
    codes.append(CGKeyCode(kVK_Shift))
  }
  if flags.contains(.maskCommand) {
    codes.append(CGKeyCode(kVK_Command))
  }
  return codes
}

func press(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
  let source = CGEventSource(stateID: .hidSystemState)
  let modifiers = modifierKeyCodes(flags)

  for code in modifiers {
    CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
  }

  let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
  let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
  down?.flags = flags
  up?.flags = flags
  down?.post(tap: .cghidEventTap)
  up?.post(tap: .cghidEventTap)

  // Explicitly release modifiers so no synthetic modifier state leaks into
  // later clicks or key presses.
  for code in modifiers.reversed() {
    CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
  }
}

// MARK: - Hotkey

struct SmokeHotKey: Decodable {
  let keyCode: UInt32
  let modifiers: UInt32
}

func loadTranslateHotKey() -> (keyCode: CGKeyCode, flags: CGEventFlags) {
  let fallback = SmokeHotKey(
    keyCode: UInt32(kVK_ANSI_A),
    modifiers: UInt32(controlKey) | UInt32(optionKey)
  )
  let domain = UserDefaults.standard.persistentDomain(forName: lexirayBundleID)
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

// MARK: - Waiting and activation

func waitFor(_ description: String, timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    if condition() {
      return true
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
  }
  print("UI_TIMEOUT[\(scenarioName)]: \(description)")
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

func activateWorkspaceApp() {
  guard let app = workspaceInstance() else {
    return
  }

  if #available(macOS 14.0, *) {
    app.activate(options: [.activateAllWindows])
  } else {
    app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
  }
  RunLoop.current.run(until: Date().addingTimeInterval(0.2))
}

func closeLexiRayMainWindow() -> Bool {
  guard let app = workspaceInstance() else {
    return false
  }

  activateWorkspaceApp()

  let root = AXUIElementCreateApplication(app.processIdentifier)
  var windowsValue: CFTypeRef?
  if AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &windowsValue) == .success,
     let axWindows = windowsValue as? [AXUIElement] {
    for axWindow in axWindows {
      guard let frame = axFrame(axWindow), frame.width >= 650, frame.height >= 420 else {
        continue
      }
      var buttonValue: CFTypeRef?
      if AXUIElementCopyAttributeValue(axWindow, kAXCloseButtonAttribute as CFString, &buttonValue) == .success,
         let buttonValue {
        let button = buttonValue as! AXUIElement
        if AXUIElementPerformAction(button, kAXPressAction as CFString) == .success {
          return true
        }
      }
    }
  }

  guard let window = lexirayMainWindows().first else {
    return false
  }

  click(CGPoint(x: window.minX + 26, y: window.minY + 26))
  return true
}

// MARK: - Scenario preconditions

func ensureAppRunning() {
  if workspaceInstance() != nil {
    return
  }

  NSWorkspace.shared.open(URL(fileURLWithPath: appBundle))
  if !waitFor("LexiRay launches", timeout: 10, { workspaceInstance() != nil }) {
    fail("LexiRay did not launch from \(appBundle)")
  }
  RunLoop.current.run(until: Date().addingTimeInterval(1))
}

func terminateWorkspaceApp() {
  guard let app = workspaceInstance() else {
    return
  }

  _ = app.terminate()
  let deadline = Date().addingTimeInterval(5)
  while Date() < deadline {
    if workspaceInstance() == nil {
      return
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
  }

  if let pid = workspaceInstance()?.processIdentifier {
    kill(pid, SIGKILL)
  }
  _ = waitFor("workspace app terminates", timeout: 3, { workspaceInstance() == nil })
}

func restartWorkspaceApp() {
  terminateWorkspaceApp()
  ensureAppRunning()
}

func openMainWindow() {
  ensureAppRunning()
  if lexirayMainWindows().isEmpty {
    NSWorkspace.shared.open(URL(fileURLWithPath: appBundle))
  }
  if !waitFor("LexiRay main window", timeout: 10, { !lexirayMainWindows().isEmpty }) {
    fail("main window did not appear")
  }
  activateWorkspaceApp()
  RunLoop.current.run(until: Date().addingTimeInterval(0.3))
}

func openBlankComposer() {
  ensureAppRunning()
  activateWorkspaceApp()
  let hotKey = loadTranslateHotKey()
  press(hotKey.keyCode, flags: hotKey.flags)
  if !waitFor("floating composer", timeout: 10, { !panelWindows().isEmpty && floatingSourceEditor() != nil }) {
    fail("translate hotkey did not open a floating composer")
  }

  // A previous panel session can leave text behind; scenarios assume a blank
  // composer as their starting state.
  if !floatingSourceText().isEmpty, let editor = floatingSourceEditor() {
    _ = AXUIElementSetAttributeValue(editor, kAXValueAttribute as CFString, "" as CFString)
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
  }
}

func closePanel() {
  require(pressLexiRayButton(identifier: "xmark"), "panel close button was not reachable")
  require(waitFor("panel closes", { panelWindows().isEmpty }), "panel did not close")
}

func guardAgainstShieldedSession() {
  let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
  if frontmost == "com.apple.loginwindow" {
    blocked("GUI session is shielded by loginwindow; unlock/foreground the desktop session and rerun")
  }
}

func guardAgainstForeignCopies() {
  let foreign = foreignInstances()
  if !foreign.isEmpty {
    let paths = foreign.map { $0.executableURL?.path ?? "pid \($0.processIdentifier)" }
    blocked(
      "another LexiRay copy is running (\(paths.joined(separator: ", "))); "
        + "it steals hotkeys and AX targeting and trips the in-app identity guard. "
        + "Quit it or rerun with --quit-other-copies"
    )
  }
}

func resetToBaseline() {
  ensureAppRunning()

  // Dismiss any lingering context menu before touching windows; an open menu
  // swallows synthetic keyboard and hotkey events.
  press(53)
  RunLoop.current.run(until: Date().addingTimeInterval(0.2))

  for _ in 0 ..< 3 {
    if panelWindows().isEmpty {
      break
    }
    _ = pressLexiRayButton(identifier: "xmark")
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
  }

  for _ in 0 ..< 2 {
    if lexirayMainWindows().isEmpty {
      break
    }
    _ = closeLexiRayMainWindow()
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
  }

  if !panelWindows().isEmpty || !lexirayMainWindows().isEmpty {
    fail("could not reset to baseline; LexiRay windows are stuck open")
  }
}

guardAgainstShieldedSession()
guardAgainstForeignCopies()
resetToBaseline()
