import AppKit

@MainActor
protocol OCRRegionSelecting: AnyObject {
  func beginSelection(onComplete: @escaping (CGRect?) -> Void)
  func close()
}

@MainActor
final class OCRSelectionOverlayController: OCRRegionSelecting {
  private var panels: [OCRSelectionPanel] = []
  private var escapeMonitor: Any?
  private var completion: ((CGRect?) -> Void)?
  private var didComplete = false

  func beginSelection(onComplete: @escaping (CGRect?) -> Void) {
    close()

    completion = onComplete
    didComplete = false

    // One borderless overlay per physical screen. A single window spanning the
    // union of all screens only renders on the main display when "Displays have
    // separate Spaces" is on (the macOS default), so the secondary screen never
    // gets a dim layer or crosshair and cannot be selected. Per-screen panels
    // each render on their own display; cross-screen drags still work because
    // AppKit keeps delivering dragged/up events to the view that received the
    // mouseDown, even after the cursor leaves that window.
    panels = NSScreen.screens.map { screen in
      let panel = OCRSelectionPanel(
        contentRect: screen.frame,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
      )
      let selectionView = OCRSelectionView(
        frame: NSRect(origin: .zero, size: screen.frame.size),
        screen: screen
      )
      selectionView.onComplete = { [weak self] rect in
        self?.complete(rect)
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
      // A borderless clear panel ordered front from a hotkey callout may never
      // get a display pass, so its layer tree stays unattached and the overlay
      // is invisible until the first drag; force one so dim and prompt show now.
      panel.display()
      return panel
    }

    // Make the panel under the cursor key so it reliably receives the first
    // mouseDown and owns the drag.
    let mouse = NSEvent.mouseLocation
    let keyPanel = panels.first { $0.frame.contains(mouse) } ?? panels.first
    keyPanel?.makeKey()
    NSCursor.crosshair.set()

    escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      if event.keyCode == 53 {
        self?.complete(nil)
        return nil
      }
      return event
    }
  }

  func close() {
    if let escapeMonitor {
      NSEvent.removeMonitor(escapeMonitor)
      self.escapeMonitor = nil
    }
    panels.forEach { $0.orderOut(nil) }
    panels = []
    completion = nil
    didComplete = false
    NSCursor.arrow.set()
  }

  /// Reports the selected global-screen rect (or nil for cancel) exactly once,
  /// then tears down every overlay. Drags started on any screen funnel here.
  private func complete(_ rect: CGRect?) {
    guard !didComplete else {
      return
    }

    didComplete = true
    let completion = completion
    close()
    completion?(rect)
  }
}

private final class OCRSelectionPanel: NSPanel {
  override var canBecomeKey: Bool {
    true
  }
}

private final class OCRSelectionView: NSView {
  var onComplete: ((CGRect?) -> Void)?

  /// The screen this overlay covers. All selection math is done in global
  /// screen coordinates and converted to this view's local space only for
  /// drawing, so a selection that spans displays renders continuously.
  private let screen: NSScreen
  private var startPoint: CGPoint?
  private var currentPoint: CGPoint?
  private var didComplete = false

  private static let sizeLabelSize = CGSize(width: 140, height: 16)

  private let dimLayer = CAShapeLayer()
  private let borderLayer = CAShapeLayer()
  private let sizeLabelLayer = CATextLayer()
  private let promptLayer = CALayer()

  init(frame frameRect: NSRect, screen: NSScreen) {
    self.screen = screen
    super.init(frame: frameRect)
    wantsLayer = true
    layerContentsRedrawPolicy = .never
    setUpLayers()
  }

