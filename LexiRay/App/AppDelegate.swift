import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_: Notification) {
    installApplicationIcon()
    AppWindowPresenter.showDockAndActivate()

    guard !AppRuntime.isRunningTests else {
      return
    }

    AppWindowPresenter.startDockVisibilityObservation(settings: LexiRayController.shared.settings)
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

  private func installApplicationIcon() {
    guard
      let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
      let icon = NSImage(contentsOf: iconURL)
    else {
      return
    }

    NSApplication.shared.applicationIconImage = icon
  }
}
