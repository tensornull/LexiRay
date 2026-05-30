import Foundation
import ServiceManagement

enum LoginItemStatus: Equatable {
  case disabled
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

  var detail: String? {
    switch self {
    case .disabled:
      "Off"
    case .enabled:
      "Enabled"
    case .requiresApproval:
      "Requires approval in macOS Login Items."
    case let .unavailable(message):
      message
    }
  }

  static func fromSystemStatus(_ status: SMAppService.Status) -> LoginItemStatus {
    switch status {
    case .notRegistered:
      .disabled
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

enum LoginItemService {
  static var status: LoginItemStatus {
    LoginItemStatus.fromSystemStatus(SMAppService.mainApp.status)
  }

  static func setEnabled(_ isEnabled: Bool) throws {
    if isEnabled {
      try SMAppService.mainApp.register()
    } else {
      try SMAppService.mainApp.unregister()
    }
  }
}
