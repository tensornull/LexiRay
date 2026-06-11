import AppKit

@MainActor
enum AppWindowPresenter {
  private static var windowCloseObserver: NSObjectProtocol?
  private static var appResignObserver: NSObjectProtocol?
  private weak static var mainWindow: NSWindow?
  private static var mainWindowObservers: [NSObjectProtocol] = []
  private static var closingMainWindowIDs = Set<ObjectIdentifier>()
  private static var pendingMainWindowPresentation: PresentationRequest?

  static func bringMainWindowToFrontSoon() {
    requestMainWindowPresentation()
    presentMainWindowIfAvailable()
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
    if NSApp.activationPolicy() != .regular {
      NSApp.setActivationPolicy(.regular)
    }
    NSApp.unhide(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  static func hideDockIfNoRegularWindowsSoon(showsMenuBarIcon: Bool) {
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

  static func registerMainWindow(_ window: NSWindow) {
    window.identifier = NSUserInterfaceItemIdentifier("main")
    closingMainWindowIDs.remove(ObjectIdentifier(window))
    guard mainWindow !== window else {
      presentMainWindowIfAvailable()
      return
    }

    removeMainWindowObservers()
    mainWindow = window
    observeMainWindow(window)
    presentMainWindowIfAvailable()
  }

  static func requestMainWindowPresentation() {
    startPresentationCancellationObservation()
    pendingMainWindowPresentation = PresentationRequest(deadline: Date().addingTimeInterval(5))
    showDockAndActivate()
  }

  static var isMainWindowPresentationPending: Bool {
    pendingMainWindowPresentation != nil
  }

  static func cancelPendingMainWindowPresentation() {
    pendingMainWindowPresentation = nil
  }

  @discardableResult
  static func presentMainWindowIfAvailable() -> Bool {
    guard pendingMainWindowPresentation != nil else {
      return false
    }

    guard let window = mainWindowCandidate() else {
      schedulePendingPresentationRetry()
      return false
    }

    bringToFront(window)
    guard presentationSucceeded(window) else {
      schedulePendingPresentationRetry()
      return false
    }

    pendingMainWindowPresentation = nil
    return true
  }

  private static func bringToFront(_ window: NSWindow) {
    window.deminiaturize(nil)
    window.makeKeyAndOrderFront(nil)
  }

  private static func observeMainWindow(_ window: NSWindow) {
    let notificationCenter = NotificationCenter.default
    let windowID = ObjectIdentifier(window)
    let retryNotifications: [NSNotification.Name] = [
      NSWindow.didBecomeKeyNotification,
      NSWindow.didBecomeMainNotification,
      NSWindow.didChangeOcclusionStateNotification,
      NSWindow.didDeminiaturizeNotification
    ]

    mainWindowObservers = retryNotifications.map { notificationName in
      notificationCenter.addObserver(
        forName: notificationName,
        object: window,
        queue: .main
      ) { _ in
        Task { @MainActor in
          presentMainWindowIfAvailable()
        }
      }
    }

    mainWindowObservers.append(
      notificationCenter.addObserver(
        forName: NSWindow.didResignKeyNotification,
        object: window,
        queue: .main
      ) { _ in
        Task { @MainActor in
          cancelPendingMainWindowPresentation()
        }
      }
    )

    mainWindowObservers.append(
      notificationCenter.addObserver(
        forName: NSWindow.willCloseNotification,
        object: window,
        queue: .main
      ) { _ in
        Task { @MainActor in
          handleMainWindowWillClose(windowID: windowID)
        }
      }
    )
  }

  private static func startPresentationCancellationObservation() {
    guard appResignObserver == nil else {
      return
    }

    appResignObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didResignActiveNotification,
      object: NSApp,
      queue: .main
    ) { _ in
      Task { @MainActor in
        cancelPendingMainWindowPresentation()
      }
    }
  }

  private static func removeMainWindowObservers() {
    for observer in mainWindowObservers {
      NotificationCenter.default.removeObserver(observer)
    }
    mainWindowObservers.removeAll()
  }

  private static func handleMainWindowWillClose(windowID: ObjectIdentifier) {
    closingMainWindowIDs.insert(windowID)
    if let window = mainWindow, ObjectIdentifier(window) == windowID {
      mainWindow = nil
    }

    schedulePendingPresentationRetry()
  }

  private static func mainWindowCandidate() -> NSWindow? {
    if let mainWindow, isPresentationCandidate(mainWindow) {
      return mainWindow
    }

    return NSApp.windows.first { window in
      isPresentationCandidate(window)
    }
  }

  private static func isPresentationCandidate(_ window: NSWindow) -> Bool {
    isPresentationCandidate(
      identifier: window.identifier?.rawValue ?? "",
      title: window.title,
      canBecomeKey: window.canBecomeKey,
      isNormalWindowLevel: window.level == .normal,
      isClosing: closingMainWindowIDs.contains(ObjectIdentifier(window)),
      kind: .main
    )
  }

  private static func presentationSucceeded(_ window: NSWindow) -> Bool {
    presentationSucceeded(
      WindowSnapshot(
        isVisible: window.isVisible,
        identifier: window.identifier?.rawValue ?? "",
        title: window.title,
        isMiniaturized: window.isMiniaturized,
        canBecomeKey: window.canBecomeKey,
        isNormalWindowLevel: window.level == .normal,
        isClosing: closingMainWindowIDs.contains(ObjectIdentifier(window))
      ),
      kind: .main
    )
  }

  private static func schedulePendingPresentationRetry() {
    guard var request = pendingMainWindowPresentation, !request.retryScheduled else {
      return
    }

    guard Date() < request.deadline else {
      cancelPendingMainWindowPresentation()
      return
    }

    request.retryScheduled = true
    pendingMainWindowPresentation = request
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
      Task { @MainActor in
        pendingMainWindowPresentation?.retryScheduled = false
        presentMainWindowIfAvailable()
      }
    }
  }

  private static func scheduleDockVisibilityUpdate(after delay: TimeInterval, showsMenuBarIcon: Bool) {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
      Task { @MainActor in
        updateDockVisibility(showsMenuBarIcon: showsMenuBarIcon)
      }
    }
  }

