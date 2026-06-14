import AppKit
import QuartzCore
import SwiftUI

@MainActor
protocol FloatingPanelPresenting: AnyObject {
  func show(activating: Bool, repositioning: Bool)
  func refreshContentLayout()
  func hide()
  func hideIfNeeded()
  func updatePinnedState(isPinned: Bool)
  func updateLayout()
}

extension FloatingPanelPresenting {
  func show(activating: Bool) {
    show(activating: activating, repositioning: true)
  }

  func show() {
    show(activating: false, repositioning: true)
  }
}

@MainActor
final class FloatingPanelController: NSObject, FloatingPanelPresenting {
  static var panelStyleMask: NSWindow.StyleMask {
    [.borderless, .nonactivatingPanel, .resizable]
  }

  static let defaultContentWidth: CGFloat = 660
  static let cornerRadius: CGFloat = 22

  static var minimumContentSize: NSSize {
    NSSize(width: 560, height: 200)
  }

  private static let idleMaximumContentWidth: CGFloat = 680
  private static let resizeThreshold: CGFloat = 6

  private weak var controller: LexiRayController?
  private var panel: NSPanel?
  private var globalMouseMonitor: Any?
  private var localMouseMonitor: Any?
  private var localKeyMonitor: Any?
  private var pendingResizeTask: Task<Void, Never>?
  private var isMovingProgrammatically = false
  private var isSizingProgrammatically = false
  private var userContentSizeOverride: NSSize?

  init(controller: LexiRayController) {
    self.controller = controller
    super.init()
  }

  func show(activating: Bool = false, repositioning: Bool = true) {
    guard let controller else {
      return
    }

    let panel = panel ?? makePanel(controller: controller)
    self.panel = panel
    Self.updatePanelPresentation(panel, isPinned: controller.isPanelPinned)

    let wasVisible = panel.isVisible
    if !wasVisible {
      userContentSizeOverride = nil
    }

    let shouldPosition = repositioning || !wasVisible
    resize(
      panel,
      for: controller,
      preservingTopLeft: wasVisible && !shouldPosition,
      animated: false,
      force: true
    )
    if shouldPosition {
      position(panel)
    }

    panel.orderFrontRegardless()
    startDismissMonitors()
    if activating {
      NSApp.activate()
      panel.makeKeyAndOrderFront(nil)
      panel.makeKey()
      panel.makeMain()
      focusSourceEditor(in: panel)
      scheduleSourceFocusRetries(in: panel)
    }
    AppLog.panel.info("Floating panel shown")
  }

  func hide() {
    pendingResizeTask?.cancel()
    pendingResizeTask = nil
    userContentSizeOverride = nil
    panel?.orderOut(nil)
    stopDismissMonitors()
  }

  func hideIfNeeded() {
    guard controller?.isPanelPinned == false else {
      return
    }
    hide()
  }

  func updatePinnedState(isPinned: Bool) {
    guard let panel else {
      return
    }
    Self.updatePanelPresentation(panel, isPinned: isPinned)
    startDismissMonitors()
  }

  func refreshContentLayout() {
    guard let controller, let panel else {
      return
    }

    scheduleResize(panel, for: controller)
  }

  func updateLayout() {
    guard let controller, let panel else {
      return
    }

    resize(panel, for: controller, preservingTopLeft: true, animated: panel.isVisible, force: true)
  }

  private func makePanel(controller: LexiRayController) -> NSPanel {
    let contentSize = Self.contentSize(for: controller)
    let panel = LexiRayFloatingPanel(
      contentRect: NSRect(origin: .zero, size: contentSize),
      styleMask: Self.panelStyleMask,
      backing: .buffered,
      defer: false
    )

    panel.title = "LexiRay"
    Self.updatePanelPresentation(panel, isPinned: controller.isPanelPinned)
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isMovableByWindowBackground = true
    panel.hidesOnDeactivate = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.delegate = self
    panel.contentView = Self.makeContentView(controller: controller)
    applySizeLimits(panel, for: controller)

    return panel
  }

