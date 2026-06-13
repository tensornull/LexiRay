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
    // A borderless clear panel ordered front from a hotkey callout may never
    // get a display pass, so its layer tree stays unattached and the overlay
    // is invisible until the first drag; force one so dim and prompt show now.
    panel.display()

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

  private static let sizeLabelSize = CGSize(width: 140, height: 16)

  private let dimLayer = CAShapeLayer()
  private let borderLayer = CAShapeLayer()
  private let sizeLabelLayer = CATextLayer()
  private let promptLayer = CALayer()

  init(frame frameRect: NSRect, screenFrame: NSRect) {
    self.screenFrame = screenFrame
    super.init(frame: frameRect)
    wantsLayer = true
    layerContentsRedrawPolicy = .never
    setUpLayers()
  }

  /// Layers are mutated per mouse event instead of redrawing the multi-screen
  /// backing store; compositing happens in the render server so dragging stays
  /// smooth on Retina and multi-display unions.
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
    let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
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
    // Center on the screen holding the cursor: the view spans the union of
    // all screens, so bounds.mid* can land far off-center on any one display.
    let mouse = NSEvent.mouseLocation
    let target = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.screens.first
    let center = target.map { screen in
      CGPoint(x: screen.frame.midX - screenFrame.minX, y: screen.frame.midY - screenFrame.minY)
    } ?? CGPoint(x: bounds.midX, y: bounds.midY)
    promptLayer.frame = CGRect(
      x: center.x - size.width / 2,
      y: center.y - size.height / 2,
      width: size.width,
      height: size.height
    )
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

  /// The panel spans the union of all screens, so use the largest backing
  /// scale; the size label's CATextLayer otherwise rasterizes at 1x and looks
  /// blurry on Retina. The prompt layer carries pre-rendered image contents
  /// and does not depend on contentsScale.
  private func updateContentsScale() {
    let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
    sizeLabelLayer.contentsScale = scale
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

  private func updateSelectionLayers() {
    guard let rect = selectionRect else {
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

    sizeLabelLayer.string = "\(Int(rect.width)) x \(Int(rect.height))"
    sizeLabelLayer.frame = CGRect(
      origin: CGPoint(x: rect.minX + 8, y: rect.maxY + 8),
      size: Self.sizeLabelSize
    )
    sizeLabelLayer.isHidden = false

    promptLayer.isHidden = true

    CATransaction.commit()
  }
}
