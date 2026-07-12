// Shared GUI scenario harness. Concatenated before each scenario file by
// script/ui/run.sh and executed as one Swift script:
//   cat lib.swift scenarios/<name>.swift | swift - <app> <workdir> <shotdir> <name>
import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Darwin
import Foundation

let appBundle = CommandLine.arguments[1]
let workDir = CommandLine.arguments[2]
let shotDir = CommandLine.arguments[3]
let scenarioName = CommandLine.arguments[4]
let repoRoot = CommandLine.arguments.count > 5 ? CommandLine.arguments[5] : URL(fileURLWithPath: appBundle)
  .deletingLastPathComponent()
  .deletingLastPathComponent()
  .deletingLastPathComponent()
  .deletingLastPathComponent()
  .deletingLastPathComponent()
  .deletingLastPathComponent()
  .path
let acceptanceRoot = CommandLine.arguments[6]
let acceptanceDefaultsSuite = CommandLine.arguments[7]

let lexirayBundleID = "io.github.tensornull.lexiray"
let seededHistoryText = "LexiRay seeded history text."
let richWrapHistoryText = "LexiRay rich wrap history text."
let selectionSmokeText = "LexiRay smoke selection text."
let appExecutablePath = URL(fileURLWithPath: appBundle)
  .appendingPathComponent("Contents/MacOS/LexiRay")
  .standardizedFileURL
  .resolvingSymlinksInPath()
  .path
let lexirayHomeURL = URL(fileURLWithPath: acceptanceRoot, isDirectory: true)
let providersFileURL = lexirayHomeURL.appendingPathComponent("providers.json")
let historyFileURL = lexirayHomeURL.appendingPathComponent("history.json")
let fixtureDirectoryURL = URL(fileURLWithPath: repoRoot).appendingPathComponent("script/ui/fixtures", isDirectory: true)
let fixtureProvidersFileURL = fixtureDirectoryURL.appendingPathComponent("providers.json")
let fixtureHistoryFileURL = fixtureDirectoryURL.appendingPathComponent("history.json")
var workspaceLaunchExtraArguments: [String] = []
var workspaceProcessIdentifier: pid_t?
var ownedWorkspaceArguments: [String]?
var validatedFloatingPanelWindowID: UInt32?
var scenarioCleanupActions: [() -> Void] = []

// MARK: - Target app resolution

// Every lookup pins the workspace copy by executable path. Scenarios block
// before launch if another LexiRay process exists because global hotkeys cannot
// be safely directed to one bundle-identical process.

func lexirayInstances() -> [NSRunningApplication] {
  NSRunningApplication.runningApplications(withBundleIdentifier: lexirayBundleID)
}

func canonicalExecutablePath(_ application: NSRunningApplication) -> String? {
  application.executableURL?
    .standardizedFileURL
    .resolvingSymlinksInPath()
    .path
}

func processArguments(processIdentifier: pid_t) -> [String]? {
  var mib = [CTL_KERN, KERN_PROCARGS2, processIdentifier]
  var byteCount = 0
  guard sysctl(&mib, u_int(mib.count), nil, &byteCount, nil, 0) == 0,
        byteCount > MemoryLayout<Int32>.size
  else {
    return nil
  }

  var bytes = [UInt8](repeating: 0, count: byteCount)
  let readResult = bytes.withUnsafeMutableBytes { buffer in
    sysctl(&mib, u_int(mib.count), buffer.baseAddress, &byteCount, nil, 0)
  }
  guard readResult == 0 else {
    return nil
  }

  var argumentCount: Int32 = 0
  withUnsafeMutableBytes(of: &argumentCount) { destination in
    bytes.withUnsafeBytes { source in
      destination.copyBytes(from: source.prefix(MemoryLayout<Int32>.size))
    }
  }
  guard argumentCount > 0 else {
    return nil
  }

  var index = MemoryLayout<Int32>.size
  while index < byteCount, bytes[index] != 0 {
    index += 1
  }
  while index < byteCount, bytes[index] == 0 {
    index += 1
  }

  var arguments: [String] = []
  while index < byteCount, arguments.count < Int(argumentCount) {
    let start = index
    while index < byteCount, bytes[index] != 0 {
      index += 1
    }
    guard index > start else {
      return nil
    }
    arguments.append(String(decoding: bytes[start ..< index], as: UTF8.self))
    while index < byteCount, bytes[index] == 0 {
      index += 1
    }
  }
  return arguments.count == Int(argumentCount) ? arguments : nil
}

func expectedWorkspaceArguments(extraArguments: [String]) -> [String] {
  [
    "--lexiray-ui-scenario",
    "--lexiray-acceptance-profile",
    "--lexiray-acceptance-workspace-root", repoRoot,
    "--lexiray-acceptance-root", acceptanceRoot,
    "--lexiray-acceptance-defaults-suite", acceptanceDefaultsSuite
  ] + extraArguments
}

func applicationMatchesWorkspaceProcess(
  _ application: NSRunningApplication,
  expectedArguments: [String]
) -> Bool {
  guard !application.isTerminated,
        canonicalExecutablePath(application) == appExecutablePath,
        let arguments = processArguments(processIdentifier: application.processIdentifier),
        let argumentZero = arguments.first,
        URL(fileURLWithPath: argumentZero).standardizedFileURL.resolvingSymlinksInPath().path
        == appExecutablePath
  else {
    return false
  }
  return Array(arguments.dropFirst()) == expectedArguments
}

func workspacePathInstances() -> [NSRunningApplication] {
  lexirayInstances().filter { canonicalExecutablePath($0) == appExecutablePath }
}

