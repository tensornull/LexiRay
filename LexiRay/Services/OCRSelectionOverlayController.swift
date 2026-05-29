import AppKit

@MainActor
protocol OCRRegionSelecting: AnyObject {
  func beginSelection(onComplete: @escaping (CGRect?) -> Void)
  func close()
}

@MainActor
final class OCRSelectionOverlayController: OCRRegionSelecting {
  private var panel: OCRSelectionPanel?
  private var escapeMonitor: Any?

  func beginSelection(onComplete: @escaping (CGRect?) -> Void) {
    close()

    let screenFrame = NSScreen.screens
      .map(\.frame)
      .reduce(NSRect.null) { partialResult, frame in
        partialResult.union(frame)
      }

    let panel = OCRSelectionPanel(
      contentRect: screenFrame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    let selectionView = OCRSelectionView(frame: NSRect(origin: .zero, size: screenFrame.size), screenFrame: screenFrame)

    selectionView.onComplete = { [weak self] rect in
      self?.close()
      onComplete(rect)
    }

    panel.contentView = selectionView
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.level = .screenSaver
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.ignoresMouseEvents = false
    panel.orderFrontRegardless()
    panel.makeKey()
    NSCursor.crosshair.set()

    escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak selectionView] event in
      if event.keyCode == 53 {
        selectionView?.cancelSelection()
        return nil
      }
      return event
    }

    self.panel = panel
  }

  func close() {
    if let escapeMonitor {
      NSEvent.removeMonitor(escapeMonitor)
      self.escapeMonitor = nil
    }
    panel?.orderOut(nil)
    panel = nil
    NSCursor.arrow.set()
  }
}

private final class OCRSelectionPanel: NSPanel {
  override var canBecomeKey: Bool {
    true
  }
}

private final class OCRSelectionView: NSView {
  var onComplete: ((CGRect?) -> Void)?

  private let screenFrame: NSRect
  private var startPoint: CGPoint?
  private var currentPoint: CGPoint?
  private var didComplete = false

  init(frame frameRect: NSRect, screenFrame: NSRect) {
    self.screenFrame = screenFrame
    super.init(frame: frameRect)
    wantsLayer = true
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    nil
  }

  override var acceptsFirstResponder: Bool {
    true
  }

  override func viewDidMoveToWindow() {
    window?.makeFirstResponder(self)
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    NSColor.black.withAlphaComponent(0.28).setFill()
    bounds.fill()

    guard let selectionRect else {
      drawPrompt()
      return
    }

    NSColor.clear.setFill()
    selectionRect.fill(using: .clear)

    NSColor.controlAccentColor.setStroke()
    let path = NSBezierPath(rect: selectionRect)
    path.lineWidth = 2
    path.stroke()

    drawSizeLabel(for: selectionRect)
  }

  override func mouseDown(with event: NSEvent) {
    let point = screenPoint(from: event)
    startPoint = point
    currentPoint = point
    needsDisplay = true
  }

  override func mouseDragged(with event: NSEvent) {
    currentPoint = screenPoint(from: event)
    needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    currentPoint = screenPoint(from: event)
    guard let rect = selectedScreenRect else {
      complete(nil)
      return
    }
    guard rect.width >= 2 || rect.height >= 2 else {
      complete(nil)
      return
    }

    complete(rect)
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 {
      cancelSelection()
    } else {
      super.keyDown(with: event)
    }
  }

  func cancelSelection() {
    complete(nil)
  }

  private var selectedScreenRect: CGRect? {
    guard let startPoint, let currentPoint else {
      return nil
    }

    return CGRect(
      x: min(startPoint.x, currentPoint.x),
      y: min(startPoint.y, currentPoint.y),
      width: abs(startPoint.x - currentPoint.x),
      height: abs(startPoint.y - currentPoint.y)
    )
  }

  private var selectionRect: CGRect? {
    selectedScreenRect?.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
  }

  private func screenPoint(from event: NSEvent) -> CGPoint {
    window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
  }

  private func complete(_ rect: CGRect?) {
    guard !didComplete else {
      return
    }

    didComplete = true
    let completion = onComplete
    onComplete = nil
    completion?(rect)
  }

  private func drawPrompt() {
    let text = "Drag to select OCR region"
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 18, weight: .medium),
      .foregroundColor: NSColor.white
    ]
    let size = text.size(withAttributes: attributes)
    let origin = CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
    text.draw(at: origin, withAttributes: attributes)
  }

  private func drawSizeLabel(for rect: CGRect) {
    let text = "\(Int(rect.width)) x \(Int(rect.height))"
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
      .foregroundColor: NSColor.white
    ]
    text.draw(at: CGPoint(x: rect.minX + 8, y: rect.maxY + 8), withAttributes: attributes)
  }
}
