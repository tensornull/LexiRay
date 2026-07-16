#!/usr/bin/env swift

import AppKit
import CoreGraphics
import CryptoKit
import Darwin
import Foundation
import ImageIO

private struct ProcessSnapshot {
  let executablePath: String
  let arguments: [String]
  let startTimeMicroseconds: Int64
}

private struct CaptureBounds: Codable, Equatable {
  let x: Double
  let y: Double
  let width: Double
  let height: Double
}

private struct WindowCapture: Codable, Equatable {
  let windowID: UInt32
  let windowName: String
  let windowRole: String
  let windowLayer: Int
  let bounds: CaptureBounds
  let pngPath: String
  let pngSHA256: String
  let pixelWidth: Int
  let pixelHeight: Int

  enum CodingKeys: String, CodingKey {
    case windowID = "window_id"
    case windowName = "window_name"
    case windowRole = "window_role"
    case windowLayer = "window_layer"
    case bounds
    case pngPath = "png_path"
    case pngSHA256 = "png_sha256"
    case pixelWidth = "pixel_width"
    case pixelHeight = "pixel_height"
  }
}

private struct ScenarioStateAssertions: Codable, Equatable {
  let values: [String: String]
}

private enum EvidenceWindowRole: String {
  case main
  case panel
  case ocrOverlay = "ocr-overlay"
}

private struct EligibleWindow {
  let info: [String: Any]
  let role: EvidenceWindowRole
  let accessibilityWindow: AXUIElement?
}

private struct CaptureProvenance: Codable, Equatable {
  let schemaVersion: Int
  let kind: String
  let sourceFingerprint: String
  let scenario: String
  let installTransactionID: String
  let installedAt: String
  let capturedAt: String
  let processIdentifier: Int32
  let processStartTimeMicroseconds: Int64
  let processExecutable: String
  let processArgumentsSHA256: String
  let appCDHash: String
  let appExecutableSHA256: String
  let captureRoot: String
  let availableDisplayCount: Int
  let displayCount: Int
  let stateAssertions: ScenarioStateAssertions
  let captures: [WindowCapture]

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case kind
    case sourceFingerprint = "source_fingerprint"
    case scenario
    case installTransactionID = "install_transaction_id"
    case installedAt = "installed_at"
    case capturedAt = "captured_at"
    case processIdentifier = "process_identifier"
    case processStartTimeMicroseconds = "process_start_time_us"
    case processExecutable = "process_executable"
    case processArgumentsSHA256 = "process_arguments_sha256"
    case appCDHash = "app_cdhash"
    case appExecutableSHA256 = "app_executable_sha256"
    case captureRoot = "capture_root"
    case availableDisplayCount = "available_display_count"
    case displayCount = "display_count"
    case stateAssertions = "state_assertions"
    case captures
  }
}

private struct VerifiedPNG {
  let width: Int
  let height: Int
}

private enum EvidenceError: LocalizedError {
  case message(String)

  var errorDescription: String? {
    switch self {
    case let .message(message): message
    }
  }
}

private func fail(_ message: String) -> Never {
  fputs("ACCEPTANCE_EVIDENCE_ERROR: \(message)\n", stderr)
  exit(1)
}

private func usage() -> Never {
  fputs(
    """
    usage:
      acceptance_evidence.swift process <pid> <expected-executable> [expected-start-time-us] -- <expected-arguments...>
      acceptance_evidence.swift process-identity <pid> <expected-executable> -- <expected-arguments...>
      acceptance_evidence.swift arguments-hash -- <arguments...>
      acceptance_evidence.swift png <image.png> [image.png...]
      acceptance_evidence.swift displays
      acceptance_evidence.swift capture <pid> <expected-executable> <scenario> <output-dir> <source-fingerprint> <cdhash> <executable-sha256> <install-transaction-id> <installed-at> <process-start-time-us> [window-id] -- <expected-arguments...>
      acceptance_evidence.swift verify <provenance> <pid> <expected-executable> <scenario> <output-dir> <source-fingerprint> <cdhash> <executable-sha256> <install-transaction-id> <installed-at> <process-start-time-us> <valid-through> <require-live:0|1> <print-images:0|1> -- <expected-arguments...>
    """,
    stderr
  )
  exit(2)
}

private func canonicalPath(_ path: String) -> String {
  URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
}

private func processSnapshot(processIdentifier: pid_t) throws -> ProcessSnapshot {
  guard processIdentifier > 0, Darwin.kill(processIdentifier, 0) == 0 else {
    throw EvidenceError.message("process \(processIdentifier) is not running")
  }

  var processInfo = kinfo_proc()
  var processMIB = [CTL_KERN, KERN_PROC, KERN_PROC_PID, processIdentifier]
  var processInfoSize = MemoryLayout<kinfo_proc>.stride
  let processInfoResult = withUnsafeMutablePointer(to: &processInfo) { pointer in
    sysctl(&processMIB, u_int(processMIB.count), pointer, &processInfoSize, nil, 0)
  }
  let startSeconds = Int64(processInfo.kp_proc.p_starttime.tv_sec)
  let startMicroseconds = Int64(processInfo.kp_proc.p_starttime.tv_usec)
  guard processInfoResult == 0,
        processInfoSize == MemoryLayout<kinfo_proc>.stride,
        processInfo.kp_proc.p_pid == processIdentifier,
        startSeconds > 0,
        (0 ..< 1_000_000).contains(startMicroseconds),
        startSeconds <= (Int64.max - startMicroseconds) / 1_000_000
  else {
    throw EvidenceError.message("could not read kernel start time for process \(processIdentifier)")
  }
  let startTimeMicroseconds = startSeconds * 1_000_000 + startMicroseconds

  var mib = [CTL_KERN, KERN_PROCARGS2, processIdentifier]
  var byteCount = 0
  guard sysctl(&mib, u_int(mib.count), nil, &byteCount, nil, 0) == 0,
        byteCount > MemoryLayout<Int32>.size
  else {
    throw EvidenceError.message("could not size argv for process \(processIdentifier)")
  }

  var bytes = [UInt8](repeating: 0, count: byteCount)
  let readResult = bytes.withUnsafeMutableBytes { buffer in
    sysctl(&mib, u_int(mib.count), buffer.baseAddress, &byteCount, nil, 0)
  }
  guard readResult == 0 else {
    throw EvidenceError.message("could not read argv for process \(processIdentifier)")
  }

  var argumentCount: Int32 = 0
  withUnsafeMutableBytes(of: &argumentCount) { destination in
    bytes.withUnsafeBytes { source in
      destination.copyBytes(from: source.prefix(MemoryLayout<Int32>.size))
    }
  }
  guard argumentCount > 0 else {
    throw EvidenceError.message("process \(processIdentifier) has no argv")
  }

  var index = MemoryLayout<Int32>.size
  let executableStart = index
  while index < byteCount, bytes[index] != 0 {
    index += 1
  }
  guard index > executableStart else {
    throw EvidenceError.message("process \(processIdentifier) has no kernel executable path")
  }
  let executablePath = String(decoding: bytes[executableStart ..< index], as: UTF8.self)
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
      throw EvidenceError.message("process \(processIdentifier) has malformed argv")
    }
    arguments.append(String(decoding: bytes[start ..< index], as: UTF8.self))
    while index < byteCount, bytes[index] == 0 {
      index += 1
    }
  }
  guard arguments.count == Int(argumentCount) else {
    throw EvidenceError.message("process \(processIdentifier) argv was truncated")
  }

  return ProcessSnapshot(
    executablePath: canonicalPath(executablePath),
    arguments: arguments,
    startTimeMicroseconds: startTimeMicroseconds
  )
}