  private static func makeContentView(controller: LexiRayController) -> NSView {
    let hostingView = NSHostingView(rootView: FloatingPanelView(controller: controller))

    if #available(macOS 26.0, *) {
      let glassView = FloatingPanelGlassEffectView(cornerRadius: cornerRadius)
      glassView.style = .regular
      hostingView.translatesAutoresizingMaskIntoConstraints = false
      glassView.contentView = hostingView
      NSLayoutConstraint.activate([
        hostingView.leadingAnchor.constraint(equalTo: glassView.leadingAnchor),
        hostingView.trailingAnchor.constraint(equalTo: glassView.trailingAnchor),
        hostingView.topAnchor.constraint(equalTo: glassView.topAnchor),
        hostingView.bottomAnchor.constraint(equalTo: glassView.bottomAnchor)
      ])
      return glassView
    }

    hostingView.translatesAutoresizingMaskIntoConstraints = false
    let effectView = FloatingPanelVisualEffectView(cornerRadius: cornerRadius)
    effectView.material = .hudWindow
    effectView.blendingMode = .behindWindow
    effectView.state = .active
    effectView.addSubview(hostingView)
    NSLayoutConstraint.activate([
      hostingView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
      hostingView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
      hostingView.topAnchor.constraint(equalTo: effectView.topAnchor),
      hostingView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
    ])
    return effectView
  }

  private func focusSourceEditor(in panel: NSPanel) {
    guard let textView = findTextView(identifier: "FloatingPanelSourceEditor", in: panel.contentView) else {
      return
    }

    panel.makeKeyAndOrderFront(nil)
    panel.makeKey()
    panel.makeMain()
    panel.makeFirstResponder(textView)
    textView.window?.makeFirstResponder(textView)
  }

  private func scheduleSourceFocusRetries(in panel: NSPanel) {
    for delay in [0.0, 0.05, 0.15, 0.3] {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak panel] in
        guard let panel, panel.isVisible else {
          return
        }
        self?.focusSourceEditor(in: panel)
      }
    }
  }

  private func findTextView(identifier: String, in view: NSView?) -> NSTextView? {
    guard let view else {
      return nil
    }

    if let textView = view as? NSTextView,
       textView.identifier?.rawValue == identifier
    {
      return textView
    }

    for subview in view.subviews {
      if let textView = findTextView(identifier: identifier, in: subview) {
        return textView
      }
    }

    return nil
  }

  private func startDismissMonitors() {
    guard globalMouseMonitor == nil, localMouseMonitor == nil, localKeyMonitor == nil else {
      return
    }

    globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] _ in
      Task { @MainActor in
        self?.hideAfterOutsideClick(at: NSEvent.mouseLocation)
      }
    }

    localMouseMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] event in
      let screenLocation = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
      let windowNumber = event.window?.windowNumber
      Task { @MainActor in
        self?.hideAfterLocalMouseEvent(windowNumber: windowNumber, screenLocation: screenLocation)
      }
      return event
    }

    let panelWindowNumber = panel?.windowNumber
    localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self else {
        return event
      }

      let keyCode = event.keyCode
      let modifierFlagsRawValue = event.modifierFlags.rawValue
      let eventWindowNumber = event.window?.windowNumber
      let shouldSwallowEvent = MainActor.assumeIsolated {
        self.shouldSwallowLocalKeyEvent(
          keyCode: keyCode,
          modifierFlags: NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue),
          eventWindowNumber: eventWindowNumber,
          panelWindowNumber: panelWindowNumber,
          panelIsVisible: panel?.isVisible == true
        )
      }
      return shouldSwallowEvent ? nil : event
    }
  }

  private func stopDismissMonitors() {
    if let globalMouseMonitor {
      NSEvent.removeMonitor(globalMouseMonitor)
      self.globalMouseMonitor = nil
    }

    if let localMouseMonitor {
      NSEvent.removeMonitor(localMouseMonitor)
      self.localMouseMonitor = nil
    }

    if let localKeyMonitor {
      NSEvent.removeMonitor(localKeyMonitor)
      self.localKeyMonitor = nil
    }
  }

  private func hideAfterOutsideClick(at screenLocation: NSPoint) {
    guard panel?.isVisible == true, controller?.isPanelPinned == false else {
      return
    }

    if panel?.frame.contains(screenLocation) == false {
      hide()
    }
  }

  private func hideAfterLocalMouseEvent(windowNumber: Int?, screenLocation: NSPoint) {
    guard panel?.isVisible == true, controller?.isPanelPinned == false else {
      return
    }

    guard let panel, windowNumber != panel.windowNumber else {
      return
    }

    if !panel.frame.contains(screenLocation) {
      hide()
    }
  }

  private func position(_ panel: NSPanel) {
    guard let controller else {
      return
    }

    let mouseLocation = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
    let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let size = panel.frame.size
    let lastOrigin = controller.settings.floatingPanelLastOrigin.map { NSPoint(x: $0.x, y: $0.y) }

    setFrameOrigin(
      FloatingPanelPositionResolver.origin(
        placement: controller.settings.floatingPanelPlacement,
        panelSize: size,
        visibleFrame: visibleFrame,
        mouseLocation: mouseLocation,
        lastOrigin: lastOrigin
      ),
      for: panel
    )
  }

  private func scheduleResize(_ panel: NSPanel, for controller: LexiRayController) {
    pendingResizeTask?.cancel()
    pendingResizeTask = Task { @MainActor [weak self, weak panel, weak controller] in
      try? await Task.sleep(nanoseconds: 45_000_000)
      guard let self, let panel, let controller, panel.isVisible else {
        return
      }

      resize(panel, for: controller, preservingTopLeft: true, animated: true, force: false)
    }
  }

  private func resize(
    _ panel: NSPanel,
    for controller: LexiRayController,
    preservingTopLeft: Bool,
    animated: Bool,
    force: Bool
  ) {
    applySizeLimits(panel, for: controller)
    let automaticSize = Self.contentSize(for: controller)
    let targetSize = Self.contentSize(
      automaticSize,
      respectingUserOverride: userContentSizeOverride,
      maximum: Self.maximumContentSize(for: controller)
    )
    setContentSize(
      targetSize,
      for: panel,
      preservingTopLeft: preservingTopLeft,
      animated: animated,
      force: force
    )
  }

  private func applySizeLimits(_ panel: NSPanel, for controller: LexiRayController) {
    panel.contentMinSize = Self.minimumContentSize
    panel.contentMaxSize = Self.maximumContentSize(for: controller)
  }

  private func setContentSize(
    _ size: NSSize,
    for panel: NSPanel,
    preservingTopLeft: Bool,
    animated: Bool,
    force: Bool
  ) {
    let currentFrame = panel.frame
    let targetSize = panel.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
    var targetFrame = currentFrame
    targetFrame.size = targetSize
    if preservingTopLeft {
      targetFrame.origin = NSPoint(x: currentFrame.minX, y: currentFrame.maxY - targetSize.height)
    }

    guard force || Self.shouldApplyResize(from: currentFrame, to: targetFrame) else {
      return
    }

    setFrame(
      targetFrame,
      for: panel,
      animated: animated,
      marksResize: true,
      marksMove: preservingTopLeft
    )
  }

  private func setFrame(
    _ frame: NSRect,
    for panel: NSPanel,
    animated: Bool,
    marksResize: Bool,
    marksMove: Bool
  ) {
    if marksResize {
      isSizingProgrammatically = true
    }
    if marksMove {
      isMovingProgrammatically = true
    }

    guard animated else {
      panel.setFrame(frame, display: true)
      finishProgrammaticFrameChange(marksResize: marksResize, marksMove: marksMove)
      return
    }

    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.14
      context.allowsImplicitAnimation = true
      panel.animator().setFrame(frame, display: true)
    } completionHandler: { [weak self] in
      Task { @MainActor [weak self] in
        self?.finishProgrammaticFrameChange(marksResize: marksResize, marksMove: marksMove)
      }
    }
  }

  private func finishProgrammaticFrameChange(marksResize: Bool, marksMove: Bool) {
    if marksResize {
      isSizingProgrammatically = false
    }
    if marksMove {
      isMovingProgrammatically = false
    }
  }

  private func setFrameOrigin(_ origin: NSPoint, for panel: NSPanel) {
    isMovingProgrammatically = true
    panel.setFrameOrigin(origin)
    isMovingProgrammatically = false
  }

  static func contentSize(for controller: LexiRayController) -> NSSize {
    let maximum = maximumContentSize(for: controller)
    let automaticWidth = automaticContentWidth(for: controller)
    let width = clampedContentWidth(
      contentWidth(for: controller, automaticWidth: automaticWidth),
      maximum: maximum.width
    )
    return clampedContentSize(
      NSSize(width: width, height: contentHeight(for: controller, width: width)),
      maximum: maximum
    )
  }

  static func contentSize(
    _ automaticSize: NSSize,
    respectingUserOverride userOverride: NSSize?,
    maximum: NSSize
  ) -> NSSize {
    guard let userOverride else {
      return clampedContentSize(automaticSize, maximum: maximum)
    }

    return clampedContentSize(
      NSSize(
        width: max(automaticSize.width, userOverride.width),
        height: max(automaticSize.height, userOverride.height)
      ),
      maximum: maximum
    )
  }

  static func panelLevel(isPinned: Bool) -> NSWindow.Level {
    isPinned ? .floating : .normal
  }

  private static func updatePanelPresentation(_ panel: NSPanel, isPinned: Bool) {
    panel.isFloatingPanel = isPinned
    panel.level = panelLevel(isPinned: isPinned)
  }

  private static func contentHeight(for controller: LexiRayController, width: CGFloat) -> CGFloat {
    let maximumHeight = maximumContentHeight(isExpanded: controller.isExpanded)
    let baseHeight = panelBaseHeight(for: controller, width: width)
    let resultContainerPadding: CGFloat = 20
    let resultSpacing: CGFloat = 10
    let resultCharsPerLine = resultCharsPerLine(for: width)

    switch controller.panelState {
    case .idle:
      let providerCount = controller.settings.visibleProviderConfigurations().count
      let previewHeight = idleProviderPreviewHeight(for: controller)
      guard previewHeight > 0 else {
        return clampedContentHeight(baseHeight + 8, minimum: 200, maximum: maximumHeight)
      }

      return clampedContentHeight(
        baseHeight + resultSpacing + resultContainerPadding + previewHeight,
        minimum: providerCount >= 4 ? 360 : 240,
        maximum: min(460, maximumHeight)
      )
    case let .loading(state):
      let previewHeight = state.preview.map {
        estimatedTextHeight(
          $0,
          charsPerLine: resultCharsPerLine,
          maxLines: controller.isExpanded ? nil : 2
        )
      } ?? 0
      let resultHeight = 28 + (previewHeight > 0 ? 10 + previewHeight : 0)
      return clampedContentHeight(
        baseHeight + resultSpacing + resultContainerPadding + resultHeight,
        minimum: 284,
        maximum: maximumHeight
      )
    case let .error(message):
      let resultHeight = 28 + 10 + estimatedTextHeight(message, charsPerLine: resultCharsPerLine)
      return clampedContentHeight(
        baseHeight + resultSpacing + resultContainerPadding + resultHeight,
        minimum: 304,
        maximum: maximumHeight
      )
    case let .batch(batch):
      let resultHeight = batch.entries.enumerated().reduce(CGFloat(0)) { height, pair in
        let dividerHeight: CGFloat = pair.offset == 0 ? 0 : 1
        return height + dividerHeight + estimatedEntryHeight(
          pair.element,
          charsPerLine: resultCharsPerLine
        )
      }
      return clampedContentHeight(
        baseHeight + resultSpacing + resultContainerPadding + resultHeight,
        minimum: 306,
        maximum: maximumHeight
      )
    case let .result(result):
      let resultHeight = 48 + estimatedTextHeight(result.translatedText, charsPerLine: resultCharsPerLine)
      return clampedContentHeight(
        baseHeight + resultSpacing + resultContainerPadding + resultHeight,
        minimum: 306,
        maximum: maximumHeight
      )
    }
  }

  private static func maximumContentSize(for controller: LexiRayController) -> NSSize {
    NSSize(width: 980, height: maximumContentHeight(isExpanded: controller.isExpanded))
  }

  private static func automaticContentWidth(for controller: LexiRayController) -> CGFloat {
    switch controller.panelState {
    case .idle:
      640
    case let .loading(state):
      widthForText(state.preview ?? controller.panelSourceText, base: defaultContentWidth)
    case let .error(message):
      widthForText(message, base: defaultContentWidth)
    case let .result(result):
      widthForText(result.translatedText, base: defaultContentWidth)
    case let .batch(batch):
      widthForTexts(
        [batch.request.text]
          + batch.entries.compactMap { entry in
            switch entry.status {
            case let .streaming(text):
              text
            case let .success(result):
              result.translatedText
            case let .failure(message):
              message
            case .disabled, .translating:
              nil
            }
          },
        base: defaultContentWidth
      )
    }
  }

  private static func contentWidth(for controller: LexiRayController, automaticWidth: CGFloat) -> CGFloat {
    guard let savedSize = controller.settings.floatingPanelLastSize else {
      return automaticWidth
    }

    let savedWidth = CGFloat(savedSize.width)
    switch controller.panelState {
    case .idle:
      return min(idleMaximumContentWidth, max(automaticWidth, savedWidth))
    case .loading, .error, .batch, .result:
      return max(automaticWidth, savedWidth)
    }
  }

  private static func idleProviderPreviewHeight(for controller: LexiRayController) -> CGFloat {
    let providerCount = controller.settings.visibleProviderConfigurations().count
    guard providerCount > 0 else {
      return 0
    }

    let rowHeight: CGFloat = 36
    let dividerHeight: CGFloat = 1
    return CGFloat(providerCount) * rowHeight + CGFloat(max(0, providerCount - 1)) * dividerHeight
  }

  private static func widthForText(_ text: String, base: CGFloat) -> CGFloat {
    widthForTexts([text], base: base)
  }

  private static func widthForTexts(_ texts: [String], base: CGFloat) -> CGFloat {
    let longestLine = texts
      .flatMap { $0.components(separatedBy: .newlines) }
      .map(\.count)
      .max() ?? 0
    let extraWidth = CGFloat(max(0, longestLine - 56)) * 3.8
    return min(900, max(base, base + extraWidth))
  }

  private static func clampedContentSize(_ size: NSSize, maximum: NSSize) -> NSSize {
    NSSize(
      width: clampedContentWidth(size.width, maximum: maximum.width),
      height: min(maximum.height, max(minimumContentSize.height, size.height))
    )
  }

  private static func clampedContentWidth(_ width: CGFloat, maximum: CGFloat) -> CGFloat {
    min(maximum, max(minimumContentSize.width, width.rounded(.up)))
  }

  static func maximumContentHeight(isExpanded: Bool) -> CGFloat {
    let mouseLocation = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
    let visibleHeight = screen?.visibleFrame.height ?? 900
    let appMaximum: CGFloat = isExpanded ? 760 : 680
    return max(320, min(appMaximum, visibleHeight - 96))
  }

  private static func clampedContentHeight(_ height: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
    min(maximum, max(minimum, height.rounded(.up)))
  }

  private static func panelBaseHeight(for controller: LexiRayController, width: CGFloat) -> CGFloat {
    let outerPadding: CGFloat = 28
    let headerHeight: CGFloat = 28
    let headerToSourceSpacing: CGFloat = 10
    let sourceChromeHeight: CGFloat = 20 + 30 + 8
    return outerPadding
      + headerHeight
      + headerToSourceSpacing
      + sourceChromeHeight
      + sourceEditorHeight(for: controller, width: width)
  }

  private static func sourceEditorHeight(for controller: LexiRayController, width: CGFloat) -> CGFloat {
    let minimumHeight: CGFloat = controller.isExpanded ? 80 : 56
    let maximumHeight: CGFloat = controller.isExpanded ? 240 : 150
    guard let text = controller.panelSourceText.nonEmptyTrimmed else {
      return minimumHeight
    }

    let measuredHeight = estimatedTextHeight(text, charsPerLine: sourceCharsPerLine(for: width)) + 18
    return min(maximumHeight, max(minimumHeight, measuredHeight))
  }

  private static func estimatedEntryHeight(_ entry: ProviderTranslationEntry, charsPerLine: Int) -> CGFloat {
    switch entry.status {
    case .disabled:
      40
    case .translating:
      62
    case let .streaming(text):
      48 + estimatedTextHeight(text, charsPerLine: charsPerLine)
    case let .success(result):
      48 + estimatedTextHeight(result.translatedText, charsPerLine: charsPerLine)
    case let .failure(message):
      48 + estimatedTextHeight(message, charsPerLine: charsPerLine)
    }
  }

  private static func estimatedTextHeight(_ text: String, charsPerLine: Int, maxLines: Int? = nil) -> CGFloat {
    let lineCount = estimatedLineCount(text, charsPerLine: charsPerLine)
    return CGFloat(maxLines.map { min($0, lineCount) } ?? lineCount) * 22
  }

  private static func estimatedLineCount(_ text: String, charsPerLine: Int) -> Int {
    text.components(separatedBy: .newlines).reduce(0) { count, line in
      count + max(1, Int(ceil(Double(max(1, line.count)) / Double(charsPerLine))))
    }
  }

  private static func sourceCharsPerLine(for width: CGFloat) -> Int {
    max(24, Int((width - 74) / 8.2))
  }

  private static func resultCharsPerLine(for width: CGFloat) -> Int {
    max(24, Int((width - 86) / 8.2))
  }

  private static func shouldApplyResize(from currentFrame: NSRect, to targetFrame: NSRect) -> Bool {
    abs(currentFrame.width - targetFrame.width) >= resizeThreshold
      || abs(currentFrame.height - targetFrame.height) >= resizeThreshold
      || abs(currentFrame.origin.x - targetFrame.origin.x) >= resizeThreshold
      || abs(currentFrame.origin.y - targetFrame.origin.y) >= resizeThreshold
  }

  private nonisolated static func isSubmitShortcut(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
    (keyCode == 36 || keyCode == 76)
      && modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
  }

  private func shouldSwallowLocalKeyEvent(
    keyCode: UInt16,
    modifierFlags: NSEvent.ModifierFlags,
    eventWindowNumber: Int?,
    panelWindowNumber: Int?,
    panelIsVisible: Bool
  ) -> Bool {
    if Self.isSubmitShortcut(keyCode: keyCode, modifierFlags: modifierFlags),
       eventWindowNumber == panelWindowNumber
    {
      controller?.submitPanelSourceText()
      return true
    }

    if let direction = Self.historyNavigationDirection(keyCode: keyCode, modifierFlags: modifierFlags),
       Self.shouldRoutePanelKeyEvent(
         eventWindowNumber: eventWindowNumber,
         panelWindowNumber: panelWindowNumber,
         panelIsVisible: panelIsVisible
       )
    {
      let handled: Bool?
      switch direction {
      case .previous:
        handled = controller?.showPreviousHistory()
      case .next:
        handled = controller?.showNextHistory()
      }

      if handled == true {
        return true
      }
    }

    guard Self.shouldRouteEscapeKeyEvent(
      keyCode: keyCode,
      eventWindowNumber: eventWindowNumber,
      panelWindowNumber: panelWindowNumber,
      panelIsVisible: panelIsVisible
    ) else {
      return false
    }

    hide()
    return true
  }

  nonisolated static func isEscapeKey(keyCode: UInt16) -> Bool {
    keyCode == 53
  }

  nonisolated static func shouldRouteEscapeKeyEvent(
    keyCode: UInt16,
    eventWindowNumber: Int?,
    panelWindowNumber: Int?,
    panelIsVisible: Bool
  ) -> Bool {
    isEscapeKey(keyCode: keyCode)
      && shouldRoutePanelKeyEvent(
        eventWindowNumber: eventWindowNumber,
        panelWindowNumber: panelWindowNumber,
        panelIsVisible: panelIsVisible
      )
  }

  nonisolated static func shouldRoutePanelKeyEvent(
    eventWindowNumber: Int?,
    panelWindowNumber: Int?,
    panelIsVisible: Bool
  ) -> Bool {
    eventWindowNumber == panelWindowNumber || (eventWindowNumber == nil && panelIsVisible)
  }

  private nonisolated static func historyNavigationDirection(
    keyCode: UInt16,
    modifierFlags: NSEvent.ModifierFlags
  ) -> HistoryNavigationDirection? {
    let modifierFlags = modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting([.numericPad, .function])
    guard modifierFlags.isEmpty else {
      return nil
    }

    switch keyCode {
    case 126:
      return .previous
    case 125:
      return .next
    default:
      return nil
    }
  }
}

