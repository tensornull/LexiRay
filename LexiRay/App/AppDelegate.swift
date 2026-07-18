import AppKit
import Darwin

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_: Notification) {
    if AppRuntime.isRunningLoginItemSystemProbe {
      runLoginItemSystemProbe()
    }

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

  private func runLoginItemSystemProbe() -> Never {
    guard let profile = AppRuntime.acceptanceProfile else {
      FileHandle.standardError.write(Data("Login Item system probe requires the acceptance profile.\n".utf8))
      Darwin.exit(78)
    }
    guard AppRuntime.isCanonicalInstalledApplication() else {
      FileHandle.standardError.write(
        Data("Login Item system probe requires /Applications/LexiRay.app.\n".utf8)
      )
      Darwin.exit(78)
    }

    let result = LoginItemSystemProbe.run(service: SystemLoginItemService())
    do {
      try LoginItemSystemProbe.write(result, to: profile.loginItemSystemProbeURL)
    } catch {
      FileHandle.standardError.write(Data("Could not write Login Item probe evidence: \(error)\n".utf8))
      Darwin.exit(1)
    }

    switch result.outcome {
    case .passed:
      Darwin.exit(0)
    case .blocked:
      Darwin.exit(75)
    case .failed:
      Darwin.exit(1)
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
