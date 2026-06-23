import AppKit
import SwiftUI

struct MenuBarView: View {
  @ObservedObject var controller: LexiRayController
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    shortcutButton(
      hotKey: controller.settings.translateHotKey,
      action: {
        controller.translateCurrentSelection()
      },
      label: {
        Label("Translate Selection", systemImage: "text.viewfinder")
      }
    )

    shortcutButton(
      hotKey: controller.settings.ocrHotKey,
      action: {
        controller.translateOCRRegion()
      },
      label: {
        Label("OCR Region", systemImage: "viewfinder")
      }
    )

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
    presentMainWindow { controller.selectDashboard() }
  }

  private func openSettingsWindow() {
    presentMainWindow { controller.selectSettings() }
  }

  private func presentMainWindow(selectingSection: () -> Void) {
    selectingSection()
    // Opening a regular window must never resurrect a dismissed floating panel:
    // hide it first, then activate the app and bring the main window forward.
    controller.hideFloatingPanelIfNeeded()
    AppWindowPresenter.requestMainWindowPresentation()
    openWindow(id: "main")
    AppWindowPresenter.presentMainWindowIfAvailable()
  }

  @ViewBuilder
  private func shortcutButton(
    hotKey: HotKeyConfiguration,
    action: @escaping () -> Void,
    @ViewBuilder label: () -> some View
  ) -> some View {
    let button = Button(action: action, label: label)
    if let shortcut = hotKey.menuKeyboardShortcut {
      button.keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
    } else {
      button
    }
  }
}