private enum HistoryNavigationDirection {
  case previous
  case next
}

extension FloatingPanelController: NSWindowDelegate {
  func windowDidResize(_ notification: Notification) {
    guard !isSizingProgrammatically,
          let panel = notification.object as? NSPanel,
          let currentPanel = self.panel,
          panel === currentPanel
    else {
      return
    }

    guard let controller else {
      return
    }

    let contentSize = panel.contentRect(forFrameRect: panel.frame).size
    userContentSizeOverride = Self.contentSize(
      contentSize,
      respectingUserOverride: nil,
      maximum: Self.maximumContentSize(for: controller)
    )
    controller.settings.recordFloatingPanelSize(
      width: contentSize.width,
      height: contentSize.height
    )
  }

  func windowDidMove(_ notification: Notification) {
    guard !isMovingProgrammatically,
          let panel = notification.object as? NSPanel,
          let currentPanel = self.panel,
          panel === currentPanel
    else {
      return
    }

    controller?.settings.recordFloatingPanelOrigin(
      x: panel.frame.origin.x,
      y: panel.frame.origin.y
    )
  }
}

@available(macOS 26.0, *)
private final class FloatingPanelGlassEffectView: NSGlassEffectView {
  private let panelCornerRadius: CGFloat
  private var lastMaskSize: NSSize = .zero
  private let shapeMask = CAShapeLayer()

