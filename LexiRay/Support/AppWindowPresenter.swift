import AppKit

@MainActor
enum AppWindowPresenter {
  private static var windowCloseObserver: NSObjectProtocol?

  static func bringMainWindowToFrontSoon() {
    bringToFrontSoon(.main)
  }

  static func bringSettingsWindowToFrontSoon() {
    bringToFrontSoon(.settings)
  }

  static func startDockVisibilityObservation() {
    guard windowCloseObserver == nil else {
      return
    }

    windowCloseObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification,
      object: nil,
      queue: .main
    ) { _ in
      Task { @MainActor in
        hideDockIfNoRegularWindowsSoon()
      }
    }
  }

  static func showDockAndActivate() {
    NSApp.setActivationPolicy(.regular)
    NSApp.unhide(nil)
    NSApp.activate()
  }

  static func hideDockIfNoRegularWindowsSoon() {
    scheduleDockVisibilityUpdate(after: 0.05)
    scheduleDockVisibilityUpdate(after: 0.2)
  }

  static func activationPolicy(hasVisibleRegularWindows: Bool) -> NSApplication.ActivationPolicy {
    hasVisibleRegularWindows ? .regular : .accessory
  }

  private static func bringToFrontSoon(_ kind: WindowKind) {
    bringToFront(kind)
    scheduleBringToFront(kind, after: 0.05)
    scheduleBringToFront(kind, after: 0.2)
  }

  private static func scheduleBringToFront(_ kind: WindowKind, after delay: TimeInterval) {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
      Task { @MainActor in
        bringToFront(kind)
      }
    }
  }

  private static func bringToFront(_ kind: WindowKind) {
    showDockAndActivate()

    let candidate = NSApp.windows.first { window in
      window.isVisible && matches(window, kind: kind)
    } ?? NSApp.keyWindow ?? NSApp.windows.first { window in
      window.isVisible && window.canBecomeKey
    }

    candidate?.deminiaturize(nil)
    candidate?.makeKeyAndOrderFront(nil)
    candidate?.orderFrontRegardless()
  }

  private static func scheduleDockVisibilityUpdate(after delay: TimeInterval) {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
      Task { @MainActor in
        updateDockVisibility()
      }
    }
  }

  private static func updateDockVisibility() {
    NSApp.setActivationPolicy(
      activationPolicy(hasVisibleRegularWindows: hasVisibleRegularWindows())
    )
  }

  private static func hasVisibleRegularWindows() -> Bool {
    NSApp.windows.contains { window in
      isVisibleRegularWindow(window)
    }
  }

  private static func isVisibleRegularWindow(_ window: NSWindow) -> Bool {
    window.isVisible
      && !window.isMiniaturized
      && window.level == .normal
      && window.canBecomeKey
  }

  private static func matches(_ window: NSWindow, kind: WindowKind) -> Bool {
    let identifier = window.identifier?.rawValue ?? ""
    let title = window.title

    switch kind {
    case .main:
      return identifier == "main" || title == AppConstants.appName
    case .settings:
      return identifier.localizedCaseInsensitiveContains("settings")
        || title.localizedCaseInsensitiveContains("settings")
        || title.localizedCaseInsensitiveContains("preferences")
    }
  }

  private enum WindowKind {
    case main
    case settings
  }
}
