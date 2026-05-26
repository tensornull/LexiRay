import AppKit
import Carbon
import SwiftUI

struct HotKeyRecorderButton: NSViewRepresentable {
  @Binding var hotKey: HotKeyConfiguration

  func makeNSView(context _: Context) -> RecorderButton {
    let button = RecorderButton()
    button.onRecord = { hotKey in
      self.hotKey = hotKey
    }
    return button
  }

  func updateNSView(_ nsView: RecorderButton, context _: Context) {
    nsView.applyHotKey(hotKey)
  }
}

final class RecorderButton: NSButton {
  var hotKey: HotKeyConfiguration = .defaultTranslate {
    didSet { updateTitle() }
  }

  var onRecord: ((HotKeyConfiguration) -> Void)?
  private var isRecording = false

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    bezelStyle = .rounded
    target = self
    action = #selector(beginRecording)
    updateTitle()
  }

  func applyHotKey(_ hotKey: HotKeyConfiguration) {
    self.hotKey = hotKey
    updateTitle()
    needsDisplay = true
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    bezelStyle = .rounded
    target = self
    action = #selector(beginRecording)
    updateTitle()
  }

  override var acceptsFirstResponder: Bool {
    true
  }

  override func resignFirstResponder() -> Bool {
    isRecording = false
    updateTitle()
    return super.resignFirstResponder()
  }

  override func keyDown(with event: NSEvent) {
    guard isRecording else {
      super.keyDown(with: event)
      return
    }

    if event.keyCode == UInt16(kVK_Escape) {
      isRecording = false
      updateTitle()
      return
    }

    guard let hotKey = HotKeyConfiguration(event: event), hotKey.isValidGlobalShortcut else {
      NSSound.beep()
      return
    }

    self.hotKey = hotKey
    onRecord?(hotKey)
    isRecording = false
    updateTitle()
    window?.makeFirstResponder(nil)
  }

  @objc private func beginRecording() {
    isRecording = true
    updateTitle()
    window?.makeFirstResponder(self)
  }

  private func updateTitle() {
    title = isRecording ? "Press shortcut..." : hotKey.displayString
    needsDisplay = true
  }
}

extension HotKeyConfiguration {
  init?(event: NSEvent) {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let modifiers = Self.carbonModifiers(from: flags)
    let keyEquivalent = Self.keyEquivalent(from: event)

    self.init(
      keyCode: UInt32(event.keyCode),
      modifiers: modifiers,
      keyEquivalent: keyEquivalent
    )
  }

  private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    var modifiers: UInt32 = 0
    if flags.contains(.control) {
      modifiers |= UInt32(controlKey)
    }
    if flags.contains(.option) {
      modifiers |= UInt32(optionKey)
    }
    if flags.contains(.shift) {
      modifiers |= UInt32(shiftKey)
    }
    if flags.contains(.command) {
      modifiers |= UInt32(cmdKey)
    }
    return modifiers
  }

  private static func keyEquivalent(from event: NSEvent) -> String {
    if let characters = event.charactersIgnoringModifiers?.nonEmptyTrimmed {
      return characters.uppercased()
    }

    switch Int(event.keyCode) {
    case kVK_Space:
      return "Space"
    case kVK_Return:
      return "Return"
    case kVK_Tab:
      return "Tab"
    case kVK_Delete:
      return "Delete"
    case kVK_Escape:
      return "Escape"
    case kVK_UpArrow:
      return "Up"
    case kVK_DownArrow:
      return "Down"
    case kVK_LeftArrow:
      return "Left"
    case kVK_RightArrow:
      return "Right"
    default:
      return ""
    }
  }
}
