import AppKit
import Combine
import Foundation
import ServiceManagement

enum LoginItemStatus: Equatable {
  case notRegistered
  case enabled
  case requiresApproval
  case unavailable(String)

  var isEnabled: Bool {
    self == .enabled
  }

  var isUnavailable: Bool {
    if case .unavailable = self {
      return true
    }
    return false
  }

  var persistedValue: String? {
    switch self {
    case .notRegistered:
      "notRegistered"
    case .enabled:
      "enabled"
    case .requiresApproval:
      "requiresApproval"
    case .unavailable:
      nil
    }
  }

  init?(persistedValue: String) {
    switch persistedValue {
    case "notRegistered":
      self = .notRegistered
    case "enabled":
      self = .enabled
    case "requiresApproval":
      self = .requiresApproval
    default:
      return nil
    }
  }

  var detail: String? {
    switch self {
    case .notRegistered:
      "Off"
    case .enabled:
      "Enabled"
    case .requiresApproval:
      "macOS requires approval in Login Items."
    case let .unavailable(message):
      message
    }
  }

  static func fromSystemStatus(_ status: SMAppService.Status) -> LoginItemStatus {
    switch status {
    case .notRegistered:
      .notRegistered
    case .enabled:
      .enabled
    case .requiresApproval:
      .requiresApproval
    case .notFound:
      .unavailable("Login item service is unavailable for this app.")
    @unknown default:
      .unavailable("Login item service returned an unknown status.")
    }
  }
}

@MainActor
protocol LoginItemSystemServicing: AnyObject {
  var status: LoginItemStatus { get }
  func register() throws
  func unregister() throws
}

@MainActor
final class SystemLoginItemService: LoginItemSystemServicing {
  var status: LoginItemStatus {
    LoginItemStatus.fromSystemStatus(SMAppService.mainApp.status)
  }

  func register() throws {
    try SMAppService.mainApp.register()
  }

  func unregister() throws {
    try SMAppService.mainApp.unregister()
  }
}

@MainActor
final class UnavailableLoginItemSystemService: LoginItemSystemServicing {
  private let message: String

  init(message: String) {
    self.message = message
  }

  var status: LoginItemStatus {
    .unavailable(message)
  }

  func register() throws {
    throw UnavailableLoginItemError(message: message)
  }

  func unregister() throws {
    throw UnavailableLoginItemError(message: message)
  }
}

private struct UnavailableLoginItemError: LocalizedError {
  let message: String

  var errorDescription: String? {
    message
  }
}

@MainActor
final class IsolatedLoginItemSystemService: LoginItemSystemServicing {
  private(set) var status: LoginItemStatus

  init(status: LoginItemStatus = .notRegistered) {
    self.status = status
  }

  func register() {
    status = .enabled
  }

  func unregister() {
    status = .notRegistered
  }
}

@MainActor
final class LoginItemCoordinator: ObservableObject {
  @Published private(set) var status: LoginItemStatus
  @Published private(set) var desiredStartAtLogin: Bool
  @Published private(set) var operationError: String?

  private let systemService: LoginItemSystemServicing
  private let defaults: UserDefaults
  private var hasAttemptedStartupRepair = false

  private enum Keys {
    static let desiredStartAtLogin = "desiredStartAtLogin"
    static let lastSystemStatus = "lastLoginItemSystemStatus"
  }

  init(systemService: LoginItemSystemServicing, defaults: UserDefaults) {
    self.systemService = systemService
    self.defaults = defaults
    let currentStatus = systemService.status
    status = currentStatus

    if defaults.object(forKey: Keys.desiredStartAtLogin) == nil {
      let migratedIntent = currentStatus == .enabled || currentStatus == .requiresApproval
      desiredStartAtLogin = migratedIntent
      defaults.set(migratedIntent, forKey: Keys.desiredStartAtLogin)
      persist(status)
    } else {
      desiredStartAtLogin = defaults.bool(forKey: Keys.desiredStartAtLogin)
    }
  }

  var detail: String? {
    operationError ?? status.detail
  }

  var needsSystemApproval: Bool {
    status == .requiresApproval
  }

  var canRetryDesiredOperation: Bool {
    if operationError != nil {
      return true
    }
    return switch (desiredStartAtLogin, status) {
    case (true, .notRegistered), (false, .enabled):
      true
    default:
      false
    }
  }

  func reconcileAtStartup() {
    guard !hasAttemptedStartupRepair else {
      return
    }
    hasAttemptedStartupRepair = true
    operationError = nil

    let currentStatus = systemService.status
    status = currentStatus
    let previousStatus = defaults.string(forKey: Keys.lastSystemStatus)
      .flatMap(LoginItemStatus.init(persistedValue:))

    guard desiredStartAtLogin,
          previousStatus == .enabled,
          currentStatus == .notRegistered
    else {
      persist(currentStatus)
      return
    }

    do {
      try systemService.register()
      status = systemService.status
      persist(status)
      AppLog.settings.info("Restored missing login item registration")
    } catch {
      status = systemService.status
      operationError = "Could not restore Start at login. Try again in Settings."
      // Keep the last confirmed enabled state so a future process can make one
      // fresh repair attempt; this process is guarded from retry loops.
      AppLog.settings.error("Failed to restore login item: \(error.localizedDescription, privacy: .public)")
    }
  }

  func refresh() {
    status = systemService.status
    if statusMatchesDesiredIntent {
      operationError = nil
    }
    let previousStatus = defaults.string(forKey: Keys.lastSystemStatus)
      .flatMap(LoginItemStatus.init(persistedValue:))
    let preservesFailedRepair = operationError != nil
      && hasAttemptedStartupRepair
      && desiredStartAtLogin
      && previousStatus == .enabled
      && status == .notRegistered
    if !preservesFailedRepair {
      persist(status)
    }
  }

  func setDesiredStartAtLogin(_ isEnabled: Bool) {
    desiredStartAtLogin = isEnabled
    defaults.set(isEnabled, forKey: Keys.desiredStartAtLogin)
    operationError = nil

    do {
      if isEnabled {
        if systemService.status != .enabled,
           systemService.status != .requiresApproval
        {
          try systemService.register()
        }
      } else if systemService.status != .notRegistered {
        try systemService.unregister()
      }
      status = systemService.status
      if statusMatchesDesiredIntent {
        operationError = nil
      }
      persist(status)
    } catch {
      status = systemService.status
      operationError = isEnabled
        ? "Could not enable Start at login. Try again."
        : "Could not disable Start at login. Try again."
      AppLog.settings.error("Failed to update login item: \(error.localizedDescription, privacy: .public)")
    }
  }

  func retryDesiredOperation() {
    setDesiredStartAtLogin(desiredStartAtLogin)
  }

  static func openSystemSettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else {
      return
    }
    NSWorkspace.shared.open(url)
  }

  private func persist(_ status: LoginItemStatus) {
    guard let value = status.persistedValue else {
      return
    }
    defaults.set(value, forKey: Keys.lastSystemStatus)
  }

  private var statusMatchesDesiredIntent: Bool {
    switch (desiredStartAtLogin, status) {
    case (true, .enabled), (false, .notRegistered):
      true
    default:
      false
    }
  }
}
