import SwiftUI

@main
struct LexiRayApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var controller = LexiRayController.shared
  @StateObject private var settings = LexiRayController.shared.settings

  var body: some Scene {
    Window("LexiRay", id: "main") {
      MainView(controller: controller)
        .frame(minWidth: 760, minHeight: 500)
        .background {
          WindowReportingView { window in
            AppWindowPresenter.registerMainWindow(window)
          }
        }
    }
    .defaultSize(width: 820, height: 560)
    .defaultLaunchBehavior(
      AppRuntime.shouldPresentMainWindowAtLaunch() ? .presented : .suppressed
    )

    MenuBarExtra(isInserted: showsMenuBarIcon) {
      MenuBarView(controller: controller)
    } label: {
      LexiRayMenuBarLabel()
    }
    .menuBarExtraStyle(.menu)
  }

  private var showsMenuBarIcon: Binding<Bool> {
    Binding(
      get: { settings.showsMenuBarIcon },
      set: { newValue in
        guard settings.showsMenuBarIcon != newValue else {
          return
        }
        settings.showsMenuBarIcon = newValue
      }
    )
  }
}

private struct LexiRayMenuBarLabel: View {
  @Environment(\.openWindow) private var openWindow
  @State private var didRequestAcceptanceWindow = false

  var body: some View {
    Image(systemName: "translate")
      .accessibilityLabel("LexiRay")
      .onAppear {
        openAcceptanceWindowIfNeeded()
      }
  }

  private func openAcceptanceWindowIfNeeded() {
    guard !didRequestAcceptanceWindow,
          AppRuntime.shouldPresentMainWindowAtLaunch()
    else {
      return
    }

    didRequestAcceptanceWindow = true
    AppWindowPresenter.requestMainWindowPresentation(cancelsOnResign: false)
    openWindow(id: "main")
    AppWindowPresenter.presentMainWindowIfAvailable()
  }
}
