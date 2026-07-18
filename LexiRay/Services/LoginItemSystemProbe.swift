import Foundation

struct LoginItemSystemProbeResult: Codable, Equatable {
  enum Outcome: String, Codable {
    case passed
    case blocked
    case failed
  }

  let schemaVersion: Int
  let kind: String
  let outcome: Outcome
  let initialStatus: String
  let registeredStatus: String?
  let finalStatus: String
  let errorPhase: String?
  let errorDomain: String?
  let errorCode: Int?
  let errorMessage: String?
  let errorReason: String?
  let operatingSystem: String
  let appPath: String
  let bundleID: String
  let completedAt: String

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case kind
    case outcome
    case initialStatus = "initial_status"
    case registeredStatus = "registered_status"
    case finalStatus = "final_status"
    case errorPhase = "error_phase"
    case errorDomain = "error_domain"
    case errorCode = "error_code"
    case errorMessage = "error_message"
    case errorReason = "error_reason"
    case operatingSystem = "operating_system"
    case appPath = "app_path"
    case bundleID = "bundle_id"
    case completedAt = "completed_at"
  }
}

@MainActor
enum LoginItemSystemProbe {
  static func run(
    service: LoginItemSystemServicing,
    appPath: String = Bundle.main.bundleURL.path,
    bundleID: String = Bundle.main.bundleIdentifier ?? "Unknown",
    operatingSystem: String = ProcessInfo.processInfo.operatingSystemVersionString,
    completedAt: String = ISO8601DateFormatter().string(from: Date())
  ) -> LoginItemSystemProbeResult {
    let initialStatus = service.status
    switch initialStatus {
    case .enabled:
      return result(
        outcome: .passed,
        initial: initialStatus,
        registered: nil,
        final: initialStatus,
        appPath: appPath,
        bundleID: bundleID,
        operatingSystem: operatingSystem,
        completedAt: completedAt
      )
    case .requiresApproval:
      return result(
        outcome: .blocked,
        initial: initialStatus,
        registered: nil,
        final: initialStatus,
        phase: "initial-status",
        error: ProbeError.systemApprovalRequired,
        appPath: appPath,
        bundleID: bundleID,
        operatingSystem: operatingSystem,
        completedAt: completedAt
      )
    case .notRegistered, .notFound:
      return probeRegistration(
        service: service,
        initialStatus: initialStatus,
        appPath: appPath,
        bundleID: bundleID,
        operatingSystem: operatingSystem,
        completedAt: completedAt
      )
    case let .unavailable(message):
      return result(
        outcome: .failed,
        initial: initialStatus,
        registered: nil,
        final: initialStatus,
        phase: "initial-status",
        error: ProbeError.unavailable(message),
        appPath: appPath,
        bundleID: bundleID,
        operatingSystem: operatingSystem,
        completedAt: completedAt
      )
    }
  }

  static func write(_ result: LoginItemSystemProbeResult, to outputURL: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(result).write(to: outputURL, options: .atomic)
  }

  private static func probeRegistration(
    service: LoginItemSystemServicing,
    initialStatus: LoginItemStatus,
    appPath: String,
    bundleID: String,
    operatingSystem: String,
    completedAt: String
  ) -> LoginItemSystemProbeResult {
    do {
      try service.register()
    } catch {
      return result(
        outcome: .failed,
        initial: initialStatus,
        registered: service.status,
        final: service.status,
        phase: "register",
        error: error,
        appPath: appPath,
        bundleID: bundleID,
        operatingSystem: operatingSystem,
        completedAt: completedAt
      )
    }

    let registeredStatus = service.status
    let registrationOutcome: LoginItemSystemProbeResult.Outcome
    let registrationError: Error?
    switch registeredStatus {
    case .enabled:
      registrationOutcome = .passed
      registrationError = nil
    case .requiresApproval:
      registrationOutcome = .blocked
      registrationError = ProbeError.systemApprovalRequired
    default:
      registrationOutcome = .failed
      registrationError = ProbeError.unexpectedRegisteredStatus(registeredStatus.diagnosticValue)
    }

    guard registeredStatus == .enabled || registeredStatus == .requiresApproval else {
      return result(
        outcome: registrationOutcome,
        initial: initialStatus,
        registered: registeredStatus,
        final: registeredStatus,
        phase: "registered-status",
        error: registrationError,
        appPath: appPath,
        bundleID: bundleID,
        operatingSystem: operatingSystem,
        completedAt: completedAt
      )
    }

    do {
      try service.unregister()
    } catch {
      return result(
        outcome: .failed,
        initial: initialStatus,
        registered: registeredStatus,
        final: service.status,
        phase: "restore",
        error: error,
        appPath: appPath,
        bundleID: bundleID,
        operatingSystem: operatingSystem,
        completedAt: completedAt
      )
    }

    let finalStatus = service.status
    guard finalStatus == .notRegistered || finalStatus == .notFound else {
      return result(
        outcome: .failed,
        initial: initialStatus,
        registered: registeredStatus,
        final: finalStatus,
        phase: "restored-status",
        error: ProbeError.unexpectedRestoredStatus(finalStatus.diagnosticValue),
        appPath: appPath,
        bundleID: bundleID,
        operatingSystem: operatingSystem,
        completedAt: completedAt
      )
    }

    return result(
      outcome: registrationOutcome,
      initial: initialStatus,
      registered: registeredStatus,
      final: finalStatus,
      phase: registrationError == nil ? nil : "registered-status",
      error: registrationError,
      appPath: appPath,
      bundleID: bundleID,
      operatingSystem: operatingSystem,
      completedAt: completedAt
    )
  }

  private static func result(
    outcome: LoginItemSystemProbeResult.Outcome,
    initial: LoginItemStatus,
    registered: LoginItemStatus?,
    final: LoginItemStatus,
    phase: String? = nil,
    error: Error? = nil,
    appPath: String,
    bundleID: String,
    operatingSystem: String,
    completedAt: String
  ) -> LoginItemSystemProbeResult {
    let nsError = error as NSError?
    return LoginItemSystemProbeResult(
      schemaVersion: 1,
      kind: "login-item-system-probe",
      outcome: outcome,
      initialStatus: initial.diagnosticValue,
      registeredStatus: registered?.diagnosticValue,
      finalStatus: final.diagnosticValue,
      errorPhase: phase,
      errorDomain: nsError?.domain,
      errorCode: nsError?.code,
      errorMessage: nsError?.localizedDescription,
      errorReason: nsError?.localizedFailureReason,
      operatingSystem: operatingSystem,
      appPath: appPath,
      bundleID: bundleID,
      completedAt: completedAt
    )
  }
}

private enum ProbeError: LocalizedError {
  case systemApprovalRequired
  case unavailable(String)
  case unexpectedRegisteredStatus(String)
  case unexpectedRestoredStatus(String)

  var errorDescription: String? {
    switch self {
    case .systemApprovalRequired:
      "macOS requires approval in Login Items."
    case let .unavailable(message):
      message
    case let .unexpectedRegisteredStatus(status):
      "macOS returned \(status) after register()."
    case let .unexpectedRestoredStatus(status):
      "macOS returned \(status) after restoring the initial off state."
    }
  }
}
