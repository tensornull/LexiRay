@testable import LexiRay
import XCTest

final class TextSelectionServiceTests: XCTestCase {
  func testAcceptancePolicyAllowsOnlyCurrentLexiRayProcess() {
    XCTAssertTrue(
      AcceptanceSelectionTargetPolicy.allows(
        bundleIdentifier: AppConstants.bundleID,
        processIdentifier: 4101,
        currentProcessIdentifier: 4101,
        fixtureProcessIdentifier: 5201
      )
    )
    XCTAssertFalse(
      AcceptanceSelectionTargetPolicy.allows(
        bundleIdentifier: AppConstants.bundleID,
        processIdentifier: 4102,
        currentProcessIdentifier: 4101,
        fixtureProcessIdentifier: 5201
      )
    )
  }

  func testAcceptancePolicyAllowsOnlyExactTextEditFixtureProcess() {
    XCTAssertTrue(
      AcceptanceSelectionTargetPolicy.allows(
        bundleIdentifier: "com.apple.TextEdit",
        processIdentifier: 5201,
        currentProcessIdentifier: 4101,
        fixtureProcessIdentifier: 5201
      )
    )
    XCTAssertFalse(
      AcceptanceSelectionTargetPolicy.allows(
        bundleIdentifier: "com.apple.TextEdit",
        processIdentifier: 5202,
        currentProcessIdentifier: 4101,
        fixtureProcessIdentifier: 5201
      )
    )
  }

  func testAcceptancePolicyRejectsMissingOrUnrelatedProcess() {
    XCTAssertFalse(
      AcceptanceSelectionTargetPolicy.allows(
        bundleIdentifier: nil,
        processIdentifier: nil,
        currentProcessIdentifier: 4101,
        fixtureProcessIdentifier: 5201
      )
    )
    XCTAssertFalse(
      AcceptanceSelectionTargetPolicy.allows(
        bundleIdentifier: "com.apple.finder",
        processIdentifier: 5201,
        currentProcessIdentifier: 4101,
        fixtureProcessIdentifier: 5201
      )
    )
  }
}
