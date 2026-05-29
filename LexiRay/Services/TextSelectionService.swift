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
    let accessibilityTrusted = PermissionService.isAccessibilityTrusted

    if let text = accessibilityReader.readSelectedText() {
      logSelectionRead(source: .accessibility, text: text)
      return SelectionReadResult(text: text, source: .accessibility)
    }

    if let text = browserReader.readSelectedTextFromFrontmostBrowser() {
      logSelectionRead(source: .browserAppleScript, text: text)
      return SelectionReadResult(text: text, source: .browserAppleScript)
    }

    if let text = await clipboardReader.copyCurrentSelection() {
      logSelectionRead(source: .simulatedCopy, text: text)
      return SelectionReadResult(text: text, source: .simulatedCopy)
    }

    AppLog.selection.warning("No selected text could be read")
    let reason: SelectionFailureReason = accessibilityTrusted ? .copyFailed : .accessibilityPermissionMissing
    return SelectionReadResult(text: nil, source: .unavailable, failureReason: reason)
  }

  private func logSelectionRead(source: SelectionSource, text: String) {
    AppLog.selection.info(
      "Read selection through \(source.displayName, privacy: .public), characters: \(text.count)"
    )
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

    guard focusedResult == .success,
          let focusedElementValue = focusedValue,
          CFGetTypeID(focusedElementValue) == AXUIElementGetTypeID()
    else {
      return nil
    }
    let focusedElement = unsafeDowncast(focusedElementValue, to: AXUIElement.self)

    var selectedValue: CFTypeRef?
    let selectedResult = AXUIElementCopyAttributeValue(
      focusedElement,
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
final class ClipboardSelectionReader {
  private let pasteboard: NSPasteboard
  private let frontmostBundleIdentifier: @MainActor () -> String?
  private let copyAction: @MainActor () -> Void
  private let waitAfterCopy: @MainActor (UInt64) async -> Void

  init(
    pasteboard: NSPasteboard = .general,
    frontmostBundleIdentifier: @escaping @MainActor () -> String? = {
      NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    },
    copyAction: (@MainActor () -> Void)? = nil,
    waitAfterCopy: @escaping @MainActor (UInt64) async -> Void = { nanoseconds in
      try? await Task.sleep(nanoseconds: nanoseconds)
    }
  ) {
    self.pasteboard = pasteboard
    self.frontmostBundleIdentifier = frontmostBundleIdentifier
    self.waitAfterCopy = waitAfterCopy
    self.copyAction = copyAction ?? Self.sendCommandC
  }

  func copyCurrentSelection() async -> String? {
    if frontmostBundleIdentifier() == AppConstants.bundleID {
      AppLog.selection.info("Skipped simulated copy because LexiRay is frontmost")
      return nil
    }

    let previousItems = pasteboard.pasteboardItems?.map(Self.copyPasteboardItem)

    pasteboard.clearContents()
    let baselineChangeCount = pasteboard.changeCount
    copyAction()

    await waitAfterCopy(320_000_000)

    let copiedText = pasteboard.changeCount == baselineChangeCount
      ? nil
      : pasteboard.string(forType: .string)?.nonEmptyTrimmed

    pasteboard.clearContents()
    if let previousItems, !previousItems.isEmpty {
      pasteboard.writeObjects(previousItems)
    }

    return copiedText
  }

  private static func copyPasteboardItem(_ item: NSPasteboardItem) -> NSPasteboardItem {
    let copy = NSPasteboardItem()
    for type in item.types {
      if let data = item.data(forType: type) {
        copy.setData(data, forType: type)
      }
    }
    return copy
  }

  private static func sendCommandC() {
    let source = CGEventSource(stateID: .hidSystemState)
    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)

    keyDown?.flags = .maskCommand
    keyUp?.flags = .maskCommand

    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
  }
}