  private static func updateDockVisibility(showsMenuBarIcon: Bool) {
    let hasVisibleRegularWindows = hasVisibleRegularWindows()
    let desiredPolicy = activationPolicy(
      hasVisibleRegularWindows: hasVisibleRegularWindows,
      showsMenuBarIcon: showsMenuBarIcon
    )
    if NSApp.activationPolicy() != desiredPolicy {
      NSApp.setActivationPolicy(desiredPolicy)
    }

    if shouldHideApplication(
      desiredPolicy: desiredPolicy,
      hasVisibleAppSurface: hasVisibleAppSurfaces()
    ) {
      NSApp.hide(nil)
    }
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

  private static func hasVisibleAppSurfaces() -> Bool {
    let windows = NSApp.windows.map { window in
      WindowSnapshot(
        isVisible: window.isVisible,
        identifier: window.identifier?.rawValue ?? "",
        title: window.title,
        isMiniaturized: window.isMiniaturized,
        canBecomeKey: window.canBecomeKey,
        isNormalWindowLevel: window.level == .normal,
        isClosing: closingMainWindowIDs.contains(ObjectIdentifier(window))
      )
    }
    return hasVisibleAppSurface(in: windows)
  }

  static func hasVisibleAppSurface(in windows: [WindowSnapshot]) -> Bool {
    windows.contains { window in
      window.isVisible
        && !window.isMiniaturized
        && !window.isClosing
    }
  }

  static func shouldHideApplication(
    desiredPolicy: NSApplication.ActivationPolicy,
    hasVisibleAppSurface: Bool
  ) -> Bool {
    desiredPolicy == .accessory && !hasVisibleAppSurface
  }

  private static func matches(_ window: NSWindow, kind: WindowKind) -> Bool {
    let identifier = window.identifier?.rawValue ?? ""
    let title = window.title
    return matches(identifier: identifier, title: title, kind: kind)
  }

  static func matchingWindowIndex(in windows: [WindowSnapshot], kind: WindowKind) -> Int? {
    presentationCandidateIndex(in: windows, kind: kind)
  }

  static func presentationCandidateIndex(in windows: [WindowSnapshot], kind: WindowKind) -> Int? {
    windows.firstIndex { window in
      isPresentationCandidate(
        identifier: window.identifier,
        title: window.title,
        canBecomeKey: window.canBecomeKey,
        isNormalWindowLevel: window.isNormalWindowLevel,
        isClosing: window.isClosing,
        kind: kind
      )
    }
  }

  static func presentationSucceeded(_ window: WindowSnapshot, kind: WindowKind) -> Bool {
    matches(identifier: window.identifier, title: window.title, kind: kind)
      && window.isVisible
      && !window.isMiniaturized
      && window.canBecomeKey
      && window.isNormalWindowLevel
      && !window.isClosing
  }

  private static func isPresentationCandidate(
    identifier: String,
    title: String,
    canBecomeKey: Bool,
    isNormalWindowLevel: Bool,
    isClosing: Bool,
    kind: WindowKind
  ) -> Bool {
    matches(identifier: identifier, title: title, kind: kind)
      && canBecomeKey
      && isNormalWindowLevel
      && !isClosing
  }

  static func matches(identifier: String, title: String, kind: WindowKind) -> Bool {
    switch kind {
    case .main:
      identifier == "main" || title == AppConstants.appName
    }
  }

  struct WindowSnapshot {
    let isVisible: Bool
    let identifier: String
    let title: String
    let isMiniaturized: Bool
    let canBecomeKey: Bool
    let isNormalWindowLevel: Bool
    let isClosing: Bool

    init(
      isVisible: Bool,
      identifier: String,
      title: String,
      isMiniaturized: Bool = false,
      canBecomeKey: Bool = true,
      isNormalWindowLevel: Bool = true,
      isClosing: Bool = false
    ) {
      self.isVisible = isVisible
      self.identifier = identifier
      self.title = title
      self.isMiniaturized = isMiniaturized
      self.canBecomeKey = canBecomeKey
      self.isNormalWindowLevel = isNormalWindowLevel
      self.isClosing = isClosing
    }
  }

  enum WindowKind: Hashable {
    case main
  }

  private struct PresentationRequest {
    var deadline: Date
    var retryScheduled = false
  }
}