@discardableResult
private func validateProcess(
  processIdentifier: pid_t,
  expectedExecutable: String,
  expectedStartTimeMicroseconds: Int64? = nil,
  expectedArguments: [String]
) throws -> ProcessSnapshot {
  guard !expectedArguments.isEmpty else {
    throw EvidenceError.message("expected acceptance argv must not be empty")
  }
  let snapshot = try processSnapshot(processIdentifier: processIdentifier)
  guard snapshot.executablePath == canonicalPath(expectedExecutable) else {
    throw EvidenceError.message("process executable does not match \(expectedExecutable)")
  }
  if let expectedStartTimeMicroseconds,
     snapshot.startTimeMicroseconds != expectedStartTimeMicroseconds
  {
    throw EvidenceError.message("process start time does not match the installed acceptance process")
  }
  guard let argumentZero = snapshot.arguments.first,
        canonicalPath(argumentZero) == canonicalPath(expectedExecutable),
        Array(snapshot.arguments.dropFirst()) == expectedArguments
  else {
    throw EvidenceError.message("process argv0 and arguments do not exactly match the acceptance launch")
  }
  return snapshot
}

private func sha256(data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func sha256(file: URL) throws -> String {
  try sha256(data: Data(contentsOf: file, options: [.mappedIfSafe]))
}

private func argumentsHash(_ arguments: [String]) -> String {
  let framed = arguments.map { "\($0.utf8.count):\($0)" }.joined(separator: "\n")
  return sha256(data: Data(framed.utf8))
}

private func isSafeScenario(_ value: String) -> Bool {
  value.range(of: #"^[a-z0-9][a-z0-9._-]{0,79}$"#, options: .regularExpression) != nil
}

private func isLowercaseHex(_ value: String, count: Int) -> Bool {
  value.count == count && value.range(of: #"^[0-9a-f]+$"#, options: .regularExpression) != nil
}

private func isValidInstallTransactionID(_ value: String) -> Bool {
  value.range(
    of: #"^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"#,
    options: .regularExpression
  ) != nil
}

private func iso8601Date(_ value: String) -> Date? {
  guard value.range(
    of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"#,
    options: .regularExpression
  ) != nil else {
    return nil
  }
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime]
  guard let date = formatter.date(from: value), formatter.string(from: date) == value else {
    return nil
  }
  return date
}

private func axString(_ element: AXUIElement, _ attribute: String) -> String {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
    return ""
  }
  return value as? String ?? ""
}

private func axBool(_ element: AXUIElement, _ attribute: String) -> Bool? {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
        let number = value as? NSNumber
  else {
    return nil
  }
  return number.boolValue
}

private func axVisibleText(_ element: AXUIElement) -> String {
  [
    axString(element, kAXTitleAttribute),
    axString(element, kAXDescriptionAttribute),
    axString(element, kAXValueAttribute)
  ]
  .filter { !$0.isEmpty }
  .joined(separator: " ")
}

private func ocrCaptureDisplayIndices(from value: String) -> [Int]? {
  let prefix = "OCR capture displays: "
  guard value.hasPrefix(prefix) else {
    return nil
  }
  let components = value.dropFirst(prefix.count).split(separator: ",", omittingEmptySubsequences: false)
  let indices = components.compactMap { component -> Int? in
    guard let index = Int(component), index > 0, String(index) == String(component) else {
      return nil
    }
    return index
  }
  guard indices.count == components.count,
        indices == Array(Set(indices)).sorted()
  else {
    return nil
  }
  return indices
}

private func accessibilityElements(root: AXUIElement) -> [AXUIElement] {
  var elements: [AXUIElement] = []
  func collect(_ element: AXUIElement, depth: Int) {
    elements.append(element)
    guard depth < 16 else {
      return
    }
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
          let children = value as? [AXUIElement]
    else {
      return
    }
    children.forEach { collect($0, depth: depth + 1) }
  }
  collect(root, depth: 0)
  return elements
}

private func accessibilityWindows(processIdentifier: pid_t) throws -> [AXUIElement] {
  guard AXIsProcessTrusted() else {
    throw EvidenceError.message("Accessibility permission is required for scenario state evidence")
  }
  let root = AXUIElementCreateApplication(processIdentifier)
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &value) == .success,
        let windows = value as? [AXUIElement]
  else {
    throw EvidenceError.message("could not read acceptance application windows through Accessibility")
  }
  return windows
}

