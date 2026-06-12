import AppKit
import ApplicationServices
import Foundation

protocol PermissionChecking {
  var isAccessibilityTrusted: Bool { get }
  var isScreenCaptureTrusted: Bool { get }

  @discardableResult
  func requestAccessibilityIfNeeded(prompt: Bool) -> Bool
}

struct SystemPermissionChecker: PermissionChecking {
  var isAccessibilityTrusted: Bool {
    PermissionService.isAccessibilityTrusted
  }

  var isScreenCaptureTrusted: Bool {
    PermissionService.isScreenCaptureTrusted
  }

  @discardableResult
  func requestAccessibilityIfNeeded(prompt: Bool) -> Bool {
    PermissionService.requestAccessibilityIfNeeded(prompt: prompt)
  }
}

enum PermissionService {
  static var isAccessibilityTrusted: Bool {
    AXIsProcessTrusted()
  }

  static var isScreenCaptureTrusted: Bool {
    CGPreflightScreenCaptureAccess()
  }

  @discardableResult
  static func requestAccessibilityIfNeeded(prompt: Bool = true) -> Bool {
    let options = [
      "AXTrustedCheckOptionPrompt": prompt
    ] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  static func openAccessibilitySettings() {
    requestAccessibilityIfNeeded(prompt: true)
    openSettings(path: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
  }

  static func openAutomationSettings() {
    openSettings(path: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
  }

  static func openPrivacySettings() {
    openSettings(path: "x-apple.systempreferences:com.apple.preference.security")
  }

  @discardableResult
  static func requestScreenCaptureIfNeeded() -> Bool {
    guard !isScreenCaptureTrusted else {
      return true
    }

    return CGRequestScreenCaptureAccess()
  }

  static func openScreenCaptureSettings() {
    requestScreenCaptureIfNeeded()
    openSettings(path: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
  }

  private static func openSettings(path: String) {
    guard let url = URL(string: path) else {
      return
    }
    NSWorkspace.shared.open(url)
  }
}