  /// Layers are mutated per mouse event instead of redrawing the backing store;
  /// compositing happens in the render server so dragging stays smooth on
  /// Retina and across displays.
  private func setUpLayers() {
    guard let layer else {
      return
    }

    dimLayer.fillRule = .evenOdd
    dimLayer.fillColor = NSColor.black.withAlphaComponent(0.28).cgColor
    dimLayer.path = CGPath(rect: bounds, transform: nil)

    borderLayer.fillColor = nil
    borderLayer.lineWidth = 2
    borderLayer.isHidden = true

    sizeLabelLayer.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    sizeLabelLayer.fontSize = 12
    sizeLabelLayer.foregroundColor = NSColor.white.cgColor
    sizeLabelLayer.alignmentMode = .left
    sizeLabelLayer.frame = CGRect(origin: .zero, size: Self.sizeLabelSize)
    sizeLabelLayer.isHidden = true

    setUpPromptLayer()

    layer.addSublayer(dimLayer)
    layer.addSublayer(borderLayer)
    layer.addSublayer(sizeLabelLayer)
    layer.addSublayer(promptLayer)
  }

  /// The prompt uses pre-rendered image contents instead of CATextLayer:
  /// text-layer rasterization is lazy and can miss the commit that first
  /// shows this panel from a hotkey callout, leaving the prompt invisible.
  private func setUpPromptLayer() {
    let text = NSAttributedString(
      string: "Drag to select OCR region",
      attributes: [
        .font: NSFont.systemFont(ofSize: 18, weight: .medium),
        .foregroundColor: NSColor.white
      ]
    )
    let size = text.size()
    let scale = screen.backingScaleFactor
    let width = Int((size.width * scale).rounded(.up))
    let height = Int((size.height * scale).rounded(.up))
    guard width > 0, height > 0,
          let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else {
      return
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    context.scaleBy(x: scale, y: scale)
    text.draw(at: .zero)
    NSGraphicsContext.restoreGraphicsState()

    promptLayer.contents = context.makeImage()
    // Center the prompt on this screen, and only show it on the screen holding
    // the cursor so the other displays stay quietly dimmed.
    promptLayer.frame = CGRect(
      x: bounds.midX - size.width / 2,
      y: bounds.midY - size.height / 2,
      width: size.width,
      height: size.height
    )
    promptLayer.isHidden = !NSMouseInRect(NSEvent.mouseLocation, screen.frame, false)
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
    updateContentsScale()
    let appearance = window?.effectiveAppearance ?? NSApp.effectiveAppearance
    appearance.performAsCurrentDrawingAppearance {
      borderLayer.strokeColor = NSColor.controlAccentColor.cgColor
    }
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    updateContentsScale()
  }

  private func updateContentsScale() {
    sizeLabelLayer.contentsScale = window?.backingScaleFactor ?? screen.backingScaleFactor
  }

  override func mouseDown(with event: NSEvent) {
    let point = screenPoint(from: event)
    startPoint = point
    currentPoint = point
    updateSelectionLayers()
  }

  override func mouseDragged(with event: NSEvent) {
    currentPoint = screenPoint(from: event)
    updateSelectionLayers()
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

  /// Selection in global screen coordinates — fed straight to SCScreenshotManager
  /// capture, which expects global AppKit coordinates.
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

  /// The selection in this view's local space (not clipped). Portions that fall
  /// on another display land off-bounds and the window clips them, so the cut-out
  /// and border stay continuous across screens with no seam line at the edge.
  private var localSelectionRect: CGRect? {
    selectedScreenRect?.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
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

  private func updateSelectionLayers() {
    promptLayer.isHidden = true

    guard let rect = localSelectionRect, let selectedScreenRect, let currentPoint else {
      return
    }

    CATransaction.begin()
    CATransaction.setDisableActions(true)

    let dimPath = CGMutablePath()
    dimPath.addRect(bounds)
    dimPath.addRect(rect)
    dimLayer.path = dimPath

    borderLayer.path = CGPath(rect: rect, transform: nil)
    borderLayer.isHidden = false

    // Show the full selection size, but only on the screen holding the active
    // corner so a cross-screen drag doesn't print the dimensions twice.
    if NSMouseInRect(currentPoint, screen.frame, false) {
      sizeLabelLayer.string = "\(Int(selectedScreenRect.width)) x \(Int(selectedScreenRect.height))"
      sizeLabelLayer.frame = CGRect(
        origin: CGPoint(x: rect.minX + 8, y: rect.maxY + 8),
        size: Self.sizeLabelSize
      )
      sizeLabelLayer.isHidden = false
    } else {
      sizeLabelLayer.isHidden = true
    }

    CATransaction.commit()
  }
}
