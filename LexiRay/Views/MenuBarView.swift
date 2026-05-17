import AppKit
import SwiftUI

struct MenuBarView: View {
  @ObservedObject var controller: LexiRayController
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button {
      controller.translateCurrentSelection()
    } label: {
      Label("Translate Selection", systemImage: "text.magnifyingglass")
    }
    .keyboardShortcut("d", modifiers: [.command, .option])

    Button {
      openWindow(id: "main")
      NSApp.activate(ignoringOtherApps: true)
    } label: {
      Label("Open LexiRay", systemImage: "macwindow")
    }

    SettingsLink {
      Label("Settings", systemImage: "gearshape")
    }

    Divider()

    Button {
      NSApp.terminate(nil)
    } label: {
      Label("Quit LexiRay", systemImage: "power")
    }
  }
}
