import AppKit
import ApplicationServices
import Carbon
import Foundation

@MainActor
protocol TextSelectionReading {
  func readSelectedText() async -> SelectionReadResult
}

final class TextSelectionService: TextSelectionReading {
  private let accessibilityReader = AccessibilitySelectionReader()
  private let browserReader = BrowserSelectionReader()
  private let clipboardReader = ClipboardSelectionReader()

  func readSelectedText() async -> SelectionReadResult {
    if let text = accessibilityReader.readSelectedText() {
      AppLog.selection.info("Read selection through Accessibility")
      return SelectionReadResult(text: text, source: .accessibility)
    }

    if let text = browserReader.readSelectedTextFromFrontmostBrowser() {
      AppLog.selection.info("Read selection through browser AppleScript")
      return SelectionReadResult(text: text, source: .browserAppleScript)
    }

    if let text = await clipboardReader.copyCurrentSelection() {
      AppLog.selection.info("Read selection through simulated copy")
      return SelectionReadResult(text: text, source: .simulatedCopy)
    }

    AppLog.selection.warning("No selected text could be read")
    return .unavailable
  }
}

@MainActor
private final class AccessibilitySelectionReader {
  func readSelectedText() -> String? {
    guard PermissionService.requestAccessibilityIfNeeded(prompt: false) else {
      return nil
    }

    let systemWideElement = AXUIElementCreateSystemWide()
    var focusedValue: CFTypeRef?
    let focusedResult = AXUIElementCopyAttributeValue(
      systemWideElement,
      kAXFocusedUIElementAttribute as CFString,
      &focusedValue
    )

    guard focusedResult == .success, let focusedElement = focusedValue else {
      return nil
    }

    var selectedValue: CFTypeRef?
    let selectedResult = AXUIElementCopyAttributeValue(
      focusedElement as! AXUIElement,
      kAXSelectedTextAttribute as CFString,
      &selectedValue
    )

    guard selectedResult == .success, let text = selectedValue as? String else {
      return nil
    }

    return text.nonEmptyTrimmed
  }
}

@MainActor
private final class BrowserSelectionReader {
  func readSelectedTextFromFrontmostBrowser() -> String? {
    guard let bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
      return nil
    }

    guard let source = scriptSource(for: bundleIdentifier) else {
      return nil
    }

    var error: NSDictionary?
    let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&error)

    if let error {
      AppLog.selection.debug("AppleScript selection read failed: \(error.description, privacy: .public)")
    }

    return descriptor?.stringValue?.nonEmptyTrimmed
  }

  private func scriptSource(for bundleIdentifier: String) -> String? {
    switch bundleIdentifier {
    case "com.apple.Safari":
      """
      tell application id "\(bundleIdentifier)"
        if not (exists front window) then return ""
        return do JavaScript "window.getSelection().toString()" in current tab of front window
      end tell
      """
    case "com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser", "com.thebrowser.Browser":
      """
      tell application id "\(bundleIdentifier)"
        if not (exists front window) then return ""
        return execute active tab of front window javascript "window.getSelection().toString()"
      end tell
      """
    default:
      nil
    }
  }
}

@MainActor
private final class ClipboardSelectionReader {
  func copyCurrentSelection() async -> String? {
    let pasteboard = NSPasteboard.general
    let previousString = pasteboard.string(forType: .string)
    let previousChangeCount = pasteboard.changeCount

    pasteboard.clearContents()
    sendCommandC()

    try? await Task.sleep(nanoseconds: 180_000_000)

    let copiedText = pasteboard.string(forType: .string)?.nonEmptyTrimmed

    if let previousString, pasteboard.changeCount != previousChangeCount {
      pasteboard.clearContents()
      pasteboard.setString(previousString, forType: .string)
    }

    return copiedText
  }

  private func sendCommandC() {
    let source = CGEventSource(stateID: .hidSystemState)
    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)

    keyDown?.flags = .maskCommand
    keyUp?.flags = .maskCommand

    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
  }
}