private func axFrame(_ element: AXUIElement) -> CGRect? {
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

private func validateScenarioStateAssertions(
  scenario: String,
  assertions: ScenarioStateAssertions
) throws {
  let values = assertions.values
  switch scenario {
  case "launch":
    guard values == ["main_window": "present"] else {
      throw EvidenceError.message("launch state assertions do not prove the main window")
    }

  case "source_editor":
    guard values == [
      "editor_focused": "true",
      "editor_nonempty": "true"
    ] else {
      throw EvidenceError.message("source_editor requires a focused, non-empty source editor")
    }

  case "selection_hotkey":
    guard values == [
      "mock_translation": "present",
      "source_contains": "LexiRay",
      "source_kind": "Accessibility"
    ] else {
      throw EvidenceError.message("selection_hotkey does not prove the installed selection workflow")
    }

  case "language_direction":
    guard values["source_picker"]?.contains("Japanese") == true,
          values["target_picker"]?.contains("English") == true,
          values["mock_direction"] == "Direction: ja -> en",
          values.count == 3
    else {
      throw EvidenceError.message(
        "language_direction requires concrete Japanese/English pickers and the matching mock result"
      )
    }

  case "speech_controls":
    guard values["stop_control_count"] == "1",
          let identifier = values["stop_control_identifier"],
          ["FloatingPanelSourceSpeech", "TranslationSpeech-mock"].contains(identifier),
          values.count == 2
    else {
      throw EvidenceError.message("speech_controls requires exactly one identified Stop control")
    }

  case "panel_visual_states":
    guard values == [
      "app_active": "false",
      "floating_layer": String(NSWindow.Level.floating.rawValue),
      "pinned_control": "Unpin",
      "resized": "true"
    ] else {
      throw EvidenceError.message(
        "panel_visual_states requires a pinned, non-key, resized floating-level panel"
      )
    }

  case "ocr_result_display_1", "ocr_result_display_2":
    let expectedDisplayIndex = scenario == "ocr_result_display_1" ? 1 : 2
    guard values["display_index"] == String(expectedDisplayIndex),
          values["capture_display_index"] == String(expectedDisplayIndex),
          values["mock_translation"] == "present",
          values["source_contains"] == "LexiRay",
          values["source_kind"] == "OCR",
          Int(values["display_count"] ?? "") ?? 0 >= 2,
          values.count == 6
    else {
      throw EvidenceError.message(
        "\(scenario) does not prove OCR source, capture display, translation, and panel placement"
      )
    }

  case "ocr_multi_display":
    guard let overlays = Int(values["overlay_count"] ?? ""),
          let displays = Int(values["display_count"] ?? ""),
          displays >= 2,
          overlays == displays,
          values.count == 2
    else {
      throw EvidenceError.message("ocr_multi_display state assertions do not cover every display")
    }

  default:
    throw EvidenceError.message("unsupported Computer Use scenario: \(scenario)")
  }
}

private func scenarioStateAssertions(
  scenario: String,
  processIdentifier: pid_t,
  windows: [EligibleWindow]
) throws -> ScenarioStateAssertions {
  let values: [String: String]
  switch scenario {
  case "launch":
    guard windows.count == 1,
          windows[0].role == .main,
          let accessibilityWindow = windows[0].accessibilityWindow,
          axString(accessibilityWindow, kAXRoleAttribute) == "AXWindow",
          axString(accessibilityWindow, kAXIdentifierAttribute) != "FloatingPanelWindow"
    else {
      throw EvidenceError.message("launch live AX state is not bound to the main window")
    }
    values = ["main_window": "present"]

  case "source_editor":
    guard windows.count == 1,
          windows[0].role == .panel,
          let accessibilityWindow = windows[0].accessibilityWindow
    else {
      throw EvidenceError.message("source_editor is not bound to the floating panel AX window")
    }
    let elements = accessibilityElements(root: accessibilityWindow)
    guard let editor = elements.first(where: {
      axString($0, kAXIdentifierAttribute) == "FloatingPanelSourceEditor"
        && axString($0, kAXRoleAttribute) == "AXTextArea"
    }),
      !axString(editor, kAXValueAttribute).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      axBool(editor, kAXFocusedAttribute) == true
    else {
      throw EvidenceError.message("source_editor live AX state is not focused and non-empty")
    }
    values = ["editor_focused": "true", "editor_nonempty": "true"]

  case "selection_hotkey":
    guard windows.count == 1,
          windows[0].role == .panel,
          let accessibilityWindow = windows[0].accessibilityWindow
    else {
      throw EvidenceError.message("selection_hotkey is not bound to the floating panel AX window")
    }
    let elements = accessibilityElements(root: accessibilityWindow)
    guard let editor = elements.first(where: {
      axString($0, kAXIdentifierAttribute) == "FloatingPanelSourceEditor"
        && axString($0, kAXRoleAttribute) == "AXTextArea"
    }) else {
      throw EvidenceError.message("selection_hotkey could not find the floating source editor")
    }
    let sourceText = axString(editor, kAXValueAttribute)
    let sourceKinds = elements.filter {
      axString($0, kAXIdentifierAttribute) == "FloatingPanelSelectionSource"
    }
    guard !sourceKinds.isEmpty else {
      throw EvidenceError.message("selection_hotkey could not find the selection source badge")
    }
    let allText = elements.map(axVisibleText).joined(separator: "\n")
    guard sourceText.contains("LexiRay"),
          sourceKinds.contains(where: { axVisibleText($0).contains("Accessibility") }),
          allText.contains("LexiRay mock translation:")
    else {
      throw EvidenceError.message("selection_hotkey does not show selected source, source kind, and mock translation")
    }
    values = [
      "mock_translation": "present",
      "source_contains": "LexiRay",
      "source_kind": "Accessibility"
    ]

  case "language_direction":
    guard windows.count == 1,
          windows[0].role == .panel,
          let accessibilityWindow = windows[0].accessibilityWindow
    else {
      throw EvidenceError.message("language_direction is not bound to the floating panel AX window")
    }
    let elements = accessibilityElements(root: accessibilityWindow)
    func element(withIdentifier identifier: String) -> AXUIElement? {
      elements.first { axString($0, kAXIdentifierAttribute) == identifier }
    }
    guard let source = element(withIdentifier: "SourceLanguagePicker"),
          let target = element(withIdentifier: "TargetLanguagePicker")
    else {
      throw EvidenceError.message("language_direction could not find both picker AX elements")
    }
    let sourceText = axVisibleText(source)
    let targetText = axVisibleText(target)
    let allText = elements.map(axVisibleText).joined(separator: "\n")
    guard sourceText.contains("Japanese"),
          targetText.contains("English"),
          allText.contains("Direction: ja -> en")
    else {
      throw EvidenceError.message("language_direction live AX state does not show Japanese -> English")
    }
    values = [
      "source_picker": sourceText,
      "target_picker": targetText,
      "mock_direction": "Direction: ja -> en"
    ]

  case "speech_controls":
    guard windows.count == 1,
          windows[0].role == .panel,
          let accessibilityWindow = windows[0].accessibilityWindow
    else {
      throw EvidenceError.message("speech_controls is not bound to the floating panel AX window")
    }
    let elements = accessibilityElements(root: accessibilityWindow)
    let stopControls = elements.filter {
      axString($0, kAXRoleAttribute) == "AXButton" && axVisibleText($0).contains("Stop")
    }
    guard stopControls.count == 1 else {
      throw EvidenceError.message("speech_controls live AX state must expose exactly one Stop button")
    }
    let identifier = axString(stopControls[0], kAXIdentifierAttribute)
    guard ["FloatingPanelSourceSpeech", "TranslationSpeech-mock"].contains(identifier) else {
      throw EvidenceError.message("speech_controls Stop button has an unexpected AX identifier")
    }
    values = ["stop_control_count": "1", "stop_control_identifier": identifier]

  case "panel_visual_states":
    guard windows.count == 1,
          windows[0].role == .panel,
          let accessibilityWindow = windows[0].accessibilityWindow,
          windowLayer(windows[0].info) == NSWindow.Level.floating.rawValue,
          let application = NSRunningApplication(processIdentifier: processIdentifier),
          !application.isActive
    else {
      throw EvidenceError.message("panel_visual_states live window is not a non-key floating panel")
    }
    let elements = accessibilityElements(root: accessibilityWindow)
    let unpinControls = elements.filter {
      axString($0, kAXRoleAttribute) == "AXButton" && axVisibleText($0).contains("Unpin")
    }
    let bounds = windowBounds(windows[0].info)
    guard unpinControls.count == 1,
          bounds.width >= 760,
          bounds.height >= 360
    else {
      throw EvidenceError.message("panel_visual_states live panel is not pinned and resized")
    }
    values = [
      "app_active": "false",
      "floating_layer": String(NSWindow.Level.floating.rawValue),
      "pinned_control": "Unpin",
      "resized": "true"
    ]

  case "ocr_result_display_1", "ocr_result_display_2":
    guard windows.count == 1,
          windows[0].role == .panel,
          let accessibilityWindow = windows[0].accessibilityWindow
    else {
      throw EvidenceError.message("\(scenario) is not bound to the floating panel AX window")
    }
    let elements = accessibilityElements(root: accessibilityWindow)
    guard let editor = elements.first(where: {
      axString($0, kAXIdentifierAttribute) == "FloatingPanelSourceEditor"
        && axString($0, kAXRoleAttribute) == "AXTextArea"
    }) else {
      throw EvidenceError.message("\(scenario) could not find the OCR source editor")
    }
    let sourceText = axString(editor, kAXValueAttribute)
    let sourceKinds = elements.filter {
      axString($0, kAXIdentifierAttribute) == "FloatingPanelSelectionSource"
    }
    guard sourceKinds.count == 1 else {
      throw EvidenceError.message("\(scenario) could not find the OCR source badge")
    }
    let sourceKindValues = sourceKinds.flatMap { sourceKind in
      [
        axString(sourceKind, kAXTitleAttribute),
        axString(sourceKind, kAXDescriptionAttribute),
        axString(sourceKind, kAXValueAttribute)
      ]
    }
    let allText = elements.map(axVisibleText).joined(separator: "\n")
    let captureDisplayIndices = ocrCaptureDisplayIndices(
      from: axString(sourceKinds[0], kAXValueAttribute)
    )
    let expectedDisplayIndex = scenario == "ocr_result_display_1" ? 1 : 2
    guard sourceText.contains("LexiRay"),
          sourceKindValues.contains("OCR"),
          allText.contains("LexiRay mock translation:"),
          captureDisplayIndices == [expectedDisplayIndex]
    else {
      throw EvidenceError.message(
        "\(scenario) does not show OCR text and translation captured from display \(expectedDisplayIndex)"
      )
    }
    let displays = expectedDisplayWindowBounds()
    guard displays.count >= 2,
          displays.indices.contains(expectedDisplayIndex - 1),
          displays[expectedDisplayIndex - 1].contains(
            CGPoint(x: windowBounds(windows[0].info).midX, y: windowBounds(windows[0].info).midY)
          )
    else {
      throw EvidenceError.message("\(scenario) panel is not centered on the required display")
    }
    values = [
      "capture_display_index": String(expectedDisplayIndex),
      "display_count": String(displays.count),
      "display_index": String(expectedDisplayIndex),
      "mock_translation": "present",
      "source_contains": "LexiRay",
      "source_kind": "OCR"
    ]

  case "ocr_multi_display":
    guard NSScreen.screens.count >= 2,
          windows.count == NSScreen.screens.count,
          windows.allSatisfy({ $0.role == .ocrOverlay })
    else {
      throw EvidenceError.message("ocr_multi_display requires at least two current displays and one overlay per display")
    }
    values = [
      "overlay_count": String(windows.count),
      "display_count": String(NSScreen.screens.count)
    ]

  default:
    throw EvidenceError.message("unsupported Computer Use scenario: \(scenario)")
  }
  let assertions = ScenarioStateAssertions(values: values)
  try validateScenarioStateAssertions(scenario: scenario, assertions: assertions)
  return assertions
}

private func allWindows() -> [[String: Any]] {
  CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements],
    kCGNullWindowID
  ) as? [[String: Any]] ?? []
}

