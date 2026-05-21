import AppKit

@MainActor
enum AppWindowPresenter {
  private static var windowCloseObserver: NSObjectProtocol?

  static func bringMainWindowToFrontSoon() {
    bringToFrontSoon(.main)
  }

  static func bringSettingsWindowToFrontSoon() {
    bringMainWindowToFrontSoon()
  }

  static func startDockVisibilityObservation(settings: SettingsStore) {
    guard windowCloseObserver == nil else {
      return
    }

    windowCloseObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification,
      object: nil,
      queue: .main
    ) { _ in
      Task { @MainActor in
        hideDockIfNoRegularWindowsSoon(showsMenuBarIcon: settings.showsMenuBarIcon)
      }
    }
  }

  static func showDockAndActivate() {
    NSApp.setActivationPolicy(.regular)
    NSApp.unhide(nil)
    NSApp.activate()
  }

  static func hideDockIfNoRegularWindowsSoon(showsMenuBarIcon: Bool) {
    scheduleDockVisibilityUpdate(after: 0.05, showsMenuBarIcon: showsMenuBarIcon)
    scheduleDockVisibilityUpdate(after: 0.2, showsMenuBarIcon: showsMenuBarIcon)
  }

  static func activationPolicy(hasVisibleRegularWindows: Bool) -> NSApplication.ActivationPolicy {
    activationPolicy(hasVisibleRegularWindows: hasVisibleRegularWindows, showsMenuBarIcon: true)
  }

  static func activationPolicy(
    hasVisibleRegularWindows: Bool,
    showsMenuBarIcon: Bool
  ) -> NSApplication.ActivationPolicy {
    hasVisibleRegularWindows || !showsMenuBarIcon ? .regular : .accessory
  }

  static func refreshDockVisibilitySoon(showsMenuBarIcon: Bool) {
    hideDockIfNoRegularWindowsSoon(showsMenuBarIcon: showsMenuBarIcon)
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
    }

    candidate?.deminiaturize(nil)
    candidate?.makeKeyAndOrderFront(nil)
    candidate?.orderFrontRegardless()
  }

  private static func scheduleDockVisibilityUpdate(after delay: TimeInterval, showsMenuBarIcon: Bool) {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
      Task { @MainActor in
        updateDockVisibility(showsMenuBarIcon: showsMenuBarIcon)
      }
    }
  }

  private static func updateDockVisibility(showsMenuBarIcon: Bool) {
    NSApp.setActivationPolicy(
      activationPolicy(
        hasVisibleRegularWindows: hasVisibleRegularWindows(),
        showsMenuBarIcon: showsMenuBarIcon
      )
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
    return matches(identifier: identifier, title: title, kind: kind)
  }

  static func matchingWindowIndex(in windows: [WindowSnapshot], kind: WindowKind) -> Int? {
    windows.firstIndex { window in
      window.isVisible && matches(identifier: window.identifier, title: window.title, kind: kind)
    }
  }

  static func matches(identifier: String, title: String, kind: WindowKind) -> Bool {
    switch kind {
    case .main:
      return identifier == "main" || title == AppConstants.appName
    }
  }

  struct WindowSnapshot {
    let isVisible: Bool
    let identifier: String
    let title: String
  }

  enum WindowKind {
    case main
  }
}
