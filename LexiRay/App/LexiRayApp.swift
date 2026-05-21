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
    }
    .defaultSize(width: 820, height: 560)
    .defaultLaunchBehavior(.presented)

    MenuBarExtra("LexiRay", image: "MenuBarIcon", isInserted: showsMenuBarIcon) {
      MenuBarView(controller: controller)
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
