import Carbon
import Foundation

struct HotKeyConfiguration: Codable, Equatable, Sendable {
  var keyCode: UInt32
  var modifiers: UInt32
  var keyEquivalent: String

  static let defaultTranslate = HotKeyConfiguration(
    keyCode: UInt32(kVK_ANSI_T),
    modifiers: UInt32(cmdKey) | UInt32(optionKey) | UInt32(shiftKey),
    keyEquivalent: "T"
  )

  static let defaultOCR = HotKeyConfiguration(
    keyCode: UInt32(kVK_ANSI_O),
    modifiers: UInt32(cmdKey) | UInt32(optionKey),
    keyEquivalent: "O"
  )

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
