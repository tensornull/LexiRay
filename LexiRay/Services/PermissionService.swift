import AppKit
import ApplicationServices
import Foundation

protocol PermissionChecking {
  var isAccessibilityTrusted: Bool { get }
  var isScreenCaptureTrusted: Bool { get }

  @discardableResult
  func requestAccessibilityIfNeeded(prompt: Bool) -> Bool

  @discardableResult
  func requestScreenCaptureIfNeeded() -> Bool
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

  @discardableResult
  func requestScreenCaptureIfNeeded() -> Bool {
    PermissionService.requestScreenCaptureIfNeeded()
  }
}

final class AcceptancePermissionChecker: PermissionChecking {
  let isAccessibilityTrusted = true
  private(set) var isScreenCaptureTrusted: Bool
  private let grantsScreenCaptureOnRequest: Bool

  init(isScreenCaptureTrusted: Bool, grantsScreenCaptureOnRequest: Bool) {
    self.isScreenCaptureTrusted = isScreenCaptureTrusted
    self.grantsScreenCaptureOnRequest = grantsScreenCaptureOnRequest
  }

  func requestAccessibilityIfNeeded(prompt _: Bool) -> Bool {
    true
  }

  func requestScreenCaptureIfNeeded() -> Bool {
    if grantsScreenCaptureOnRequest {
      isScreenCaptureTrusted = true
    }
    return isScreenCaptureTrusted
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
    openSettings(path: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
  }

  private static func openSettings(path: String) {
    guard let url = URL(string: path) else {
      return
    }
    NSWorkspace.shared.open(url)
  }
}
