import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_: Notification) {
    applyAcceptanceAppearance()
    installApplicationIcon()
    AppWindowPresenter.applyActivationPolicy(
      showsMenuBarIcon: LexiRayController.shared.settings.showsMenuBarIcon
    )

    guard !AppRuntime.isRunningTests else {
      return
    }

    AppWindowPresenter.startDockVisibilityObservation(settings: LexiRayController.shared.settings)
    LexiRayController.shared.start()
    if AppRuntime.shouldPresentMainWindowAtLaunch() {
      AppWindowPresenter.bringMainWindowToFrontSoon(cancelsOnResign: false)
    }
  }

  private func applyAcceptanceAppearance() {
    switch AppRuntime.acceptanceAppearance {
    case "dark":
      NSApp.appearance = NSAppearance(named: .darkAqua)
    case "light":
      NSApp.appearance = NSAppearance(named: .aqua)
    default:
      break
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
    false
  }

  func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
    AppWindowPresenter.activateApp()
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
