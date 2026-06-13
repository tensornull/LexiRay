@testable import LexiRay
import XCTest

final class AppIdentityTests: XCTestCase {
  func testReleaseIdentityIsStable() {
    let state = AppIdentityClassifier.signatureState(
      bundleIdentifier: AppConstants.bundleID,
      isSignatureValid: true,
      hasCertificate: true,
      certificateAuthority: "LexiRay Release Self-Signed"
    )

    XCTAssertEqual(state, .stable)
  }

  func testUnofficialCertificateBackedIdentityIsStableUnofficial() {
    let state = AppIdentityClassifier.signatureState(
      bundleIdentifier: AppConstants.bundleID,
      isSignatureValid: true,
      hasCertificate: true,
      certificateAuthority: "Developer Self Signed"
    )

    XCTAssertEqual(state, .stableUnofficial)
  }

  func testAdHocIdentityIsUnstable() {
    let state = AppIdentityClassifier.signatureState(
      bundleIdentifier: AppConstants.bundleID,
      isSignatureValid: true,
      hasCertificate: false,
      certificateAuthority: nil
    )

    XCTAssertEqual(state, .unstable)
    XCTAssertEqual(
      AppIdentityClassifier.signatureSummary(
        bundleIdentifier: AppConstants.bundleID,
        isSignatureValid: true,
        hasCertificate: false,
        certificateAuthority: nil
      ),
      "unsigned or ad hoc signature"
    )
  }

  func testInvalidSignatureIsUnstable() {
    let state = AppIdentityClassifier.signatureState(
      bundleIdentifier: AppConstants.bundleID,
      isSignatureValid: false,
      hasCertificate: true,
      certificateAuthority: "LexiRay Release Self-Signed"
    )

    XCTAssertEqual(state, .unstable)
  }

  func testWrongBundleIdentifierIsUnstable() {
    let state = AppIdentityClassifier.signatureState(
      bundleIdentifier: "com.example.other",
      isSignatureValid: true,
      hasCertificate: true,
      certificateAuthority: "LexiRay Release Self-Signed"
    )

    XCTAssertEqual(state, .unstable)
  }

  func testDuplicateCopyCreatesBlockingIssue() {
    let snapshot = AppIdentitySnapshot.stableForTesting(duplicateExecutablePaths: ["/Applications/LexiRay.app/Contents/MacOS/LexiRay"])

    XCTAssertEqual(snapshot.statusTitle, "Multiple Copies Running")
    guard case let .multipleRunningCopies(paths) = snapshot.blockingIssue else {
      return XCTFail("Expected duplicate copy issue")
    }
    XCTAssertEqual(paths, ["/Applications/LexiRay.app/Contents/MacOS/LexiRay"])
  }
}
