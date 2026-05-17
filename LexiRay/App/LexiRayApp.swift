import SwiftUI

@main
struct LexiRayApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var controller = LexiRayController.shared

  var body: some Scene {
    WindowGroup("LexiRay", id: "main") {
      MainView(controller: controller)
        .frame(minWidth: 760, minHeight: 500)
    }
    .defaultSize(width: 820, height: 560)

    Settings {
      SettingsView(settings: controller.settings)
        .frame(width: 520)
    }

    MenuBarExtra("LexiRay", systemImage: "text.magnifyingglass") {
      MenuBarView(controller: controller)
    }
    .menuBarExtraStyle(.menu)
  }
}