  init(cornerRadius: CGFloat) {
    panelCornerRadius = cornerRadius
    super.init(frame: .zero)
    self.cornerRadius = cornerRadius
    wantsLayer = true
    layer?.cornerRadius = cornerRadius
    layer?.masksToBounds = true
    shapeMask.fillColor = NSColor.black.cgColor
    layer?.mask = shapeMask
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layout() {
    super.layout()
    updateShapeMask()
  }

  private func updateShapeMask() {
    guard bounds.width > 0, bounds.height > 0, bounds.size != lastMaskSize else {
      return
    }

    lastMaskSize = bounds.size
    shapeMask.frame = bounds
    shapeMask.path = CGPath(
      roundedRect: bounds,
      cornerWidth: panelCornerRadius,
      cornerHeight: panelCornerRadius,
      transform: nil
    )
  }
}

private final class FloatingPanelVisualEffectView: NSVisualEffectView {
  private let panelCornerRadius: CGFloat
  private var lastMaskSize: NSSize = .zero

  init(cornerRadius: CGFloat) {
    panelCornerRadius = cornerRadius
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = cornerRadius
    layer?.masksToBounds = true
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    nil
  }

  override func layout() {
    super.layout()
    updateMaskImage()
  }

  private func updateMaskImage() {
    guard bounds.width > 0, bounds.height > 0, bounds.size != lastMaskSize else {
      return
    }

    lastMaskSize = bounds.size
    maskImage = FloatingPanelCornerMask.image(size: bounds.size, cornerRadius: panelCornerRadius)
  }
}

private enum FloatingPanelCornerMask {
  static func image(size: NSSize, cornerRadius: CGFloat) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.black.setFill()
    NSBezierPath(
      roundedRect: NSRect(origin: .zero, size: size),
      xRadius: cornerRadius,
      yRadius: cornerRadius
    ).fill()
    image.unlockFocus()
    image.capInsets = NSEdgeInsets(
      top: cornerRadius,
      left: cornerRadius,
      bottom: cornerRadius,
      right: cornerRadius
    )
    return image
  }
}

private final class LexiRayFloatingPanel: NSPanel {
  override var canBecomeKey: Bool {
    true
  }

  override var canBecomeMain: Bool {
    true
  }
}
