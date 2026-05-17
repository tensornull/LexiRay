import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController {
  private weak var controller: LexiRayController?
  private var panel: NSPanel?

  init(controller: LexiRayController) {
    self.controller = controller
  }

  func show() {
    guard let controller else {
      return
    }

    let panel = panel ?? makePanel(controller: controller)
    self.panel = panel

    position(panel)
    panel.orderFrontRegardless()
    NSApp.activate(ignoringOtherApps: true)
    AppLog.panel.info("Floating panel shown")
  }

  func hideIfNeeded() {
    guard controller?.isPanelPinned == false else {
      return
    }
    panel?.orderOut(nil)
  }

  private func makePanel(controller: LexiRayController) -> NSPanel {
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 430, height: 286),
      styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )

    panel.title = "LexiRay"
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isMovableByWindowBackground = true
    panel.hidesOnDeactivate = false
    panel.backgroundColor = .clear
    panel.contentView = NSHostingView(rootView: FloatingPanelView(controller: controller))

    return panel
  }

  private func position(_ panel: NSPanel) {
    let mouseLocation = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
    let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let size = panel.frame.size

    let x = min(max(mouseLocation.x + 14, visibleFrame.minX + 12), visibleFrame.maxX - size.width - 12)
    let y = min(max(mouseLocation.y - size.height - 14, visibleFrame.minY + 12), visibleFrame.maxY - size.height - 12)

    panel.setFrameOrigin(NSPoint(x: x, y: y))
  }
}
