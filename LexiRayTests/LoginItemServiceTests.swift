@testable import LexiRay
import ServiceManagement
import XCTest

final class LoginItemServiceTests: XCTestCase {
  func testMapsSystemStatusToUserVisibleStatus() {
    XCTAssertEqual(LoginItemStatus.fromSystemStatus(.notRegistered), .disabled)
    XCTAssertEqual(LoginItemStatus.fromSystemStatus(.enabled), .enabled)
    XCTAssertEqual(LoginItemStatus.fromSystemStatus(.requiresApproval), .requiresApproval)

    guard case .unavailable = LoginItemStatus.fromSystemStatus(.notFound) else {
      return XCTFail("Expected unavailable status")
    }
  }

  func testUnavailableStatusIsNotEnabled() {
    let status = LoginItemStatus.unavailable("error")

    XCTAssertFalse(status.isEnabled)
    XCTAssertTrue(status.isUnavailable)
    XCTAssertEqual(status.detail, "error")
  }
}
