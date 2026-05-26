import Carbon
import SwiftUI

struct MenuKeyboardShortcut {
  let key: KeyEquivalent
  let modifiers: SwiftUI.EventModifiers
}

extension HotKeyConfiguration {
  var menuKeyboardShortcut: MenuKeyboardShortcut? {
    guard let key = menuKeyEquivalent else {
      return nil
    }

    return MenuKeyboardShortcut(key: key, modifiers: menuEventModifiers)
  }

  private var menuKeyEquivalent: KeyEquivalent? {
    let normalized = keyEquivalent.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalized.count == 1, let character = normalized.lowercased().first {
      return KeyEquivalent(character)
    }

    switch normalized.lowercased() {
    case "space":
      return .space
    case "return":
      return .return
    case "tab":
      return .tab
    case "delete":
      return .delete
    case "escape":
      return .escape
    case "up":
      return .upArrow
    case "down":
      return .downArrow
    case "left":
      return .leftArrow
    case "right":
      return .rightArrow
    default:
      return nil
    }
  }

  private var menuEventModifiers: SwiftUI.EventModifiers {
    var result = SwiftUI.EventModifiers()
    if modifiers & UInt32(controlKey) != 0 {
      result.insert(.control)
    }
    if modifiers & UInt32(optionKey) != 0 {
      result.insert(.option)
    }
    if modifiers & UInt32(shiftKey) != 0 {
      result.insert(.shift)
    }
    if modifiers & UInt32(cmdKey) != 0 {
      result.insert(.command)
    }
    return result
  }
}
