import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_: Notification) {
    AppWindowPresenter.showDockAndActivate()

    guard !AppRuntime.isRunningTests else {
      return
    }

    AppWindowPresenter.startDockVisibilityObservation()
    LexiRayController.shared.start()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
    false
  }

  func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
    AppWindowPresenter.showDockAndActivate()
    AppWindowPresenter.bringMainWindowToFrontSoon()
    return true
  }
}
