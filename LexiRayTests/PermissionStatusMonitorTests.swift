import AppKit
import Combine
@testable import LexiRay
import XCTest

@MainActor
final class PermissionStatusMonitorTests: XCTestCase {
  func testStartPublishesCurrentStatus() {
    let checker = MutablePermissionChecker(accessibilityTrusted: false, screenCaptureTrusted: false)
    let monitor = makeMonitor(checker: checker)
    defer { monitor.stop() }

    checker.accessibilityTrusted = true
    checker.screenCaptureTrusted = true
    monitor.start()

    XCTAssertEqual(
      monitor.status,
      PermissionStatus(isAccessibilityTrusted: true, isScreenCaptureTrusted: true)
    )
  }

  func testAccessibilityNotificationTriggersRefresh() async {
    let checker = MutablePermissionChecker(accessibilityTrusted: false, screenCaptureTrusted: false)
    let distributedCenter = NotificationCenter()
    let monitor = makeMonitor(checker: checker, distributedCenter: distributedCenter)
    defer { monitor.stop() }
    monitor.start()
    XCTAssertFalse(monitor.status.isAccessibilityTrusted)

    checker.accessibilityTrusted = true
    distributedCenter.post(name: accessibilityAPINotification, object: nil)

    await waitUntil { monitor.status.isAccessibilityTrusted }
  }

  func testNotificationRecheckCatchesLateTCCWrite() async {
    let checker = MutablePermissionChecker(accessibilityTrusted: false, screenCaptureTrusted: false)
    let distributedCenter = NotificationCenter()
    let monitor = makeMonitor(checker: checker, distributedCenter: distributedCenter)
    defer { monitor.stop() }
    monitor.start()

    // The read triggered by the notification still sees the stale value; the
    // checker flips only after that read, so just the delayed re-check can
    // observe the granted permission.
    checker.onAccessibilityRead = { [weak checker] in
      checker?.accessibilityTrusted = true
      checker?.onAccessibilityRead = nil
    }
    distributedCenter.post(name: accessibilityAPINotification, object: nil)

    await waitUntil { monitor.status.isAccessibilityTrusted }
  }

  func testAppActivationTriggersRefresh() async {
    let checker = MutablePermissionChecker(accessibilityTrusted: true, screenCaptureTrusted: false)
    let applicationCenter = NotificationCenter()
    let monitor = makeMonitor(checker: checker, applicationCenter: applicationCenter)
    defer { monitor.stop() }
    monitor.start()
    XCTAssertFalse(monitor.status.isScreenCaptureTrusted)

    checker.screenCaptureTrusted = true
    applicationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)

    await waitUntil { monitor.status.isScreenCaptureTrusted }
  }

  func testFallbackPollingRefreshesWithoutEvents() async {
    let checker = MutablePermissionChecker(accessibilityTrusted: false, screenCaptureTrusted: false)
    let monitor = makeMonitor(checker: checker, fallbackPollInterval: .milliseconds(20))
    defer { monitor.stop() }
    monitor.start()

    checker.accessibilityTrusted = true
    checker.screenCaptureTrusted = true

    await waitUntil { monitor.status.isAccessibilityTrusted && monitor.status.isScreenCaptureTrusted }
  }

  func testStopRemovesObserversAndCancelsPolling() async {
    let checker = MutablePermissionChecker(accessibilityTrusted: false, screenCaptureTrusted: false)
    let distributedCenter = NotificationCenter()
    let applicationCenter = NotificationCenter()
    let monitor = makeMonitor(
      checker: checker,
      distributedCenter: distributedCenter,
      applicationCenter: applicationCenter,
      fallbackPollInterval: .milliseconds(20)
    )
    monitor.start()
    monitor.stop()

    let readsAfterStop = checker.accessibilityReadCount
    checker.accessibilityTrusted = true
    distributedCenter.post(name: accessibilityAPINotification, object: nil)
    applicationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)
    try? await Task.sleep(for: .milliseconds(120))

    XCTAssertFalse(monitor.status.isAccessibilityTrusted)
    XCTAssertEqual(checker.accessibilityReadCount, readsAfterStop)
  }

  func testRefreshEventsFireEveryTickAndStatusPublishesOnlyOnChange() {
    let checker = MutablePermissionChecker(accessibilityTrusted: false, screenCaptureTrusted: false)
    let monitor = makeMonitor(checker: checker)
    defer { monitor.stop() }

    var refreshCount = 0
    var statusChanges = 0
    var cancellables: Set<AnyCancellable> = []
    monitor.refreshEvents
      .sink { refreshCount += 1 }
      .store(in: &cancellables)
    monitor.$status
      .dropFirst()
      .sink { _ in statusChanges += 1 }
      .store(in: &cancellables)

    monitor.start()
    monitor.refreshNow()
    checker.accessibilityTrusted = true
    monitor.refreshNow()
    monitor.refreshNow()

    XCTAssertEqual(refreshCount, 4)
    XCTAssertEqual(statusChanges, 1)
  }

  private let accessibilityAPINotification = Notification.Name("com.apple.accessibility.api")

  private func makeMonitor(
    checker: MutablePermissionChecker,
    distributedCenter: NotificationCenter = NotificationCenter(),
    applicationCenter: NotificationCenter = NotificationCenter(),
    fallbackPollInterval: Duration = .seconds(3600),
    notificationRecheckDelay: Duration = .milliseconds(50)
  ) -> PermissionStatusMonitor {
    PermissionStatusMonitor(
      permissionChecker: checker,
      distributedCenter: distributedCenter,
      applicationCenter: applicationCenter,
      fallbackPollInterval: fallbackPollInterval,
      notificationRecheckDelay: notificationRecheckDelay
    )
  }

  private func waitUntil(
    _ condition: @escaping @MainActor () -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    for _ in 0 ..< 100 {
      if condition() {
        return
      }
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for condition", file: file, line: line)
  }
}

private final class MutablePermissionChecker: PermissionChecking {
  var accessibilityTrusted: Bool
  var screenCaptureTrusted: Bool
  var onAccessibilityRead: (() -> Void)?
  private(set) var accessibilityReadCount = 0

  init(accessibilityTrusted: Bool, screenCaptureTrusted: Bool) {
    self.accessibilityTrusted = accessibilityTrusted
    self.screenCaptureTrusted = screenCaptureTrusted
  }

  var isAccessibilityTrusted: Bool {
    accessibilityReadCount += 1
    let value = accessibilityTrusted
    onAccessibilityRead?()
    return value
  }

  var isScreenCaptureTrusted: Bool {
    screenCaptureTrusted
  }

  func requestAccessibilityIfNeeded(prompt _: Bool) -> Bool {
    accessibilityTrusted
  }
}