func workspaceInstance() -> NSRunningApplication? {
  guard let workspaceProcessIdentifier,
        let ownedWorkspaceArguments,
        let application = NSRunningApplication(processIdentifier: workspaceProcessIdentifier),
        applicationMatchesWorkspaceProcess(application, expectedArguments: ownedWorkspaceArguments)
  else {
    return nil
  }
  return application
}

func foreignInstances() -> [NSRunningApplication] {
  lexirayInstances().filter { $0.processIdentifier != workspaceProcessIdentifier }
}

// MARK: - Outcome

func fail(_ message: String) -> Never {
  recordFailureEvidence(message)
  if let cleanupError = runScenarioCleanup() {
    print("UI_CLEANUP_BLOCKED[\(scenarioName)]: \(cleanupError)")
  }
  print("UI_FAIL[\(scenarioName)]: \(message)")
  exit(1)
}

func blocked(_ message: String) -> Never {
  if let cleanupError = runScenarioCleanup() {
    print("UI_CLEANUP_BLOCKED[\(scenarioName)]: \(cleanupError)")
  }
  print("UI_BLOCKED[\(scenarioName)]: \(message)")
  exit(2)
}

func pass() -> Never {
  if let cleanupError = runScenarioCleanup() {
    print("UI_BLOCKED[\(scenarioName)]: \(cleanupError)")
    exit(2)
  }
  print("UI_PASS[\(scenarioName)]")
  exit(0)
}

func registerScenarioCleanup(_ action: @escaping () -> Void) {
  scenarioCleanupActions.append(action)
}

