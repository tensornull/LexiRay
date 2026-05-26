import AppKit
import SwiftUI

struct WindowReportingView: NSViewRepresentable {
  var onWindowAvailable: (NSWindow) -> Void

  func makeNSView(context _: Context) -> WindowReportingNSView {
    let view = WindowReportingNSView()
    view.onWindowAvailable = onWindowAvailable
    return view
  }

  func updateNSView(_ nsView: WindowReportingNSView, context _: Context) {
    nsView.onWindowAvailable = onWindowAvailable
    nsView.reportWindowIfNeeded()
  }
}

final class WindowReportingNSView: NSView {
  var onWindowAvailable: ((NSWindow) -> Void)?
  private weak var reportedWindow: NSWindow?

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    reportWindowIfNeeded()
  }

  func reportWindowIfNeeded() {
    guard let window, reportedWindow !== window else {
      return
    }

    reportedWindow = window
    onWindowAvailable?(window)
  }
}
