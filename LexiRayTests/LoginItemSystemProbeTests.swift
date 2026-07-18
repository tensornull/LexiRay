@testable import LexiRay
import XCTest

final class LoginItemSystemProbeTests: XCTestCase {
  @MainActor
  func testNotFoundRegistrationPassesAndRestoresOffState() {
    let service = ProbeLoginItemService(
      status: .notFound,
      registerResult: .enabled,
      unregisterResult: .notFound
    )

    let result = LoginItemSystemProbe.run(
      service: service,
      appPath: "/Applications/LexiRay.app",
      bundleID: AppConstants.bundleID,
      operatingSystem: "macOS 27.0",
      completedAt: "2026-07-18T00:00:00Z"
    )

    XCTAssertEqual(result.outcome, .passed)
    XCTAssertEqual(result.initialStatus, "notFound")
    XCTAssertEqual(result.registeredStatus, "enabled")
    XCTAssertEqual(result.finalStatus, "notFound")
    XCTAssertEqual(service.registerCount, 1)
    XCTAssertEqual(service.unregisterCount, 1)
  }

  @MainActor
  func testInitialApprovalRequirementIsBlockedWithoutMutation() {
    let service = ProbeLoginItemService(status: .requiresApproval)

    let result = LoginItemSystemProbe.run(service: service)

    XCTAssertEqual(result.outcome, .blocked)
    XCTAssertEqual(result.errorPhase, "initial-status")
    XCTAssertEqual(service.registerCount, 0)
    XCTAssertEqual(service.unregisterCount, 0)
  }

  @MainActor
  func testRegisterFailureRecordsNSErrorAndDoesNotClaimSuccess() {
    let error = NSError(domain: "BTMErrorDomain", code: -95, userInfo: [
      NSLocalizedDescriptionKey: "record not found",
      NSLocalizedFailureReasonErrorKey: "the background record is missing"
    ])
    let service = ProbeLoginItemService(status: .notFound, registerError: error)

    let result = LoginItemSystemProbe.run(service: service)

    XCTAssertEqual(result.outcome, .failed)
    XCTAssertEqual(result.errorPhase, "register")
    XCTAssertEqual(result.errorDomain, "BTMErrorDomain")
    XCTAssertEqual(result.errorCode, -95)
    XCTAssertEqual(result.errorMessage, "record not found")
    XCTAssertEqual(result.errorReason, "the background record is missing")
    XCTAssertEqual(service.unregisterCount, 0)
  }

  @MainActor
  func testRestoreFailureIsAProbeFailure() {
    let error = NSError(domain: "SMAppServiceErrorDomain", code: 9)
    let service = ProbeLoginItemService(
      status: .notRegistered,
      registerResult: .enabled,
      unregisterError: error
    )

    let result = LoginItemSystemProbe.run(service: service)

    XCTAssertEqual(result.outcome, .failed)
    XCTAssertEqual(result.errorPhase, "restore")
    XCTAssertEqual(result.finalStatus, "enabled")
    XCTAssertEqual(service.unregisterCount, 1)
  }
}

@MainActor
private final class ProbeLoginItemService: LoginItemSystemServicing {
  private(set) var status: LoginItemStatus
  private(set) var registerCount = 0
  private(set) var unregisterCount = 0
  private let registerResult: LoginItemStatus
  private let unregisterResult: LoginItemStatus
  private let registerError: Error?
  private let unregisterError: Error?

  init(
    status: LoginItemStatus,
    registerResult: LoginItemStatus = .enabled,
    unregisterResult: LoginItemStatus = .notRegistered,
    registerError: Error? = nil,
    unregisterError: Error? = nil
  ) {
    self.status = status
    self.registerResult = registerResult
    self.unregisterResult = unregisterResult
    self.registerError = registerError
    self.unregisterError = unregisterError
  }

  func register() throws {
    registerCount += 1
    if let registerError {
      throw registerError
    }
    status = registerResult
  }

  func unregister() throws {
    unregisterCount += 1
    if let unregisterError {
      throw unregisterError
    }
    status = unregisterResult
  }
}
