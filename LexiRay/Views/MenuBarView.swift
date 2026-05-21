import AppKit
import SwiftUI

struct MenuBarView: View {
  @ObservedObject var controller: LexiRayController
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button {
      controller.translateCurrentSelection()
    } label: {
      Label("Translate Selection", systemImage: "text.viewfinder")
    }
    .keyboardShortcut("d", modifiers: [.command, .option])

    Button {
      controller.translateOCRRegion()
    } label: {
      Label("OCR Region", systemImage: "viewfinder")
    }
    .keyboardShortcut("o", modifiers: [.command, .option])

    Button {
      openMainWindow()
    } label: {
      Label("Open LexiRay", systemImage: "macwindow")
    }

    Button {
      openSettingsWindow()
    } label: {
      Label("Settings", systemImage: "gearshape")
    }

    Divider()

    Button {
      NSApp.terminate(nil)
    } label: {
      Label("Quit LexiRay", systemImage: "power")
    }
  }

  private func openMainWindow() {
    controller.selectDashboard()
    openWindow(id: "main")
    AppWindowPresenter.bringMainWindowToFrontSoon()
  }

  private func openSettingsWindow() {
    controller.selectSettings()
    openWindow(id: "main")
    AppWindowPresenter.bringMainWindowToFrontSoon()
  }
}
