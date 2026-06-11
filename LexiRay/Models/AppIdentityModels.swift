import Foundation

enum AppIdentitySignatureState: String, Equatable {
  case stable
  case stableUnofficial
  case unstable
}

enum AppIdentityIssue: Equatable {
  case unstableSignature(String)
  case multipleRunningCopies([String])

  var message: String {
    switch self {
    case let .unstableSignature(reason):
      "LexiRay is running with an unstable app identity: \(reason). Install or run a signed LexiRay build before granting permissions."
    case let .multipleRunningCopies(paths):
      "Multiple LexiRay copies are running. Quit the other copy before using Selection or OCR: \(paths.joined(separator: ", "))"
    }
  }
}

enum AppIdentityClassifier {
  static func signatureState(
    bundleIdentifier: String,
    isSignatureValid: Bool,
    hasCertificate: Bool,
    certificateAuthority: String?
  ) -> AppIdentitySignatureState {
    guard bundleIdentifier == AppConstants.bundleID else {
      return .unstable
    }

    guard isSignatureValid, hasCertificate else {
      return .unstable
    }

    if certificateAuthority == "LexiRay Release Self-Signed" || certificateAuthority == "LexiRay Local Development" {
      return .stable
    }

    return .stableUnofficial
  }

  static func signatureSummary(
    bundleIdentifier: String,
    isSignatureValid: Bool,
    hasCertificate: Bool,
    certificateAuthority: String?
  ) -> String {
    if bundleIdentifier != AppConstants.bundleID {
      return "bundle id \(bundleIdentifier)"
    }

    if !isSignatureValid {
      return "invalid signature"
    }

    if !hasCertificate {
      return "unsigned or ad hoc signature"
    }

    return certificateAuthority ?? "certificate-backed signature"
  }
}

struct AppIdentitySnapshot: Equatable {
  let bundleIdentifier: String
  let bundlePath: String
  let executablePath: String
  let signatureState: AppIdentitySignatureState
  let signatureSummary: String
  let certificateAuthority: String?
  let duplicateExecutablePaths: [String]

  var isStableForTCC: Bool {
    signatureState != .unstable && bundleIdentifier == AppConstants.bundleID
  }

  var blockingIssue: AppIdentityIssue? {
    if !isStableForTCC {
      return .unstableSignature(signatureSummary)
    }

    if !duplicateExecutablePaths.isEmpty {
      return .multipleRunningCopies(duplicateExecutablePaths)
    }

    return nil
  }

  var statusTitle: String {
    if !duplicateExecutablePaths.isEmpty {
      return "Multiple Copies Running"
    }

    switch signatureState {
    case .stable:
      return "Stable"
    case .stableUnofficial:
      return "Stable, Unofficial"
    case .unstable:
      return "Unstable"
    }
  }

  var diagnosticsText: String {
    [
      "LexiRay Diagnostics",
      "Bundle ID: \(bundleIdentifier)",
      "Bundle path: \(bundlePath)",
      "Executable path: \(executablePath)",
      "Signature state: \(signatureState.rawValue)",
      "Signature summary: \(signatureSummary)",
      "Authority: \(certificateAuthority ?? "None")",
      "Duplicate executable paths: \(duplicateExecutablePaths.isEmpty ? "None" : duplicateExecutablePaths.joined(separator: ", "))"
    ].joined(separator: "\n")
  }

  static func currentProcessFallback(reason: String) -> AppIdentitySnapshot {
    AppIdentitySnapshot(
      bundleIdentifier: Bundle.main.bundleIdentifier ?? "Unknown",
      bundlePath: Bundle.main.bundleURL.path,
      executablePath: Bundle.main.executableURL?.path ?? "Unknown",
      signatureState: .unstable,
      signatureSummary: reason,
      certificateAuthority: nil,
      duplicateExecutablePaths: []
    )
  }

  static func stableForTesting(duplicateExecutablePaths: [String] = []) -> AppIdentitySnapshot {
    AppIdentitySnapshot(
      bundleIdentifier: AppConstants.bundleID,
      bundlePath: "/tmp/LexiRay.app",
      executablePath: "/tmp/LexiRay.app/Contents/MacOS/LexiRay",
      signatureState: .stable,
      signatureSummary: "LexiRay Local Development",
      certificateAuthority: "LexiRay Local Development",
      duplicateExecutablePaths: duplicateExecutablePaths
    )
  }
}
