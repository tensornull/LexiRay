import AppKit
import Combine
import Foundation

struct PermissionStatus: Equatable {
  let isAccessibilityTrusted: Bool
  let isScreenCaptureTrusted: Bool
}

/// Keeps `PermissionStatus` fresh without tight polling: the undocumented
/// `com.apple.accessibility.api` distributed notification and app activation
/// drive immediate refreshes, while a slow poll covers Screen Recording (which
/// has no change notification) and any missed events.
@MainActor
final class PermissionStatusMonitor: NSObject, ObservableObject {
  @Published private(set) var status: PermissionStatus

  /// Fires after every refresh tick, even when `status` did not change, so
  /// observers can piggyback their own re-checks (app identity, login item).
  let refreshEvents = PassthroughSubject<Void, Never>()

  private let permissionChecker: PermissionChecking
  private let distributedCenter: NotificationCenter
  private let applicationCenter: NotificationCenter
  private let fallbackPollInterval: Duration
  private let notificationRecheckDelay: Duration
  private var pollTask: Task<Void, Never>?
  private var recheckTask: Task<Void, Never>?
  private var isStarted = false

  private static let accessibilityAPINotification = Notification.Name("com.apple.accessibility.api")

  init(
    permissionChecker: PermissionChecking = SystemPermissionChecker(),
    distributedCenter: NotificationCenter = DistributedNotificationCenter.default(),
    applicationCenter: NotificationCenter = .default,
    fallbackPollInterval: Duration = .seconds(15),
    notificationRecheckDelay: Duration = .seconds(1)
  ) {
    self.permissionChecker = permissionChecker
    self.distributedCenter = distributedCenter
    self.applicationCenter = applicationCenter
    self.fallbackPollInterval = fallbackPollInterval
    self.notificationRecheckDelay = notificationRecheckDelay
    status = PermissionStatus(
      isAccessibilityTrusted: permissionChecker.isAccessibilityTrusted,
      isScreenCaptureTrusted: permissionChecker.isScreenCaptureTrusted
    )
    super.init()
  }

  func start() {
    guard !isStarted else {
      return
    }
    isStarted = true

    if let distributed = distributedCenter as? DistributedNotificationCenter {
      // Without .deliverImmediately the notification coalesces until the app
      // activates, losing the live update while System Settings is frontmost.
      distributed.addObserver(
        self,
        selector: #selector(accessibilityPermissionsDidChange),
        name: Self.accessibilityAPINotification,
        object: nil,
        suspensionBehavior: .deliverImmediately
      )
    } else {
      distributedCenter.addObserver(
        self,
        selector: #selector(accessibilityPermissionsDidChange),
        name: Self.accessibilityAPINotification,
        object: nil
      )
    }

    applicationCenter.addObserver(
      self,
      selector: #selector(applicationDidBecomeActive),
      name: NSApplication.didBecomeActiveNotification,
      object: nil
    )

    refreshNow()
    startFallbackPolling()
    AppLog.app.info("Permission monitor started")
  }

  func stop() {
    guard isStarted else {
      return
    }
    isStarted = false

    distributedCenter.removeObserver(self, name: Self.accessibilityAPINotification, object: nil)
    applicationCenter.removeObserver(self, name: NSApplication.didBecomeActiveNotification, object: nil)
    pollTask?.cancel()
    pollTask = nil
    recheckTask?.cancel()
    recheckTask = nil
  }

  func refreshNow() {
    let currentStatus = PermissionStatus(
      isAccessibilityTrusted: permissionChecker.isAccessibilityTrusted,
      isScreenCaptureTrusted: permissionChecker.isScreenCaptureTrusted
    )
    if status != currentStatus {
      status = currentStatus
    }
    refreshEvents.send()
  }

  @objc private nonisolated func accessibilityPermissionsDidChange() {
    Task { @MainActor [weak self] in
      guard let self else {
        return
      }
      refreshNow()
      // The TCC write can lag what AXIsProcessTrusted() reports at the
      // instant the notification fires, so check once more shortly after.
      scheduleNotificationRecheck()
    }
  }

  @objc private nonisolated func applicationDidBecomeActive() {
    Task { @MainActor [weak self] in
      self?.refreshNow()
    }
  }

  private func scheduleNotificationRecheck() {
    recheckTask?.cancel()
    let delay = notificationRecheckDelay
    recheckTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(for: delay)
      } catch {
        return
      }
      self?.refreshNow()
    }
  }

  private func startFallbackPolling() {
    pollTask?.cancel()
    let interval = fallbackPollInterval
    pollTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: interval)
        } catch {
          return
        }
        guard let self else {
          return
        }
        refreshNow()
      }
    }
  }
}