func runScenarioCleanup() -> String? {
  let actions = Array(scenarioCleanupActions.reversed())
  scenarioCleanupActions.removeAll()
  actions.forEach { $0() }
  return terminateWorkspaceApp()
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

func windows(processIdentifier: pid_t, name: String? = nil) -> [CGRect] {
  allWindows().compactMap { window in
    guard windowOwnerPID(window) == processIdentifier else {
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

func windowFramesApproximatelyMatch(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 4) -> Bool {
  abs(lhs.minX - rhs.minX) < tolerance
    && abs(lhs.minY - rhs.minY) < tolerance
    && abs(lhs.width - rhs.width) < tolerance
    && abs(lhs.height - rhs.height) < tolerance
}

func windowInfo(matching accessibilityWindow: AXUIElement?) -> [String: Any]? {
  guard let accessibilityWindow, let frame = axFrame(accessibilityWindow) else {
    return nil
  }
  let matches = lexirayWindowInfos().filter {
    windowID($0) != nil && windowFramesApproximatelyMatch(windowBounds($0), frame)
  }
  return matches.count == 1 ? matches[0] : nil
}

func lexirayMainWindowInfo() -> [String: Any]? {
  windowInfo(matching: lexirayMainAXWindow())
}

func floatingPanelWindowInfo() -> [String: Any]? {
  if let matched = windowInfo(matching: floatingPanelAXWindow()) {
    validatedFloatingPanelWindowID = windowID(matched)
    return matched
  }

  // NSMenu teardown can briefly remove the panel from the AX window tree even
  // though the same app-owned CGWindow remains on screen. Reuse only the window
  // ID that AX already proved during this exact runner-owned process lifetime.
  guard let validatedFloatingPanelWindowID else {
    return nil
  }
  let matches = lexirayWindowInfos().filter { windowID($0) == validatedFloatingPanelWindowID }
  return matches.count == 1 ? matches[0] : nil
}

func isFloatingPanelWindow(_ window: [String: Any]) -> Bool {
  guard let candidateID = windowID(window), let panelID = floatingPanelWindowInfo().flatMap(windowID) else {
    return false
  }
  return candidateID == panelID
}

func panelWindows() -> [CGRect] {
  floatingPanelWindowInfo().map { [windowBounds($0)] } ?? []
}

func lexirayMainWindows() -> [CGRect] {
  lexirayMainWindowInfo().map { [windowBounds($0)] } ?? []
}

// MARK: - Screenshots

final class AcceptanceSafeBackdropPanel: NSPanel {
  override var canBecomeKey: Bool {
    false
  }

  override var canBecomeMain: Bool {
    false
  }
}

final class AcceptanceSafeBackdropView: NSView {
  override var isOpaque: Bool {
    true
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor(calibratedWhite: 0.92, alpha: 1).setFill()
    dirtyRect.fill()

    let tileSize: CGFloat = 28
    let columns = Int(ceil(bounds.width / tileSize))
    let rows = Int(ceil(bounds.height / tileSize))
    for row in 0 ... rows {
      for column in 0 ... columns where (row + column).isMultiple(of: 2) {
        let color = row.isMultiple(of: 2)
          ? NSColor(calibratedRed: 0.12, green: 0.48, blue: 0.42, alpha: 1)
          : NSColor(calibratedRed: 0.86, green: 0.34, blue: 0.28, alpha: 1)
        color.setFill()
        NSRect(
          x: CGFloat(column) * tileSize,
          y: CGFloat(row) * tileSize,
          width: tileSize,
          height: tileSize
        ).fill()
      }
    }
  }
}

func windowLayer(_ window: [String: Any]) -> Int? {
  window[kCGWindowLayer as String] as? Int
}

func windowAlpha(_ window: [String: Any]) -> CGFloat? {
  (window[kCGWindowAlpha as String] as? NSNumber).map { CGFloat(truncating: $0) }
}

final class ControlledPanelBackdrop {
  private static let title = "LexiRay Acceptance Safe Backdrop"
  private static let padding: CGFloat = 64

  private let panel: AcceptanceSafeBackdropPanel
  private let targetLayer: Int
  private let expectedBounds: CGRect

  init?(targetWindow: [String: Any]) {
    guard let targetWindowID = windowID(targetWindow),
          let targetLayer = windowLayer(targetWindow),
          let primaryScreen = NSScreen.screens.first
    else {
      return nil
    }

    self.targetLayer = targetLayer
    expectedBounds = windowBounds(targetWindow).insetBy(
      dx: -Self.padding,
      dy: -Self.padding
    )
    let appKitFrame = CGRect(
      x: expectedBounds.minX,
      y: primaryScreen.frame.maxY - expectedBounds.maxY,
      width: expectedBounds.width,
      height: expectedBounds.height
    )

    _ = NSApplication.shared
    panel = AcceptanceSafeBackdropPanel(
      contentRect: appKitFrame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.title = Self.title
    panel.level = NSWindow.Level(rawValue: targetLayer)
    panel.isOpaque = true
    panel.backgroundColor = NSColor(calibratedWhite: 0.92, alpha: 1)
    panel.alphaValue = 1
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.isReleasedWhenClosed = false
    panel.animationBehavior = .none
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    let contentView = AcceptanceSafeBackdropView(frame: CGRect(origin: .zero, size: appKitFrame.size))
    contentView.autoresizingMask = [.width, .height]
    panel.contentView = contentView
    panel.order(.below, relativeTo: Int(targetWindowID))
    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
  }

  func verificationError(targetWindowID: UInt32, processIdentifier: pid_t) -> String? {
    guard panel.isVisible,
          panel.isOpaque,
          panel.alphaValue == 1,
          panel.styleMask.contains(.nonactivatingPanel),
          !panel.canBecomeKey,
          !panel.canBecomeMain,
          panel.ignoresMouseEvents,
          let contentView = panel.contentView as? AcceptanceSafeBackdropView,
          contentView.subviews.isEmpty
    else {
      return "controlled panel backdrop is not visibly opaque"
    }

    let orderedWindows = allWindows()
    guard let targetIndex = orderedWindows.firstIndex(where: {
      windowID($0) == targetWindowID && windowOwnerPID($0) == processIdentifier
    }),
      let backdropIndex = orderedWindows.firstIndex(where: {
        windowID($0) == UInt32(panel.windowNumber) && windowOwnerPID($0) == getpid()
      })
    else {
      return "controlled panel backdrop or target is absent from the window server"
    }

    let target = orderedWindows[targetIndex]
    let backdrop = orderedWindows[backdropIndex]
    guard windowLayer(target) == targetLayer,
          windowLayer(backdrop) == targetLayer,
          backdropIndex == targetIndex + 1
    else {
      return "controlled panel backdrop is not immediately below the target panel"
    }
    guard let alpha = windowAlpha(backdrop), alpha >= 0.999 else {
      return "controlled panel backdrop is not fully opaque in the window server"
    }

    let targetBounds = windowBounds(target)
    let backdropBounds = windowBounds(backdrop)
    let tolerance: CGFloat = 1
    guard backdropBounds.minX <= targetBounds.minX + tolerance,
          backdropBounds.minY <= targetBounds.minY + tolerance,
          backdropBounds.maxX >= targetBounds.maxX - tolerance,
          backdropBounds.maxY >= targetBounds.maxY - tolerance,
          abs(backdropBounds.minX - expectedBounds.minX) <= tolerance,
          abs(backdropBounds.minY - expectedBounds.minY) <= tolerance,
          abs(backdropBounds.width - expectedBounds.width) <= tolerance,
          abs(backdropBounds.height - expectedBounds.height) <= tolerance
    else {
      return "controlled panel backdrop does not cover the target panel frame"
    }
    return nil
  }

  func close() {
    panel.orderOut(nil)
    panel.close()
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
  }
}

func currentOwnedWindowInfo(targetWindowID: UInt32, processIdentifier: pid_t) -> [String: Any]? {
  allWindows().first {
    windowID($0) == targetWindowID && windowOwnerPID($0) == processIdentifier
  }
}

func captureOwnedWindow(_ name: String, window: [String: Any]) -> String? {
  guard let processIdentifier = workspaceProcessIdentifier,
        workspaceInstance()?.processIdentifier == processIdentifier,
        windowOwnerPID(window) == processIdentifier,
        let id = windowID(window),
        currentOwnedWindowInfo(targetWindowID: id, processIdentifier: processIdentifier) != nil
  else {
    return "target window is not owned by the validated LexiRay PID"
  }

  var controlledBackdrop: ControlledPanelBackdrop?
  if isFloatingPanelWindow(window) {
    guard let backdrop = ControlledPanelBackdrop(targetWindow: window) else {
      return "could not create a synthetic controlled backdrop for the material panel"
    }
    controlledBackdrop = backdrop
    guard backdrop.verificationError(
      targetWindowID: id,
      processIdentifier: processIdentifier
    ) == nil
    else {
      backdrop.close()
      return "synthetic controlled backdrop could not be verified below the material panel"
    }
  }
  defer { controlledBackdrop?.close() }

  let outputURL = URL(fileURLWithPath: shotDir).appendingPathComponent("\(name).png")
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
  process.arguments = ["-x", "-l", "\(id)", outputURL.path]
  do {
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      return "screencapture exited \(process.terminationStatus)"
    }
    guard currentOwnedWindowInfo(targetWindowID: id, processIdentifier: processIdentifier) != nil else {
      try? FileManager.default.removeItem(at: outputURL)
      return "target window ownership changed while capturing"
    }
    if let backdropError = controlledBackdrop?.verificationError(
      targetWindowID: id,
      processIdentifier: processIdentifier
    ) {
      try? FileManager.default.removeItem(at: outputURL)
      return "controlled panel backdrop changed while capturing: \(backdropError)"
    }
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
          let size = attributes[.size] as? NSNumber,
          size.intValue > 0
    else {
      try? FileManager.default.removeItem(at: outputURL)
      return "screencapture produced no window evidence"
    }
    return nil
  } catch {
    try? FileManager.default.removeItem(at: outputURL)
    return error.localizedDescription
  }
}

func recordFailureEvidence(_ message: String) {
  guard !shotDir.isEmpty else {
    return
  }

  var lines = [
    "scenario=\(scenarioName)",
    "result=failed",
    "message=\(message)"
  ]
  guard let processIdentifier = workspaceProcessIdentifier,
        workspaceInstance()?.processIdentifier == processIdentifier
  else {
    lines.append("validated_lexiray_process=unavailable")
    let outputURL = URL(fileURLWithPath: shotDir).appendingPathComponent("FAIL-\(scenarioName).txt")
    try? lines.joined(separator: "\n").write(to: outputURL, atomically: true, encoding: .utf8)
    return
  }

  lines.append("validated_lexiray_pid=\(processIdentifier)")
  lines.append("executable=\(appExecutablePath)")
  let windowInfos = lexirayWindowInfos()
  lines.append("window_count=\(windowInfos.count)")
  for (index, window) in windowInfos.enumerated() {
    let id = windowID(window).map(String.init) ?? "unavailable"
    lines.append(
      "window[\(index)]=id:\(id),name:\(windowName(window)),bounds:\(NSStringFromRect(windowBounds(window)))"
    )
    if let error = captureOwnedWindow("FAIL-\(scenarioName)-window-\(index + 1)", window: window) {
      lines.append("window[\(index)].capture_error=\(error)")
    }
  }

  let outputURL = URL(fileURLWithPath: shotDir).appendingPathComponent("FAIL-\(scenarioName).txt")
  try? lines.joined(separator: "\n").write(to: outputURL, atomically: true, encoding: .utf8)
}

func snap(_ name: String, window: [String: Any]?) {
  guard !shotDir.isEmpty else {
    return
  }
  guard let window else {
    fail("screenshot \(name): target window was not found")
  }
  if let error = captureOwnedWindow(name, window: window) {
    fail("screenshot \(name): \(error)")
  }
}

func snapMain(_ name: String) {
  var window: [String: Any]?
  _ = waitFor("main window for screenshot \(name)", timeout: 3) {
    window = lexirayMainWindowInfo()
    return window != nil
  }
  snap(name, window: window)
}

func snapPanel(_ name: String) {
  var window: [String: Any]?
  _ = waitFor("floating panel for screenshot \(name)", timeout: 3) {
    window = floatingPanelWindowInfo()
    return window != nil
  }
  snap(name, window: window)
}

func recordPanelPixelEvidence(_ imageName: String) {
  let imageURL = URL(fileURLWithPath: shotDir).appendingPathComponent("\(imageName).png")
  guard let image = NSImage(contentsOf: imageURL),
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff)
  else {
    fail("could not read pixel evidence from \(imageName).png")
  }

  let points = [
    ("top-left", 1, max(0, bitmap.pixelsHigh - 2)),
    ("top-right", max(0, bitmap.pixelsWide - 2), max(0, bitmap.pixelsHigh - 2)),
    ("bottom-left", 1, 1),
    ("bottom-right", max(0, bitmap.pixelsWide - 2), 1),
    ("interior", min(20, bitmap.pixelsWide - 1), min(20, bitmap.pixelsHigh - 1))
  ]
  let sampledColors = points.map { name, x, y in
    (name, bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
  }
  let samples = sampledColors.map { name, color -> String in
    guard let color else {
      return "\(name)=unavailable"
    }
    return "\(name)=r:\(color.redComponent),g:\(color.greenComponent),b:\(color.blueComponent),a:\(color.alphaComponent)"
  }

  let evidenceURL = URL(fileURLWithPath: shotDir).appendingPathComponent("\(imageName)-pixels.txt")
  do {
    try samples.joined(separator: "\n").write(to: evidenceURL, atomically: true, encoding: .utf8)
  } catch {
    fail("could not write panel pixel evidence: \(error.localizedDescription)")
  }

  let cornerColors = sampledColors.prefix(4).compactMap(\.1)
  guard cornerColors.count == 4, cornerColors.allSatisfy({ $0.alphaComponent < 0.25 }) else {
    fail("\(imageName) has opaque corner pixels; rounded clipping regressed")
  }
  guard let interior = sampledColors.last?.1, interior.alphaComponent > 0.9 else {
    fail("\(imageName) did not capture an opaque panel interior for corner comparison")
  }
}

// MARK: - Accessibility tree

func axElements(root: AXUIElement, depth: Int = 0) -> [AXUIElement] {
  var elements = [root]
  guard depth < 14 else {
    return elements
  }

  var value: CFTypeRef?
  if AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &value) == .success,
     let children = value as? [AXUIElement]
  {
    for child in children {
      elements += axElements(root: child, depth: depth + 1)
    }
  }
  return elements
}

func lexirayAXElements() -> [AXUIElement] {
  guard let app = workspaceInstance() else {
    return []
  }
  return axElements(root: AXUIElementCreateApplication(app.processIdentifier))
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

func axElement(title: String) -> AXUIElement? {
  lexirayAXElements().first { element in
    let role = axString(element, kAXRoleAttribute)
    return ["AXButton", "AXMenuItem", "AXRadioButton"].contains(role)
      && axString(element, kAXTitleAttribute) == title
  }
}

func axMenuItems(title: String) -> [AXUIElement] {
  lexirayAXElements().filter { element in
    ["AXMenuItem", "AXRadioButton"].contains(axString(element, kAXRoleAttribute))
      && axString(element, kAXTitleAttribute) == title
  }
}

func axMenuItem(title: String) -> AXUIElement? {
  let matches = axMenuItems(title: title)
  return matches.first { axString($0, kAXRoleAttribute) == "AXMenuItem" } ?? matches.first
}

func axMenuItemIsMarked(title: String) -> Bool {
  axMenuItems(title: title).contains { element in
    !axString(element, kAXMenuItemMarkCharAttribute).isEmpty
  }
}

func acceptanceDefaultString(_ key: String) -> String? {
  _ = CFPreferencesAppSynchronize(acceptanceDefaultsSuite as CFString)
  return CFPreferencesCopyAppValue(
    key as CFString,
    acceptanceDefaultsSuite as CFString
  ) as? String
}

func lexiRayLanguageMenuIsOpen() -> Bool {
  axMenuItem(title: "Once") != nil && axMenuItem(title: "Always") != nil
}

func dismissLexiRayLanguageMenu(timeout: TimeInterval) -> Bool {
  guard lexiRayLanguageMenuIsOpen() else {
    return true
  }
  press(CGKeyCode(kVK_Escape))
  return waitFor("dismiss language menu", timeout: timeout) { !lexiRayLanguageMenuIsOpen() }
}

func openLexiRayLanguageMenu(
  containing title: String,
  pickerIdentifier: String,
  timeout: TimeInterval
) -> Bool {
  guard floatingPanelWindowInfo() != nil else {
    print("UI_MENU_DIAGNOSTIC[\(scenarioName)]: panel dismissed before opening \(pickerIdentifier)")
    return false
  }
  let deadline = Date().addingTimeInterval(timeout)
  var lastOpenAttempt = Date.distantPast
  repeat {
    guard floatingPanelWindowInfo() != nil else {
      print("UI_MENU_DIAGNOSTIC[\(scenarioName)]: panel dismissed while opening \(pickerIdentifier)")
      return false
    }
    if lexiRayLanguageMenuIsOpen(), axMenuItem(title: title) != nil {
      return true
    }
    if !lexiRayLanguageMenuIsOpen(), Date().timeIntervalSince(lastOpenAttempt) >= 0.5 {
      _ = pressLexiRayElement(identifier: pickerIdentifier)
      lastOpenAttempt = Date()
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
  } while Date() < deadline
  print("UI_TIMEOUT[\(scenarioName)]: open \(pickerIdentifier) menu containing \(title)")
  return false
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
  guard let window = floatingPanelAXWindow(), let frame = axFrame(window) else {
    return []
  }
  return [frame.size]
}

func lexirayVisibleTextContains(_ needle: String) -> Bool {
  lexirayAXElements().contains { axVisibleText($0).contains(needle) }
}

func floatingPanelVisibleTextContains(_ needle: String) -> Bool {
  guard let panel = floatingPanelAXWindow() else {
    return false
  }
  return axElements(root: panel).contains { axVisibleText($0).contains(needle) }
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
  lexirayAXElements().first { element in
    axString(element, kAXRoleAttribute) == "AXWindow"
      && axString(element, kAXIdentifierAttribute) == "FloatingPanelWindow"
  }
}

func lexirayMainAXWindow() -> AXUIElement? {
  let matches = lexirayAXElements().filter { element in
    guard axString(element, kAXRoleAttribute) == "AXWindow",
          axString(element, kAXIdentifierAttribute) != "FloatingPanelWindow",
          let frame = axFrame(element)
    else {
      return false
    }
    return frame.width >= 650 && frame.height >= 420
  }
  return matches.count == 1 ? matches[0] : nil
}

func setFloatingPanelSize(_ size: CGSize) -> Bool {
  guard let window = floatingPanelAXWindow() else {
    return false
  }

  // AX window sizes and CGWindow bounds can use different effective scales on
  // a scaled secondary display. Iteratively translate the desired on-screen
  // size into the AX coordinate space instead of assuming a 1:1 mapping.
  for _ in 0 ..< 5 {
    guard let screenSize = floatingPanelSize(),
          let accessibilityFrame = axFrame(window),
          screenSize.width > 0,
          screenSize.height > 0
    else {
      return false
    }
    if abs(screenSize.width - size.width) < 4,
       abs(screenSize.height - size.height) < 4
    {
      return true
    }

    var requestedSize = CGSize(
      width: size.width * accessibilityFrame.width / screenSize.width,
      height: size.height * accessibilityFrame.height / screenSize.height
    )
    guard let value = AXValueCreate(.cgSize, &requestedSize) else {
      return false
    }
    guard AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) == .success else {
      return false
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.25))
  }

  guard let finalSize = floatingPanelSize() else {
    return false
  }
  return abs(finalSize.width - size.width) < 4
    && abs(finalSize.height - size.height) < 4
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
     let frame = axFrame(editor)
  {
    click(CGPoint(x: frame.midX, y: frame.midY))
  }

  RunLoop.current.run(until: Date().addingTimeInterval(0.2))

  press(0, flags: .maskCommand)
  RunLoop.current.run(until: Date().addingTimeInterval(0.05))
  typeUnicode(text)
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

func setAcceptanceMarkedText(_ text: String) {
  DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("io.github.tensornull.lexiray.acceptance.ime.mark"),
    object: text,
    userInfo: nil,
    deliverImmediately: true
  )
  RunLoop.current.run(until: Date().addingTimeInterval(0.3))
}

func commitAcceptanceMarkedText(_ text: String) {
  DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("io.github.tensornull.lexiray.acceptance.ime.commit"),
    object: text,
    userInfo: nil,
    deliverImmediately: true
  )
  RunLoop.current.run(until: Date().addingTimeInterval(0.3))
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

func clickLexiRayElement(identifier: String) -> Bool {
  guard let element = axElement(identifier: identifier), let frame = axFrame(element) else {
    return false
  }
  click(CGPoint(x: frame.midX, y: frame.midY))
  return true
}

func pressLexiRayElement(title: String) -> Bool {
  guard let element = axElement(title: title) else {
    return false
  }
  if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
    return true
  }
  guard let frame = axFrame(element) else {
    return false
  }
  click(CGPoint(x: frame.midX, y: frame.midY))
  return true
}

func selectLexiRayMenuItem(
  title: String,
  pickerIdentifier: String,
  timeout: TimeInterval = 5
) -> Bool {
  guard dismissLexiRayLanguageMenu(timeout: timeout) else {
    print("UI_MENU_DIAGNOSTIC[\(scenarioName)]: stale-menu-dismiss failed for \(pickerIdentifier)")
    return false
  }
  guard openLexiRayLanguageMenu(
    containing: title,
    pickerIdentifier: pickerIdentifier,
    timeout: timeout
  ) else {
    print("UI_MENU_DIAGNOSTIC[\(scenarioName)]: menu open failed for \(pickerIdentifier)")
    return false
  }
  guard let element = axMenuItem(title: title) else {
    print("UI_MENU_DIAGNOSTIC[\(scenarioName)]: \(title) disappeared from \(pickerIdentifier)")
    return false
  }

  for action in [kAXPressAction, kAXPickAction] {
    let result = AXUIElementPerformAction(element, action as CFString)
    if result == .success {
      return true
    }
  }
  guard let frame = axFrame(element) else {
    print("UI_MENU_DIAGNOSTIC[\(scenarioName)]: no actionable frame for \(title) in \(pickerIdentifier)")
    return false
  }
  click(CGPoint(x: frame.midX, y: frame.midY))
  return true
}

func selectAndVerifyLexiRayMenuMode(
  title: String,
  pickerIdentifier: String,
  timeout: TimeInterval = 5
) -> Bool {
  guard selectLexiRayMenuItem(
    title: title,
    pickerIdentifier: pickerIdentifier,
    timeout: timeout
  ) else {
    print("UI_MENU_DIAGNOSTIC[\(scenarioName)]: initial \(title) selection failed")
    return false
  }

  RunLoop.current.run(until: Date().addingTimeInterval(0.3))
  guard dismissLexiRayLanguageMenu(timeout: timeout) else {
    print("UI_MENU_DIAGNOSTIC[\(scenarioName)]: post-selection dismiss failed for \(title)")
    return false
  }
  guard openLexiRayLanguageMenu(
    containing: title,
    pickerIdentifier: pickerIdentifier,
    timeout: timeout
  ) else {
    print("UI_MENU_DIAGNOSTIC[\(scenarioName)]: verification menu open failed for \(pickerIdentifier)")
    return false
  }
  guard waitFor("verify \(title) mode", timeout: timeout, { axMenuItemIsMarked(title: title) }) else {
    let onceMark = axMenuItems(title: "Once").map { axString($0, kAXMenuItemMarkCharAttribute) }
    let alwaysMark = axMenuItems(title: "Always").map { axString($0, kAXMenuItemMarkCharAttribute) }
    print(
      "UI_MENU_DIAGNOSTIC[\(scenarioName)]: mode mark mismatch "
        + "once=\(onceMark) always=\(alwaysMark)"
    )
    return false
  }
  return dismissLexiRayLanguageMenu(timeout: timeout)
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
  let targetIsVisible = {
    guard let windowInfo = lexirayMainWindowInfo() else {
      return false
    }
    let window = windowBounds(windowInfo)
    guard let frame = axElement(identifier: identifier).flatMap(axFrame) else {
      return false
    }
    return frame.minY >= window.minY && frame.maxY <= window.maxY
  }

  if targetIsVisible() {
    return true
  }

  if mainWindowScrollBar() != nil {
    for value in stride(from: 0.0, through: 1.0, by: 0.08) {
      _ = setMainWindowScrollValue(value)
      RunLoop.current.run(until: Date().addingTimeInterval(0.12))
      if targetIsVisible() {
        return true
      }
    }
  }

  for _ in 0 ..< maxAttempts {
    guard let windowInfo = lexirayMainWindowInfo() else {
      return false
    }
    let window = windowBounds(windowInfo)
    if targetIsVisible() {
      return true
    }

    let frame = axElement(identifier: identifier).flatMap(axFrame)
    var deltaY: Int32 = 200
    if let frame, frame.maxY < window.minY {
      deltaY = -200
    }
    scroll(at: CGPoint(x: window.midX, y: window.midY), deltaY: deltaY)
    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
  }
  return false
}

func mainWindowScrollBar() -> AXUIElement? {
  guard let windowInfo = lexirayMainWindowInfo() else {
    return nil
  }
  let window = windowBounds(windowInfo)
  return lexirayAXElements().first { element in
    guard axString(element, kAXRoleAttribute) == "AXScrollBar",
          axString(element, kAXOrientationAttribute) == "AXVerticalOrientation",
          let frame = axFrame(element)
    else {
      return false
    }

    return frame.intersects(window) && frame.minX >= window.maxX - 40
  }
}

func setMainWindowScrollValue(_ value: Double) -> Bool {
  guard let scrollBar = mainWindowScrollBar() else {
    return false
  }

  let clampedValue = NSNumber(value: min(max(value, 0), 1))
  return AXUIElementSetAttributeValue(scrollBar, kAXValueAttribute as CFString, clampedValue) == .success
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

func typeUnicode(_ text: String) {
  let units = Array(text.utf16)
  let chunkSize = 32
  for start in stride(from: 0, to: units.count, by: chunkSize) {
    let end = min(start + chunkSize, units.count)
    let chunk = Array(units[start ..< end])
    chunk.withUnsafeBufferPointer { buffer in
      let source = CGEventSource(stateID: .hidSystemState)
      let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
      let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
      down?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
      up?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
      down?.post(tap: .cghidEventTap)
      up?.post(tap: .cghidEventTap)
    }
  }
}

// MARK: - Hotkey

struct SmokeHotKey: Decodable {
  let keyCode: UInt32
  let modifiers: UInt32
}

func loadHotKey(
  key: String,
  fallbackKeyCode: Int,
  fallbackModifiers: UInt32 = UInt32(controlKey) | UInt32(optionKey)
) -> (keyCode: CGKeyCode, flags: CGEventFlags) {
  let fallback = SmokeHotKey(keyCode: UInt32(fallbackKeyCode), modifiers: fallbackModifiers)
  let data = UserDefaults(suiteName: acceptanceDefaultsSuite)?.data(forKey: key)
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

func loadTranslateHotKey() -> (keyCode: CGKeyCode, flags: CGEventFlags) {
  loadHotKey(
    key: "translateHotKey",
    fallbackKeyCode: kVK_ANSI_A,
    fallbackModifiers: UInt32(controlKey) | UInt32(optionKey) | UInt32(shiftKey)
  )
}

func loadOCRHotKey() -> (keyCode: CGKeyCode, flags: CGEventFlags) {
  loadHotKey(
    key: "ocrHotKey",
    fallbackKeyCode: kVK_ANSI_S,
    fallbackModifiers: UInt32(controlKey) | UInt32(optionKey) | UInt32(shiftKey)
  )
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
     let axWindows = windowsValue as? [AXUIElement]
  {
    for axWindow in axWindows {
      guard let frame = axFrame(axWindow), frame.width >= 650, frame.height >= 420 else {
        continue
      }
      var buttonValue: CFTypeRef?
      if AXUIElementCopyAttributeValue(axWindow, kAXCloseButtonAttribute as CFString, &buttonValue) == .success,
         let buttonValue
      {
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

func closeApplicationWindow(bundleIdentifier: String, titleContains: String) -> Bool {
  for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier) {
    let root = AXUIElementCreateApplication(app.processIdentifier)
    var windowsValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &windowsValue) == .success,
          let axWindows = windowsValue as? [AXUIElement]
    else {
      continue
    }

    for axWindow in axWindows where axString(axWindow, kAXTitleAttribute).contains(titleContains) {
      var buttonValue: CFTypeRef?
      guard AXUIElementCopyAttributeValue(
        axWindow,
        kAXCloseButtonAttribute as CFString,
        &buttonValue
      ) == .success, let buttonValue
      else {
        continue
      }
      if AXUIElementPerformAction(buttonValue as! AXUIElement, kAXPressAction as CFString) == .success {
        return true
      }
    }
  }
  return false
}

func closeApplicationWindow(processIdentifier: pid_t, titleContains: String) -> Bool {
  guard let app = NSRunningApplication(processIdentifier: processIdentifier) else {
    return false
  }
  let root = AXUIElementCreateApplication(app.processIdentifier)
  var windowsValue: CFTypeRef?
  guard AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &windowsValue) == .success,
        let axWindows = windowsValue as? [AXUIElement]
  else {
    return false
  }

  for axWindow in axWindows where axString(axWindow, kAXTitleAttribute).contains(titleContains) {
    var buttonValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
      axWindow,
      kAXCloseButtonAttribute as CFString,
      &buttonValue
    ) == .success, let buttonValue
    else {
      continue
    }
    if AXUIElementPerformAction(buttonValue as! AXUIElement, kAXPressAction as CFString) == .success {
      return true
    }
  }
  return false
}

func applicationWindowFrame(processIdentifier: pid_t, titleContains: String) -> CGRect? {
  let windowServerMatches = allWindows().filter {
    windowOwnerPID($0) == processIdentifier
      && windowName($0).contains(titleContains)
      && !windowBounds($0).isEmpty
  }
  if windowServerMatches.count == 1 {
    return windowBounds(windowServerMatches[0])
  }

  guard let app = NSRunningApplication(processIdentifier: processIdentifier) else {
    return nil
  }
  let root = AXUIElementCreateApplication(app.processIdentifier)
  var windowsValue: CFTypeRef?
  guard AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &windowsValue) == .success,
        let axWindows = windowsValue as? [AXUIElement]
  else {
    return nil
  }

  let matches = axWindows.filter {
    axString($0, kAXTitleAttribute).contains(titleContains) && axFrame($0) != nil
  }
  guard matches.count == 1 else {
    return nil
  }
  return axFrame(matches[0])
}

// MARK: - Scenario preconditions

func ensureAppRunning() {
  if workspaceInstance() != nil {
    return
  }
  if !workspacePathInstances().isEmpty {
    blocked("an untracked workspace LexiRay instance is already running")
  }
  validatedFloatingPanelWindowID = nil

  let configuration = NSWorkspace.OpenConfiguration()
  configuration.activates = false
  configuration.createsNewApplicationInstance = true
  let launchArguments = expectedWorkspaceArguments(extraArguments: workspaceLaunchExtraArguments)
  configuration.arguments = launchArguments

  var launchCompleted = false
  var launchError: Error?
  var launchedProcessIdentifier: pid_t?
  NSWorkspace.shared.openApplication(
    at: URL(fileURLWithPath: appBundle),
    configuration: configuration
  ) { application, error in
    launchedProcessIdentifier = application?.processIdentifier
    launchError = error
    launchCompleted = true
  }

  let launchDeadline = Date().addingTimeInterval(10)
  while !launchCompleted, Date() < launchDeadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
  }
  if let launchError {
    fail("LexiRay launch failed: \(launchError.localizedDescription)")
  }
  guard let launchedProcessIdentifier else {
    fail("LexiRay launch did not return a process identifier")
  }
  guard let launchedApplication = NSRunningApplication(processIdentifier: launchedProcessIdentifier),
        applicationMatchesWorkspaceProcess(
          launchedApplication,
          expectedArguments: launchArguments
        )
  else {
    blocked(
      "launched LexiRay PID \(launchedProcessIdentifier) did not match the exact workspace executable "
        + "and acceptance arguments; it was not recorded or terminated"
    )
  }
  workspaceProcessIdentifier = launchedProcessIdentifier
  ownedWorkspaceArguments = launchArguments
  if !waitFor("LexiRay launches", timeout: 10, { workspaceInstance() != nil }) {
    fail("LexiRay did not launch from \(appBundle)")
  }
  guardAgainstForeignCopies()
  RunLoop.current.run(until: Date().addingTimeInterval(1))
}

@discardableResult
func terminateWorkspaceApp() -> String? {
  guard let processIdentifier = workspaceProcessIdentifier,
        let expectedArguments = ownedWorkspaceArguments
  else {
    if workspaceProcessIdentifier != nil || ownedWorkspaceArguments != nil {
      return "incomplete workspace process ownership record; no process was terminated"
    }
    validatedFloatingPanelWindowID = nil
    return nil
  }

  guard let app = NSRunningApplication(processIdentifier: processIdentifier),
        !app.isTerminated
  else {
    workspaceProcessIdentifier = nil
    ownedWorkspaceArguments = nil
    validatedFloatingPanelWindowID = nil
    return nil
  }
  guard applicationMatchesWorkspaceProcess(app, expectedArguments: expectedArguments) else {
    return "recorded PID \(processIdentifier) no longer matches the exact workspace executable "
      + "and acceptance arguments; no signal was sent"
  }

  _ = app.terminate()
  let deadline = Date().addingTimeInterval(5)
  while Date() < deadline {
    if app.isTerminated {
      workspaceProcessIdentifier = nil
      ownedWorkspaceArguments = nil
      validatedFloatingPanelWindowID = nil
      return nil
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
  }

  guard applicationMatchesWorkspaceProcess(app, expectedArguments: expectedArguments) else {
    return "recorded PID \(processIdentifier) changed identity before forced termination; no signal was sent"
  }
  kill(processIdentifier, SIGKILL)
  let terminated = waitFor("workspace app terminates", timeout: 3) { app.isTerminated }
  guard terminated else {
    return "runner-owned LexiRay PID \(processIdentifier) did not terminate"
  }
  workspaceProcessIdentifier = nil
  ownedWorkspaceArguments = nil
  validatedFloatingPanelWindowID = nil
  return nil
}

func restartWorkspaceApp() {
  if let cleanupError = terminateWorkspaceApp() {
    blocked(cleanupError)
  }
  ensureAppRunning()
}

func restartWorkspaceApp(extraArguments: [String]) {
  if let cleanupError = terminateWorkspaceApp() {
    blocked(cleanupError)
  }
  workspaceLaunchExtraArguments = extraArguments
  ensureAppRunning()
}

func openMainWindow() {
  ensureAppRunning()
  if lexirayMainWindows().isEmpty {
    require(
      pressLexiRayElement(title: "Open LexiRay"),
      "menu-bar Open LexiRay action was not reachable"
    )
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
  require(waitFor("panel closes") { panelWindows().isEmpty }, "panel did not close")
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
      "another LexiRay process could intercept acceptance hotkeys: "
        + paths.joined(separator: ", ")
    )
  }
}

func closeVisibleLexiRayWindows() {
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
}

func resetToBaseline() {
  ensureAppRunning()
  closeVisibleLexiRayWindows()

  if !panelWindows().isEmpty || !lexirayMainWindows().isEmpty {
    if let cleanupError = terminateWorkspaceApp() {
      blocked(cleanupError)
    }
    ensureAppRunning()
    closeVisibleLexiRayWindows()
  }

  if !panelWindows().isEmpty || !lexirayMainWindows().isEmpty {
    fail(
      "could not reset to baseline; LexiRay windows are stuck open "
        + "(panels=\(panelWindows().count), main=\(lexirayMainWindows().count))"
    )
  }
}

func restoreFixtureStateAndRestart() {
  do {
    try FileManager.default.createDirectory(at: lexirayHomeURL, withIntermediateDirectories: true)
    try Data(contentsOf: fixtureProvidersFileURL).write(to: providersFileURL, options: .atomic)
    try Data(contentsOf: fixtureHistoryFileURL).write(to: historyFileURL, options: .atomic)
  } catch {
    fail("could not restore UI fixture state: \(error.localizedDescription)")
  }

  restartWorkspaceApp()
  resetToBaseline()
}

guardAgainstShieldedSession()
guardAgainstForeignCopies()
resetToBaseline()
