import AppKit
import ApplicationServices
import Foundation

enum PermissionService {
  static var isAccessibilityTrusted: Bool {
    AXIsProcessTrusted()
  }

  @discardableResult
  static func requestAccessibilityIfNeeded(prompt: Bool = true) -> Bool {
    let options = [
      "AXTrustedCheckOptionPrompt": prompt
    ] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  static func openAccessibilitySettings() {
    openSettings(path: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
  }

  static func openAutomationSettings() {
    openSettings(path: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
  }

  private static func openSettings(path: String) {
    guard let url = URL(string: path) else {
      return
    }
    NSWorkspace.shared.open(url)
  }
}
