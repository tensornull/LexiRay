import AppKit
import Foundation
import Security

protocol AppIdentityChecking {
  var currentSnapshot: AppIdentitySnapshot { get }
}

enum AppIdentityCheckerFactory {
  static func makeDefault() -> AppIdentityChecking {
    if AppRuntime.isRunningTests {
      return StaticAppIdentityChecker(snapshot: .stableForTesting())
    }

    return AppIdentityService()
  }
}

struct StaticAppIdentityChecker: AppIdentityChecking {
  let snapshot: AppIdentitySnapshot

  var currentSnapshot: AppIdentitySnapshot {
    snapshot
  }
}

struct AppIdentityService: AppIdentityChecking {
  var currentSnapshot: AppIdentitySnapshot {
    do {
      return try makeSnapshot()
    } catch {
      return AppIdentitySnapshot.currentProcessFallback(reason: error.localizedDescription)
    }
  }

  private func makeSnapshot() throws -> AppIdentitySnapshot {
    var code: SecCode?
    let codeStatus = SecCodeCopySelf([], &code)
    guard codeStatus == errSecSuccess, let code else {
      throw AppIdentityServiceError.security("SecCodeCopySelf failed: \(codeStatus)")
    }

    var staticCode: SecStaticCode?
    let staticStatus = SecCodeCopyStaticCode(code, [], &staticCode)
    guard staticStatus == errSecSuccess, let staticCode else {
      throw AppIdentityServiceError.security("SecCodeCopyStaticCode failed: \(staticStatus)")
    }

    let validityStatus = SecCodeCheckValidity(code, [], nil)
    let signatureInfo = signingInfo(for: staticCode)
    let bundleIdentifier = (signatureInfo[kSecCodeInfoIdentifier as String] as? String)
      ?? Bundle.main.bundleIdentifier
      ?? "Unknown"
    let certificates = signatureInfo[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? []
    let certificateAuthority = certificateName(from: certificates.first)
    let isSignatureValid = validityStatus == errSecSuccess
    let hasCertificate = !certificates.isEmpty
    let signatureState = AppIdentityClassifier.signatureState(
      bundleIdentifier: bundleIdentifier,
      isSignatureValid: isSignatureValid,
      hasCertificate: hasCertificate,
      certificateAuthority: certificateAuthority
    )
    let signatureSummary = AppIdentityClassifier.signatureSummary(
      bundleIdentifier: bundleIdentifier,
      isSignatureValid: isSignatureValid,
      hasCertificate: hasCertificate,
      certificateAuthority: certificateAuthority
    )
    let decoratedSignatureSummary = validityStatus == errSecSuccess
      ? signatureSummary
      : "\(signatureSummary) (\(validityStatus))"

    return AppIdentitySnapshot(
      bundleIdentifier: bundleIdentifier,
      bundlePath: Bundle.main.bundleURL.path,
      executablePath: Bundle.main.executableURL?.path ?? "Unknown",
      signatureState: signatureState,
      signatureSummary: decoratedSignatureSummary,
      certificateAuthority: certificateAuthority,
      duplicateExecutablePaths: duplicateExecutablePaths()
    )
  }

  private func signingInfo(for staticCode: SecStaticCode) -> [String: Any] {
    var information: CFDictionary?
    let status = SecCodeCopySigningInformation(
      staticCode,
      SecCSFlags(rawValue: kSecCSSigningInformation),
      &information
    )

    guard status == errSecSuccess, let information else {
      return [:]
    }

    return information as? [String: Any] ?? [:]
  }

  private func certificateName(from certificate: SecCertificate?) -> String? {
    guard let certificate else {
      return nil
    }

    return SecCertificateCopySubjectSummary(certificate) as String?
  }

  private func duplicateExecutablePaths() -> [String] {
    let ownPID = ProcessInfo.processInfo.processIdentifier
    let ownExecutablePath = Bundle.main.executableURL?.path

    return NSWorkspace.shared.runningApplications
      .filter { application in
        application.bundleIdentifier == AppConstants.bundleID
          && application.processIdentifier != ownPID
      }
      .compactMap { application in
        application.executableURL?.path ?? application.bundleURL?.path
      }
      .filter { path in
        guard let ownExecutablePath else {
          return true
        }
        return path != ownExecutablePath
      }
      .sorted()
  }
}

private enum AppIdentityServiceError: LocalizedError {
  case security(String)

  var errorDescription: String? {
    switch self {
    case let .security(message):
      message
    }
  }
}
