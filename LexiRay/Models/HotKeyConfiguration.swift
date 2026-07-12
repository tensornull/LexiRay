import Carbon
import Foundation

struct HotKeyConfiguration: Codable, Equatable {
  var keyCode: UInt32
  var modifiers: UInt32
  var keyEquivalent: String

  static var defaultTranslate: HotKeyConfiguration {
    HotKeyConfiguration(
      keyCode: UInt32(kVK_ANSI_A),
      modifiers: UInt32(controlKey) | UInt32(optionKey),
      keyEquivalent: "A"
    )
  }

  static var defaultOCR: HotKeyConfiguration {
    HotKeyConfiguration(
      keyCode: UInt32(kVK_ANSI_S),
      modifiers: UInt32(controlKey) | UInt32(optionKey),
      keyEquivalent: "S"
    )
  }

  static var acceptanceTranslate: HotKeyConfiguration {
    HotKeyConfiguration(
      keyCode: UInt32(kVK_ANSI_A),
      modifiers: UInt32(controlKey) | UInt32(optionKey) | UInt32(shiftKey),
      keyEquivalent: "A"
    )
  }

  static var acceptanceOCR: HotKeyConfiguration {
    HotKeyConfiguration(
      keyCode: UInt32(kVK_ANSI_S),
      modifiers: UInt32(controlKey) | UInt32(optionKey) | UInt32(shiftKey),
      keyEquivalent: "S"
    )
  }

  var isValidGlobalShortcut: Bool {
    modifiers != 0 && !keyEquivalent.trimmedForQuery.isEmpty
  }

  var displayString: String {
    let modifierText = modifierNames.joined(separator: "-")
    if modifierText.isEmpty {
      return keyEquivalent.uppercased()
    }
    return "\(modifierText)-\(keyEquivalent.uppercased())"
  }

  private var modifierNames: [String] {
    var names: [String] = []
    if modifiers & UInt32(controlKey) != 0 {
      names.append("Control")
    }
    if modifiers & UInt32(optionKey) != 0 {
      names.append("Option")
    }
    if modifiers & UInt32(shiftKey) != 0 {
      names.append("Shift")
    }
    if modifiers & UInt32(cmdKey) != 0 {
      names.append("Command")
    }
    return names
  }
}
