@testable import LexiRay
import ServiceManagement
import XCTest

final class LoginItemServiceTests: XCTestCase {
  func testMapsSystemStatusToUserVisibleStatus() {
    XCTAssertEqual(LoginItemStatus.fromSystemStatus(.notRegistered), .notRegistered)
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

  func testCanonicalLoginItemPathRequiresApplicationsInstall() {
    XCTAssertTrue(
      AppRuntime.isCanonicalInstalledApplication(
        bundleURL: URL(fileURLWithPath: "/Applications/LexiRay.app", isDirectory: true)
      )
    )
    XCTAssertFalse(
      AppRuntime.isCanonicalInstalledApplication(
        bundleURL: URL(fileURLWithPath: "/tmp/LexiRay.app", isDirectory: true)
      )
    )
    XCTAssertFalse(
      AppRuntime.isCanonicalInstalledApplication(
        bundleURL: URL(fileURLWithPath: "/Users/test/LexiRay.app", isDirectory: true)
      )
    )
    XCTAssertFalse(
      AppRuntime.isCanonicalInstalledApplication(
        bundleURL: URL(fileURLWithPath: "/Applications/LexiRay Copy.app", isDirectory: true)
      )
    )
  }

  @MainActor
  func testNoncanonicalAppCannotConstructOrMutateRealLoginItemService() {
    let productionDefaults = makeDefaults()
    productionDefaults.set(true, forKey: "desiredStartAtLogin")
    productionDefaults.set("enabled", forKey: "lastLoginItemSystemStatus")
    let isolatedDefaults = makeDefaults()
    var constructedRealService = false

    let coordinator = AppRuntime.makeLoginItemCoordinator(
      acceptanceProfile: nil,
      runningTests: false,
      bundleURL: URL(fileURLWithPath: "/tmp/LexiRay.app", isDirectory: true),
      systemServiceFactory: {
        constructedRealService = true
        return MockLoginItemSystemService(status: .notRegistered)
      },
      standardDefaults: productionDefaults,
      noncanonicalDefaults: isolatedDefaults
    )

    coordinator.reconcileAtStartup()
    coordinator.setDesiredStartAtLogin(true)

    XCTAssertFalse(constructedRealService)
    XCTAssertTrue(coordinator.status.isUnavailable)
    XCTAssertEqual(productionDefaults.bool(forKey: "desiredStartAtLogin"), true)
    XCTAssertEqual(productionDefaults.string(forKey: "lastLoginItemSystemStatus"), "enabled")
  }

  @MainActor
  func testMigratesLegacyEnabledAndApprovalStatusesAsDesiredOn() {
    for status in [LoginItemStatus.enabled, .requiresApproval] {
      let defaults = makeDefaults()
      let coordinator = LoginItemCoordinator(
        systemService: MockLoginItemSystemService(status: status),
        defaults: defaults
      )

      XCTAssertTrue(coordinator.desiredStartAtLogin)
    }
  }

  @MainActor
  func testMigratesLegacyNotRegisteredStatusAsDesiredOff() {
    let coordinator = LoginItemCoordinator(
      systemService: MockLoginItemSystemService(status: .notRegistered),
      defaults: makeDefaults()
    )

    XCTAssertFalse(coordinator.desiredStartAtLogin)
  }

  @MainActor
  func testRepairsRegistrationLostAfterPreviouslyEnabled() {
    let defaults = makeDefaults()
    defaults.set(true, forKey: "desiredStartAtLogin")
    defaults.set("enabled", forKey: "lastLoginItemSystemStatus")
    let system = MockLoginItemSystemService(status: .notRegistered)
    let coordinator = LoginItemCoordinator(systemService: system, defaults: defaults)

    coordinator.reconcileAtStartup()

    XCTAssertEqual(system.registerCount, 1)
    XCTAssertEqual(coordinator.status, .enabled)
  }

  @MainActor
  func testDoesNotFightSystemApprovalRequirement() {
    let defaults = makeDefaults()
    defaults.set(true, forKey: "desiredStartAtLogin")
    defaults.set("enabled", forKey: "lastLoginItemSystemStatus")
    let system = MockLoginItemSystemService(status: .requiresApproval)
    let coordinator = LoginItemCoordinator(systemService: system, defaults: defaults)

    coordinator.reconcileAtStartup()

    XCTAssertEqual(system.registerCount, 0)
    XCTAssertTrue(coordinator.needsSystemApproval)
  }

  @MainActor
  func testFailedRepairRunsOnlyOncePerProcess() {
    let defaults = makeDefaults()
    defaults.set(true, forKey: "desiredStartAtLogin")
    defaults.set("enabled", forKey: "lastLoginItemSystemStatus")
    let system = MockLoginItemSystemService(status: .notRegistered, registerError: TestError.failed)
    let coordinator = LoginItemCoordinator(systemService: system, defaults: defaults)

    coordinator.reconcileAtStartup()
    coordinator.reconcileAtStartup()
    coordinator.refresh()

    XCTAssertEqual(system.registerCount, 1)
    XCTAssertNotNil(coordinator.operationError)
    XCTAssertEqual(defaults.string(forKey: "lastLoginItemSystemStatus"), "enabled")
  }

  @MainActor
  func testFailedDisableRefreshPreservesOffIntentForRetry() {
    let defaults = makeDefaults()
    defaults.set(true, forKey: "desiredStartAtLogin")
    defaults.set("enabled", forKey: "lastLoginItemSystemStatus")
    let system = MockLoginItemSystemService(status: .enabled, unregisterError: TestError.failed)
    let coordinator = LoginItemCoordinator(systemService: system, defaults: defaults)

    coordinator.setDesiredStartAtLogin(false)
    coordinator.refresh()

    XCTAssertFalse(coordinator.desiredStartAtLogin)
    XCTAssertTrue(coordinator.canRetryDesiredOperation)
    XCTAssertNotNil(coordinator.operationError)

    let relaunched = LoginItemCoordinator(systemService: system, defaults: defaults)
    relaunched.refresh()
    relaunched.retryDesiredOperation()

    XCTAssertFalse(relaunched.desiredStartAtLogin)
    XCTAssertEqual(system.unregisterCount, 2)
    XCTAssertTrue(relaunched.canRetryDesiredOperation)
  }

  @MainActor
  func testRefreshClearsFailureWhenSystemReachesDesiredState() {
    let defaults = makeDefaults()
    defaults.set(true, forKey: "desiredStartAtLogin")
    defaults.set("enabled", forKey: "lastLoginItemSystemStatus")
    let system = MockLoginItemSystemService(status: .enabled, unregisterError: TestError.failed)
    let coordinator = LoginItemCoordinator(systemService: system, defaults: defaults)

    coordinator.setDesiredStartAtLogin(false)
    XCTAssertNotNil(coordinator.operationError)

    system.resolve(status: .notRegistered)
    coordinator.refresh()

    XCTAssertNil(coordinator.operationError)
    XCTAssertFalse(coordinator.canRetryDesiredOperation)
    XCTAssertEqual(defaults.string(forKey: "lastLoginItemSystemStatus"), "notRegistered")
  }

  @MainActor
  func testSettingAlreadySatisfiedIntentDoesNotRepeatSystemOperation() {
    let enabledSystem = MockLoginItemSystemService(status: .enabled)
    let enabledCoordinator = LoginItemCoordinator(systemService: enabledSystem, defaults: makeDefaults())
    enabledCoordinator.setDesiredStartAtLogin(true)

    let disabledSystem = MockLoginItemSystemService(status: .notRegistered)
    let disabledCoordinator = LoginItemCoordinator(systemService: disabledSystem, defaults: makeDefaults())
    disabledCoordinator.setDesiredStartAtLogin(false)

    XCTAssertEqual(enabledSystem.registerCount, 0)
    XCTAssertEqual(disabledSystem.unregisterCount, 0)
  }

  private func makeDefaults() -> UserDefaults {
    let suiteName = "LoginItemServiceTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }
}

@MainActor
private final class MockLoginItemSystemService: LoginItemSystemServicing {
  private(set) var status: LoginItemStatus
  private(set) var registerCount = 0
  private(set) var unregisterCount = 0
  private let registerError: Error?
  private let unregisterError: Error?

  init(
    status: LoginItemStatus,
    registerError: Error? = nil,
    unregisterError: Error? = nil
  ) {
    self.status = status
    self.registerError = registerError
    self.unregisterError = unregisterError
  }

  func register() throws {
    registerCount += 1
    if let registerError {
      throw registerError
    }
    status = .enabled
  }

  func unregister() throws {
    unregisterCount += 1
    if let unregisterError {
      throw unregisterError
    }
    status = .notRegistered
  }

  func resolve(status: LoginItemStatus) {
    self.status = status
  }
}

private enum TestError: Error {
  case failed
}
