import AppKit
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

  static var minimumContentSize: NSSize {
    NSSize(width: 560, height: 330)
  }

  private weak var controller: LexiRayController?
  private var panel: NSPanel?
  private var globalMouseMonitor: Any?
  private var localMouseMonitor: Any?
  private var localKeyMonitor: Any?
  private var isMovingProgrammatically = false
  private var isSizingProgrammatically = false

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

    let shouldPosition = repositioning || !panel.isVisible
    resize(panel, for: controller, preservingTopLeft: panel.isVisible && !shouldPosition)
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

    resize(panel, for: controller, preservingTopLeft: true)
  }

  func updateLayout() {
    guard let controller, let panel else {
      return
    }

    resize(panel, for: controller, preservingTopLeft: true)
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
    panel.delegate = self
    panel.contentView = NSHostingView(rootView: FloatingPanelView(controller: controller))
    applySizeLimits(panel, for: controller)

    return panel
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

  private func resize(_ panel: NSPanel, for controller: LexiRayController, preservingTopLeft: Bool) {
    let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
    applySizeLimits(panel, for: controller)
    setContentSize(Self.contentSize(for: controller), for: panel)

    if preservingTopLeft {
      setFrameOrigin(NSPoint(x: topLeft.x, y: topLeft.y - panel.frame.height), for: panel)
    }
  }

  private func applySizeLimits(_ panel: NSPanel, for controller: LexiRayController) {
    panel.contentMinSize = Self.minimumContentSize
    panel.contentMaxSize = Self.maximumContentSize(for: controller)
  }

  private func setContentSize(_ size: NSSize, for panel: NSPanel) {
    isSizingProgrammatically = true
    panel.setContentSize(size)
    isSizingProgrammatically = false
  }

  private func setFrameOrigin(_ origin: NSPoint, for panel: NSPanel) {
    isMovingProgrammatically = true
    panel.setFrameOrigin(origin)
    isMovingProgrammatically = false
  }

  static func contentSize(for controller: LexiRayController) -> NSSize {
    guard let savedSize = controller.settings.floatingPanelLastSize else {
      return automaticContentSize(for: controller)
    }

    return clampedContentSize(
      NSSize(width: CGFloat(savedSize.width), height: CGFloat(savedSize.height)),
      maximum: maximumContentSize(for: controller)
    )
  }

  static func panelLevel(isPinned: Bool) -> NSWindow.Level {
    isPinned ? .floating : .normal
  }

  private static func updatePanelPresentation(_ panel: NSPanel, isPinned: Bool) {
    panel.isFloatingPanel = isPinned
    panel.level = panelLevel(isPinned: isPinned)
  }

  private static func contentHeight(for controller: LexiRayController) -> CGFloat {
    let maximumHeight = maximumContentHeight(isExpanded: controller.isExpanded)
    switch controller.panelState {
    case .idle:
      return 330
    case let .loading(state):
      let preview = state.preview ?? state.title
      let estimatedHeight = 300 + estimatedTextHeight(preview, charsPerLine: 54)
      return clampedContentHeight(estimatedHeight, minimum: 360, maximum: maximumHeight)
    case let .error(message):
      let estimatedHeight = 320 + estimatedTextHeight(message, charsPerLine: 54)
      return clampedContentHeight(estimatedHeight, minimum: 380, maximum: maximumHeight)
    case let .batch(batch):
      let estimatedHeight = batch.entries.reduce(CGFloat(224)) { height, entry in
        height + estimatedEntryHeight(entry, isExpanded: controller.isExpanded)
      }
      return clampedContentHeight(estimatedHeight, minimum: 390, maximum: maximumHeight)
    case let .result(result):
      let estimatedHeight = 278 + estimatedTextHeight(result.translatedText, charsPerLine: 48)
      return clampedContentHeight(estimatedHeight, minimum: 390, maximum: maximumHeight)
    }
  }

  private static func automaticContentSize(for controller: LexiRayController) -> NSSize {
    clampedContentSize(
      NSSize(width: defaultContentWidth, height: contentHeight(for: controller)),
      maximum: maximumContentSize(for: controller)
    )
  }

  private static func maximumContentSize(for controller: LexiRayController) -> NSSize {
    NSSize(width: 980, height: maximumContentHeight(isExpanded: controller.isExpanded))
  }

  private static func clampedContentSize(_ size: NSSize, maximum: NSSize) -> NSSize {
    NSSize(
      width: min(maximum.width, max(minimumContentSize.width, size.width)),
      height: min(maximum.height, max(minimumContentSize.height, size.height))
    )
  }

  static func maximumContentHeight(isExpanded: Bool) -> CGFloat {
    let mouseLocation = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
    let visibleHeight = screen?.visibleFrame.height ?? 900
    let appMaximum: CGFloat = isExpanded ? 760 : 680
    return max(390, min(appMaximum, visibleHeight - 96))
  }

  private static func clampedContentHeight(_ height: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
    min(maximum, max(minimum, height.rounded(.up)))
  }

  private static func estimatedEntryHeight(_ entry: ProviderTranslationEntry, isExpanded: Bool) -> CGFloat {
    switch entry.status {
    case .disabled:
      38
    case .translating:
      64
    case let .streaming(text):
      54 + estimatedTextHeight(text, charsPerLine: isExpanded ? 54 : 48)
    case let .success(result):
      54 + estimatedTextHeight(result.translatedText, charsPerLine: isExpanded ? 54 : 48)
    case let .failure(message):
      54 + estimatedTextHeight(message, charsPerLine: 54)
    }
  }

  private static func estimatedTextHeight(_ text: String, charsPerLine: Int) -> CGFloat {
    CGFloat(estimatedLineCount(text, charsPerLine: charsPerLine)) * 22
  }

  private static func estimatedLineCount(_ text: String, charsPerLine: Int) -> Int {
    text.components(separatedBy: .newlines).reduce(0) { count, line in
      count + max(1, Int(ceil(Double(max(1, line.count)) / Double(charsPerLine))))
    }
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

    if keyCode != 53 {
      return false
    }

    hideIfNeeded()
    return true
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

    controller?.settings.recordFloatingPanelSize(
      width: panel.frame.width,
      height: panel.frame.height
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

private final class LexiRayFloatingPanel: NSPanel {
  override var canBecomeKey: Bool {
    true
  }

  override var canBecomeMain: Bool {
    true
  }
}