private func windowOwnerPID(_ window: [String: Any]) -> pid_t? {
  (window[kCGWindowOwnerPID as String] as? NSNumber).map { pid_t($0.int32Value) }
}

private func windowID(_ window: [String: Any]) -> UInt32? {
  (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value
}

private func windowName(_ window: [String: Any]) -> String {
  window[kCGWindowName as String] as? String ?? ""
}

private func windowLayer(_ window: [String: Any]) -> Int? {
  (window[kCGWindowLayer as String] as? NSNumber)?.intValue
}

private func windowAlpha(_ window: [String: Any]) -> CGFloat? {
  (window[kCGWindowAlpha as String] as? NSNumber).map { CGFloat(truncating: $0) }
}

private func windowBounds(_ window: [String: Any]) -> CGRect {
  guard let dictionary = window[kCGWindowBounds as String] as? NSDictionary else {
    return .zero
  }
  return CGRect(dictionaryRepresentation: dictionary) ?? .zero
}

private func expectedDisplayWindowBounds() -> [CGRect] {
  let screens = NSScreen.screens
  let primaryTop = screens.first?.frame.maxY ?? 0
  return screens.map { screen in
    CGRect(
      x: screen.frame.minX,
      y: primaryTop - screen.frame.maxY,
      width: screen.frame.width,
      height: screen.frame.height
    )
  }
}

private func framesMatch(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 4) -> Bool {
  abs(lhs.minX - rhs.minX) < tolerance
    && abs(lhs.minY - rhs.minY) < tolerance
    && abs(lhs.width - rhs.width) < tolerance
    && abs(lhs.height - rhs.height) < tolerance
}

private func semanticAccessibilityWindow(
  scenario: String,
  processIdentifier: pid_t
) throws -> (window: AXUIElement, role: EvidenceWindowRole) {
  let windows = try accessibilityWindows(processIdentifier: processIdentifier)
  let matches: [AXUIElement]
  let role: EvidenceWindowRole
  switch scenario {
  case "launch":
    role = .main
    matches = windows.filter { window in
      guard axString(window, kAXRoleAttribute) == "AXWindow",
            axString(window, kAXIdentifierAttribute) != "FloatingPanelWindow",
            let frame = axFrame(window)
      else {
        return false
      }
      return frame.width >= 650 && frame.height >= 420
    }

  case "selection_hotkey", "source_editor", "language_direction", "speech_controls", "panel_visual_states",
       "ocr_result_display_1", "ocr_result_display_2":
    role = .panel
    matches = windows.filter {
      axString($0, kAXRoleAttribute) == "AXWindow"
        && axString($0, kAXIdentifierAttribute) == "FloatingPanelWindow"
    }

  default:
    throw EvidenceError.message("unsupported AX window scenario: \(scenario)")
  }

  guard matches.count == 1 else {
    throw EvidenceError.message(
      "scenario \(scenario) requires exactly one semantic AX window; found \(matches.count)"
    )
  }
  return (matches[0], role)
}

private func ownedWindow(
  matching accessibilityWindow: AXUIElement,
  candidates: [[String: Any]]
) throws -> [String: Any] {
  guard let frame = axFrame(accessibilityWindow) else {
    throw EvidenceError.message("semantic AX window has no readable frame")
  }
  let matches = candidates.filter { framesMatch(windowBounds($0), frame) }
  guard matches.count == 1 else {
    throw EvidenceError.message(
      "semantic AX window did not map to exactly one PID-owned Window Server window; found \(matches.count)"
    )
  }
  return matches[0]
}

private func eligibleWindows(
  scenario: String,
  processIdentifier: pid_t,
  requestedWindowID: UInt32?
) throws -> [EligibleWindow] {
  let owned = allWindows().filter { window in
    guard windowOwnerPID(window) == processIdentifier,
          windowID(window) != nil,
          windowLayer(window) != nil
    else {
      return false
    }
    return true
  }

  switch scenario {
  case "launch", "selection_hotkey", "source_editor", "language_direction", "speech_controls", "panel_visual_states",
       "ocr_result_display_1", "ocr_result_display_2":
    let semantic = try semanticAccessibilityWindow(
      scenario: scenario,
      processIdentifier: processIdentifier
    )
    let window = try ownedWindow(matching: semantic.window, candidates: owned)
    if let requestedWindowID, windowID(window) != requestedWindowID {
      throw EvidenceError.message("requested window ID is not the scenario's AX-bound \(semantic.role.rawValue) window")
    }
    let bounds = windowBounds(window)
    let geometryIsValid = semantic.role == .main
      ? bounds.width >= 650 && bounds.height >= 420
      : bounds.width >= 240 && bounds.height >= 100
    guard geometryIsValid else {
      throw EvidenceError.message("AX-bound \(semantic.role.rawValue) window has invalid geometry")
    }
    return [EligibleWindow(info: window, role: semantic.role, accessibilityWindow: semantic.window)]

  case "ocr_multi_display":
    let displays = expectedDisplayWindowBounds()
    guard displays.count >= 2 else {
      throw EvidenceError.message("ocr_multi_display is blocked: fewer than two displays are connected")
    }
    let overlays = owned.filter { window in
      displays.contains { framesMatch(windowBounds(window), $0) }
    }
    guard overlays.count == displays.count,
          displays.allSatisfy({ expected in
            overlays.count(where: { framesMatch(windowBounds($0), expected) }) == 1
          })
    else {
      throw EvidenceError.message(
        "ocr_multi_display requires one acceptance-PID overlay matching every current display"
      )
    }
    if let requestedWindowID,
       overlays.count != 1 || windowID(overlays[0]) != requestedWindowID
    {
      throw EvidenceError.message("ocr_multi_display must capture all display overlays as one bound set")
    }
    return overlays.map {
      EligibleWindow(info: $0, role: .ocrOverlay, accessibilityWindow: nil)
    }

  default:
    throw EvidenceError.message("unsupported Computer Use scenario: \(scenario)")
  }
}

private func eligibleWindowsWhenReady(
  scenario: String,
  processIdentifier: pid_t,
  requestedWindowID: UInt32?
) throws -> [EligibleWindow] {
  guard scenario == "launch" else {
    return try eligibleWindows(
      scenario: scenario,
      processIdentifier: processIdentifier,
      requestedWindowID: requestedWindowID
    )
  }

  let deadline = Date().addingTimeInterval(10)
  var lastError: Error?
  repeat {
    do {
      return try eligibleWindows(
        scenario: scenario,
        processIdentifier: processIdentifier,
        requestedWindowID: requestedWindowID
      )
    } catch {
      lastError = error
      Thread.sleep(forTimeInterval: 0.1)
    }
  } while Date() < deadline

  throw lastError ?? EvidenceError.message("launch window did not become ready")
}

private final class SafeBackdropPanel: NSPanel {
  override var canBecomeKey: Bool {
    false
  }

  override var canBecomeMain: Bool {
    false
  }
}

private final class SafeBackdropView: NSView {
  override var isOpaque: Bool {
    true
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor(calibratedWhite: 0.86, alpha: 1).setFill()
    dirtyRect.fill()

    let tileSize: CGFloat = 28
    let columns = Int(ceil(bounds.width / tileSize))
    let rows = Int(ceil(bounds.height / tileSize))
    for row in 0 ... rows {
      for column in 0 ... columns where (row + column).isMultiple(of: 2) {
        let color = row.isMultiple(of: 2)
          ? NSColor(calibratedRed: 0.12, green: 0.48, blue: 0.42, alpha: 1)
          : NSColor(calibratedRed: 0.34, green: 0.38, blue: 0.42, alpha: 1)
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

private final class ControlledBackdrop {
  private static let padding: CGFloat = 72

  private let panel: SafeBackdropPanel
  private let expectedBounds: CGRect
  private let targetLayer: Int

  init(targetWindow: [String: Any]) throws {
    guard let targetWindowID = windowID(targetWindow),
          let targetLayer = windowLayer(targetWindow),
          let primaryScreen = NSScreen.screens.first
    else {
      throw EvidenceError.message("target window has incomplete geometry")
    }

    self.targetLayer = targetLayer
    expectedBounds = windowBounds(targetWindow).insetBy(dx: -Self.padding, dy: -Self.padding)
    let appKitFrame = CGRect(
      x: expectedBounds.minX,
      y: primaryScreen.frame.maxY - expectedBounds.maxY,
      width: expectedBounds.width,
      height: expectedBounds.height
    )

    _ = NSApplication.shared
    panel = SafeBackdropPanel(
      contentRect: appKitFrame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.level = NSWindow.Level(rawValue: targetLayer)
    panel.isOpaque = true
    panel.backgroundColor = NSColor(calibratedWhite: 0.86, alpha: 1)
    panel.alphaValue = 1
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.isReleasedWhenClosed = false
    panel.animationBehavior = .none
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    let content = SafeBackdropView(frame: CGRect(origin: .zero, size: appKitFrame.size))
    content.autoresizingMask = [.width, .height]
    panel.contentView = content
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
          let content = panel.contentView as? SafeBackdropView,
          content.subviews.isEmpty
    else {
      return "controlled backdrop is not opaque and nonactivating"
    }

    let windows = allWindows()
    guard let targetIndex = windows.firstIndex(where: {
      windowID($0) == targetWindowID && windowOwnerPID($0) == processIdentifier
    }),
      let backdropIndex = windows.firstIndex(where: {
        windowID($0) == UInt32(panel.windowNumber) && windowOwnerPID($0) == getpid()
      })
    else {
      return "controlled backdrop or target is absent from the window server"
    }

    let target = windows[targetIndex]
    let backdrop = windows[backdropIndex]
    guard windowLayer(target) == targetLayer,
          windowLayer(backdrop) == targetLayer,
          backdropIndex == targetIndex + 1,
          let alpha = windowAlpha(backdrop),
          alpha >= 0.999
    else {
      return "controlled backdrop is not immediately below the target"
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
      return "controlled backdrop does not cover the target window"
    }
    return nil
  }

  func close() {
    panel.orderOut(nil)
    panel.close()
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
  }
}

private func verifiedPNG(at url: URL, requireOpaque: Bool = false) throws -> VerifiedPNG {
  var metadata = stat()
  guard lstat(url.path, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG else {
    throw EvidenceError.message("capture is not a regular file: \(url.path)")
  }
  guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        CGImageSourceGetCount(source) == 1,
        (CGImageSourceGetType(source) as String?) == "public.png",
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
        image.width > 0,
        image.height > 0
  else {
    throw EvidenceError.message("capture is not a decodable single-image PNG: \(url.path)")
  }
  if requireOpaque {
    let opaqueAlphaModes: Set<CGImageAlphaInfo> = [.none, .noneSkipFirst, .noneSkipLast]
    guard opaqueAlphaModes.contains(image.alphaInfo) else {
      throw EvidenceError.message("Computer Use capture is not an opaque flattened PNG: \(url.path)")
    }
  }
  return VerifiedPNG(width: image.width, height: image.height)
}

private func flattenPNG(at url: URL) throws {
  guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
        let context = CGContext(
          data: nil,
          width: image.width,
          height: image.height,
          bitsPerComponent: 8,
          bytesPerRow: 0,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
  else {
    throw EvidenceError.message("could not create an opaque Computer Use capture")
  }

  let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
  context.setFillColor(gray: 0.86, alpha: 1)
  context.fill(bounds)
  context.draw(image, in: bounds)
  guard let flattened = context.makeImage(),
        let data = NSBitmapImageRep(cgImage: flattened).representation(using: .png, properties: [:])
  else {
    throw EvidenceError.message("could not encode an opaque Computer Use PNG")
  }
  try data.write(to: url, options: .atomic)
  _ = try verifiedPNG(at: url, requireOpaque: true)
}

private func currentOwnedWindow(
  windowIdentifier: UInt32,
  processIdentifier: pid_t
) -> [String: Any]? {
  allWindows().first {
    windowID($0) == windowIdentifier && windowOwnerPID($0) == processIdentifier
  }
}

private func captureWindow(
  _ eligibleWindow: EligibleWindow,
  processIdentifier: pid_t,
  outputURL: URL
) throws -> WindowCapture {
  let window = eligibleWindow.info
  guard let identifier = windowID(window),
        windowOwnerPID(window) == processIdentifier,
        let layer = windowLayer(window),
        currentOwnedWindow(windowIdentifier: identifier, processIdentifier: processIdentifier) != nil
  else {
    throw EvidenceError.message("target window is not owned by the acceptance PID")
  }

  let backdrop = try ControlledBackdrop(targetWindow: window)
  defer { backdrop.close() }
  if let error = backdrop.verificationError(
    targetWindowID: identifier,
    processIdentifier: processIdentifier
  ) {
    throw EvidenceError.message(error)
  }

  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
  process.arguments = ["-x", "-l", "\(identifier)", outputURL.path]
  try process.run()
  process.waitUntilExit()
  guard process.terminationStatus == 0 else {
    throw EvidenceError.message("screencapture exited \(process.terminationStatus)")
  }
  guard currentOwnedWindow(windowIdentifier: identifier, processIdentifier: processIdentifier) != nil else {
    try? FileManager.default.removeItem(at: outputURL)
    throw EvidenceError.message("target window ownership changed during capture")
  }
  if let error = backdrop.verificationError(
    targetWindowID: identifier,
    processIdentifier: processIdentifier
  ) {
    try? FileManager.default.removeItem(at: outputURL)
    throw EvidenceError.message("controlled backdrop changed during capture: \(error)")
  }

  try flattenPNG(at: outputURL)
  let image = try verifiedPNG(at: outputURL, requireOpaque: true)
  let bounds = windowBounds(window)
  return try WindowCapture(
    windowID: identifier,
    windowName: windowName(window),
    windowRole: eligibleWindow.role.rawValue,
    windowLayer: layer,
    bounds: CaptureBounds(
      x: bounds.minX,
      y: bounds.minY,
      width: bounds.width,
      height: bounds.height
    ),
    pngPath: outputURL.path,
    pngSHA256: sha256(file: outputURL),
    pixelWidth: image.width,
    pixelHeight: image.height
  )
}

private func capture(
  processIdentifier: pid_t,
  expectedExecutable: String,
  scenario: String,
  outputDirectory: String,
  sourceFingerprint: String,
  appCDHash: String,
  appExecutableSHA256: String,
  installTransactionID: String,
  installedAt: String,
  expectedProcessStartTimeMicroseconds: Int64,
  requestedWindowID: UInt32?,
  expectedArguments: [String]
) throws -> URL {
  guard isSafeScenario(scenario) else {
    throw EvidenceError.message("scenario must be a lowercase stable identifier")
  }
  guard isLowercaseHex(sourceFingerprint, count: 64),
        isLowercaseHex(appCDHash, count: 40),
        isLowercaseHex(appExecutableSHA256, count: 64),
        isValidInstallTransactionID(installTransactionID),
        expectedProcessStartTimeMicroseconds > 0,
        iso8601Date(installedAt) != nil
  else {
    throw EvidenceError.message("source/app/install identity is malformed")
  }
  guard CGPreflightScreenCaptureAccess() else {
    throw EvidenceError.message(
      "Screen Recording permission is required before Computer Use evidence capture"
    )
  }

  let snapshot = try validateProcess(
    processIdentifier: processIdentifier,
    expectedExecutable: expectedExecutable,
    expectedStartTimeMicroseconds: expectedProcessStartTimeMicroseconds,
    expectedArguments: expectedArguments
  )
  let outputRoot = URL(fileURLWithPath: outputDirectory, isDirectory: true).standardizedFileURL
  try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
  guard canonicalPath(outputRoot.path) == outputRoot.path else {
    throw EvidenceError.message("capture root must not contain symlinks")
  }

  let targetWindows = try eligibleWindowsWhenReady(
    scenario: scenario,
    processIdentifier: processIdentifier,
    requestedWindowID: requestedWindowID
  )
  guard !targetWindows.isEmpty else {
    throw EvidenceError.message("no scenario-matching window owned by acceptance PID \(processIdentifier)")
  }
  let stateAssertions = try scenarioStateAssertions(
    scenario: scenario,
    processIdentifier: processIdentifier,
    windows: targetWindows
  )

  let prefix = "\(scenario)-window-"
  for file in try FileManager.default.contentsOfDirectory(
    at: outputRoot,
    includingPropertiesForKeys: nil,
    options: [.skipsHiddenFiles]
  ) where file.lastPathComponent.hasPrefix(prefix) && file.pathExtension == "png" {
    try FileManager.default.removeItem(at: file)
  }
  let provenanceURL = outputRoot.appending(path: "\(scenario).json", directoryHint: .notDirectory)
  try? FileManager.default.removeItem(at: provenanceURL)

  var createdFiles: [URL] = []
  do {
    let captures = try targetWindows.compactMap { eligibleWindow -> WindowCapture? in
      guard let identifier = windowID(eligibleWindow.info) else {
        return nil
      }
      let outputURL = outputRoot.appending(
        path: "\(scenario)-window-\(identifier).png",
        directoryHint: .notDirectory
      )
      createdFiles.append(outputURL)
      return try captureWindow(
        eligibleWindow,
        processIdentifier: processIdentifier,
        outputURL: outputURL
      )
    }
    guard !captures.isEmpty else {
      throw EvidenceError.message("no acceptance window was captured")
    }
    _ = try validateProcess(
      processIdentifier: processIdentifier,
      expectedExecutable: expectedExecutable,
      expectedStartTimeMicroseconds: expectedProcessStartTimeMicroseconds,
      expectedArguments: expectedArguments
    )
    let finalWindows = try eligibleWindows(
      scenario: scenario,
      processIdentifier: processIdentifier,
      requestedWindowID: requestedWindowID
    )
    let finalStateAssertions = try scenarioStateAssertions(
      scenario: scenario,
      processIdentifier: processIdentifier,
      windows: finalWindows
    )
    guard finalStateAssertions == stateAssertions else {
      throw EvidenceError.message("scenario state changed while capture evidence was recorded")
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    let provenance = CaptureProvenance(
      schemaVersion: 4,
      kind: "computer-use-window-capture",
      sourceFingerprint: sourceFingerprint,
      scenario: scenario,
      installTransactionID: installTransactionID,
      installedAt: installedAt,
      capturedAt: formatter.string(from: Date()),
      processIdentifier: processIdentifier,
      processStartTimeMicroseconds: snapshot.startTimeMicroseconds,
      processExecutable: snapshot.executablePath,
      processArgumentsSHA256: argumentsHash(expectedArguments),
      appCDHash: appCDHash,
      appExecutableSHA256: appExecutableSHA256,
      captureRoot: outputRoot.path,
      availableDisplayCount: NSScreen.screens.count,
      displayCount: scenario == "ocr_multi_display" ? captures.count : 0,
      stateAssertions: stateAssertions,
      captures: captures
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(provenance).write(to: provenanceURL, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: provenanceURL.path)
    return provenanceURL
  } catch {
    for file in createdFiles {
      try? FileManager.default.removeItem(at: file)
    }
    try? FileManager.default.removeItem(at: provenanceURL)
    throw error
  }
}

private func verifyProvenance(
  provenanceURL: URL,
  processIdentifier: pid_t,
  expectedExecutable: String,
  scenario: String,
  outputDirectory: String,
  sourceFingerprint: String,
  appCDHash: String,
  appExecutableSHA256: String,
  installTransactionID: String,
  installedAt: String,
  expectedProcessStartTimeMicroseconds: Int64,
  validThrough: String,
  requireLive: Bool,
  expectedArguments: [String]
) throws -> CaptureProvenance {
  let outputRoot = URL(fileURLWithPath: outputDirectory, isDirectory: true).standardizedFileURL
  guard canonicalPath(outputRoot.path) == outputRoot.path,
        canonicalPath(provenanceURL.deletingLastPathComponent().path) == outputRoot.path,
        provenanceURL.lastPathComponent == "\(scenario).json"
  else {
    throw EvidenceError.message("provenance escaped the controlled capture root")
  }
  var metadata = stat()
  guard lstat(provenanceURL.path, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG else {
    throw EvidenceError.message("provenance is not a regular file")
  }

  let provenance = try JSONDecoder().decode(
    CaptureProvenance.self,
    from: Data(contentsOf: provenanceURL)
  )
  guard provenance.schemaVersion == 4,
        provenance.kind == "computer-use-window-capture",
        provenance.sourceFingerprint == sourceFingerprint,
        provenance.scenario == scenario,
        provenance.installTransactionID == installTransactionID,
        provenance.installedAt == installedAt,
        provenance.processIdentifier == processIdentifier,
        provenance.processStartTimeMicroseconds == expectedProcessStartTimeMicroseconds,
        provenance.processExecutable == canonicalPath(expectedExecutable),
        provenance.processArgumentsSHA256 == argumentsHash(expectedArguments),
        provenance.appCDHash == appCDHash,
        provenance.appExecutableSHA256 == appExecutableSHA256,
        provenance.captureRoot == outputRoot.path,
        provenance.availableDisplayCount > 0,
        !provenance.captures.isEmpty
  else {
    throw EvidenceError.message("provenance does not match the expected source, app, process, or scenario")
  }
  guard isValidInstallTransactionID(installTransactionID),
        let installationDate = iso8601Date(installedAt),
        let captureDate = iso8601Date(provenance.capturedAt),
        let validThroughDate = iso8601Date(validThrough),
        expectedProcessStartTimeMicroseconds > 0,
        captureDate >= installationDate,
        captureDate <= validThroughDate,
        validThroughDate <= Date()
  else {
    throw EvidenceError.message("provenance timestamp is outside the installed-to-validation interval")
  }
  try validateScenarioStateAssertions(
    scenario: scenario,
    assertions: provenance.stateAssertions
  )

  var seenWindowIDs = Set<UInt32>()
  var seenPaths = Set<String>()
  for capture in provenance.captures {
    let pngURL = URL(fileURLWithPath: capture.pngPath).standardizedFileURL
    guard canonicalPath(pngURL.deletingLastPathComponent().path) == outputRoot.path,
          pngURL.lastPathComponent == "\(scenario)-window-\(capture.windowID).png",
          seenWindowIDs.insert(capture.windowID).inserted,
          seenPaths.insert(pngURL.path).inserted,
          capture.bounds.width >= 80,
          capture.bounds.height >= 40
    else {
      throw EvidenceError.message("provenance contains an unsafe or duplicate window capture")
    }
    let image = try verifiedPNG(at: pngURL, requireOpaque: true)
    guard image.width == capture.pixelWidth,
          image.height == capture.pixelHeight,
          try sha256(file: pngURL) == capture.pngSHA256
    else {
      throw EvidenceError.message("PNG no longer matches its provenance: \(pngURL.path)")
    }
  }

  switch scenario {
  case "launch":
    guard provenance.displayCount == 0,
          provenance.captures.count == 1,
          provenance.captures.allSatisfy({ capture in
            capture.windowRole == EvidenceWindowRole.main.rawValue
              && capture.bounds.width >= 650
              && capture.bounds.height >= 420
          })
    else {
      throw EvidenceError.message("launch provenance does not contain a LexiRay main window")
    }

  case "selection_hotkey", "source_editor", "language_direction", "speech_controls", "panel_visual_states":
    guard provenance.displayCount == 0,
          provenance.captures.count == 1,
          provenance.captures.allSatisfy({ capture in
            capture.windowRole == EvidenceWindowRole.panel.rawValue
              && capture.bounds.width >= 240
              && capture.bounds.height >= 100
          })
    else {
      throw EvidenceError.message("\(scenario) provenance does not contain the floating panel")
    }

  case "ocr_result_display_1", "ocr_result_display_2":
    let displays = expectedDisplayWindowBounds()
    let expectedDisplayIndex = scenario == "ocr_result_display_1" ? 1 : 2
    let captureFrame = provenance.captures.first.map { capture in
      CGRect(
        x: capture.bounds.x,
        y: capture.bounds.y,
        width: capture.bounds.width,
        height: capture.bounds.height
      )
    }
    guard provenance.displayCount == 0,
          provenance.availableDisplayCount == displays.count,
          displays.count >= 2,
          displays.indices.contains(expectedDisplayIndex - 1),
          provenance.captures.count == 1,
          provenance.captures[0].windowRole == EvidenceWindowRole.panel.rawValue,
          let captureFrame,
          displays[expectedDisplayIndex - 1].contains(
            CGPoint(x: captureFrame.midX, y: captureFrame.midY)
          )
    else {
      throw EvidenceError.message("\(scenario) provenance is not a result panel on the required display")
    }

  case "ocr_multi_display":
    let displays = expectedDisplayWindowBounds()
    let captureFrames = provenance.captures.map { capture in
      CGRect(
        x: capture.bounds.x,
        y: capture.bounds.y,
        width: capture.bounds.width,
        height: capture.bounds.height
      )
    }
    guard provenance.availableDisplayCount == displays.count,
          displays.count >= 2,
          provenance.displayCount == displays.count,
          captureFrames.count == displays.count,
          provenance.captures.allSatisfy({ $0.windowRole == EvidenceWindowRole.ocrOverlay.rawValue }),
          displays.allSatisfy({ expected in
            captureFrames.count(where: { framesMatch($0, expected) }) == 1
          })
    else {
      throw EvidenceError.message("ocr_multi_display provenance does not cover every current display")
    }

  default:
    throw EvidenceError.message("unsupported Computer Use scenario: \(scenario)")
  }

  if requireLive {
    _ = try validateProcess(
      processIdentifier: processIdentifier,
      expectedExecutable: expectedExecutable,
      expectedStartTimeMicroseconds: expectedProcessStartTimeMicroseconds,
      expectedArguments: expectedArguments
    )
    let liveWindows = try eligibleWindows(
      scenario: scenario,
      processIdentifier: processIdentifier,
      requestedWindowID: nil
    )
    let liveRolesByID = Dictionary(uniqueKeysWithValues: liveWindows.compactMap { window -> (UInt32, String)? in
      guard let identifier = windowID(window.info) else {
        return nil
      }
      return (identifier, window.role.rawValue)
    })
    guard provenance.captures.count == liveRolesByID.count,
          provenance.captures.allSatisfy({ liveRolesByID[$0.windowID] == $0.windowRole })
    else {
      throw EvidenceError.message("a captured window is no longer the live AX-bound scenario window")
    }
    let liveStateAssertions = try scenarioStateAssertions(
      scenario: scenario,
      processIdentifier: processIdentifier,
      windows: liveWindows
    )
    guard liveStateAssertions == provenance.stateAssertions else {
      throw EvidenceError.message("live scenario state no longer matches its capture provenance")
    }
  }
  return provenance
}

private func splitArguments(_ values: ArraySlice<String>) -> (prefix: [String], suffix: [String]) {
  guard let delimiter = values.firstIndex(of: "--") else {
    usage()
  }
  return (Array(values[..<delimiter]), Array(values[values.index(after: delimiter)...]))
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
  usage()
}

do {
  switch arguments[1] {
  case "process":
    let split = splitArguments(arguments.dropFirst(2))
    guard split.prefix.count == 2 || split.prefix.count == 3,
          let pid = pid_t(split.prefix[0]),
          !split.suffix.isEmpty
    else {
      usage()
    }
    let expectedStartTime = split.prefix.count == 3 ? Int64(split.prefix[2]) : nil
    if split.prefix.count == 3, expectedStartTime == nil {
      usage()
    }
    _ = try validateProcess(
      processIdentifier: pid,
      expectedExecutable: split.prefix[1],
      expectedStartTimeMicroseconds: expectedStartTime,
      expectedArguments: split.suffix
    )

  case "process-identity":
    let split = splitArguments(arguments.dropFirst(2))
    guard split.prefix.count == 2,
          let pid = pid_t(split.prefix[0]),
          !split.suffix.isEmpty
    else {
      usage()
    }
    let snapshot = try validateProcess(
      processIdentifier: pid,
      expectedExecutable: split.prefix[1],
      expectedArguments: split.suffix
    )
    print(snapshot.startTimeMicroseconds)

  case "arguments-hash":
    let split = splitArguments(arguments.dropFirst(2))
    guard split.prefix.isEmpty, !split.suffix.isEmpty else {
      usage()
    }
    print(argumentsHash(split.suffix))

  case "png":
    guard arguments.count >= 3 else {
      usage()
    }
    for path in arguments.dropFirst(2) {
      _ = try verifiedPNG(at: URL(fileURLWithPath: path))
    }

  case "displays":
    guard arguments.count == 2 else {
      usage()
    }
    for bounds in expectedDisplayWindowBounds() {
      print("\(bounds.minX)\t\(bounds.minY)\t\(bounds.width)\t\(bounds.height)")
    }

  case "capture":
    let split = splitArguments(arguments.dropFirst(2))
    guard split.prefix.count == 10 || split.prefix.count == 11,
          let pid = pid_t(split.prefix[0]),
          let processStartTime = Int64(split.prefix[9]),
          !split.suffix.isEmpty
    else {
      usage()
    }
    let requestedWindowID = split.prefix.count == 11 ? UInt32(split.prefix[10]) : nil
    if split.prefix.count == 11, requestedWindowID == nil {
      usage()
    }
    let output = try capture(
      processIdentifier: pid,
      expectedExecutable: split.prefix[1],
      scenario: split.prefix[2],
      outputDirectory: split.prefix[3],
      sourceFingerprint: split.prefix[4],
      appCDHash: split.prefix[5],
      appExecutableSHA256: split.prefix[6],
      installTransactionID: split.prefix[7],
      installedAt: split.prefix[8],
      expectedProcessStartTimeMicroseconds: processStartTime,
      requestedWindowID: requestedWindowID,
      expectedArguments: split.suffix
    )
    print(output.path)

  case "verify":
    let split = splitArguments(arguments.dropFirst(2))
    guard split.prefix.count == 14,
          let pid = pid_t(split.prefix[1]),
          let processStartTime = Int64(split.prefix[10]),
          let requireLive = Int(split.prefix[12]),
          let printImages = Int(split.prefix[13]),
          [0, 1].contains(requireLive),
          [0, 1].contains(printImages),
          !split.suffix.isEmpty
    else {
      usage()
    }
    let provenance = try verifyProvenance(
      provenanceURL: URL(fileURLWithPath: split.prefix[0]),
      processIdentifier: pid,
      expectedExecutable: split.prefix[2],
      scenario: split.prefix[3],
      outputDirectory: split.prefix[4],
      sourceFingerprint: split.prefix[5],
      appCDHash: split.prefix[6],
      appExecutableSHA256: split.prefix[7],
      installTransactionID: split.prefix[8],
      installedAt: split.prefix[9],
      expectedProcessStartTimeMicroseconds: processStartTime,
      validThrough: split.prefix[11],
      requireLive: requireLive == 1,
      expectedArguments: split.suffix
    )
    if printImages == 1 {
      provenance.captures.forEach { print($0.pngPath) }
    }

  default:
    usage()
  }
} catch {
  fail(error.localizedDescription)
}
