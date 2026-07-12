import AppKit
import QuartzCore
import SwiftUI

@MainActor
protocol FloatingPanelPresenting: AnyObject {
  func show(activating: Bool, repositioning: Bool)
  func refreshContentLayout()
  func reportMeasuredContentHeights(chrome: CGFloat, resultContent: CGFloat)
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
  /// Slack around the panel frame when deciding whether a click is "outside".
  /// A borderless resizable window's edge/corner resize grab band lands right on
  /// (or a hair past) the frame boundary, so an exact `frame.contains` treats the
  /// resize mouseDown as an outside click and dismisses the panel.
  private static let dismissEdgeTolerance: CGFloat = 4
  private nonisolated static let menuTrackingEventGraceInterval: TimeInterval = 0.25

  /// Shared minimum content height for every panel state so the footprint stays
  /// consistent before / during / after a translation. Content longer than this
  /// still grows the panel via the per-state height estimates below.
  private static let baselineMinimumContentHeight: CGFloat = 300

  private weak var controller: LexiRayController?
  private var panel: NSPanel?
  private var globalMouseMonitor: Any?
  private var localMouseMonitor: Any?
  private var localKeyMonitor: Any?
  private var menuTrackingDepth = 0
  private var menuTrackingEndedAt: TimeInterval?
  private var isObservingMenuTracking = false
  private var pendingResizeTask: Task<Void, Never>?
  private var isMovingProgrammatically = false
  private var isSizingProgrammatically = false
  private var isLiveResizing = false
  private var userContentSizeOverride: NSSize?

  /// Natural heights reported by `FloatingPanelView` via preference keys. The
  /// panel height is derived from these instead of estimating text layout.
  private var measuredChromeHeight: CGFloat = 0
  private var measuredResultContentHeight: CGFloat = 0

  /// Set when the panel is shown "activating": the source editor is focused as
  /// soon as the panel becomes key (see `windowDidBecomeKey`).
  private var wantsSourceFocusOnKey = false

  init(controller: LexiRayController) {
    self.controller = controller
    super.init()
  }

  isolated deinit {
    // Event monitors are otherwise only removed in hide(); guarantee cleanup if
    // the controller is deallocated while the panel is still on screen so the
    // global/local monitors don't leak. NSEvent.removeMonitor is thread-safe.
    for monitor in [globalMouseMonitor, localMouseMonitor, localKeyMonitor] {
      if let monitor {
        NSEvent.removeMonitor(monitor)
      }
    }
    NotificationCenter.default.removeObserver(self, name: NSMenu.didBeginTrackingNotification, object: nil)
    NotificationCenter.default.removeObserver(self, name: NSMenu.didEndTrackingNotification, object: nil)
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
      // Request first-responder focus once the panel actually becomes key
      // (handled in windowDidBecomeKey) instead of racing the show animation
      // with a burst of timers.
      wantsSourceFocusOnKey = true
      NSApp.activate()
      panel.makeKeyAndOrderFront(nil)
    } else {
      wantsSourceFocusOnKey = false
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

  func reportMeasuredContentHeights(chrome: CGFloat, resultContent: CGFloat) {
    let chrome = max(0, chrome)
    let resultContent = max(0, resultContent)
    guard abs(chrome - measuredChromeHeight) > 0.5
      || abs(resultContent - measuredResultContentHeight) > 0.5
    else {
      return
    }

    measuredChromeHeight = chrome
    measuredResultContentHeight = resultContent

    guard let controller, let panel, panel.isVisible else {
      return
    }
    resize(panel, for: controller, preservingTopLeft: true, animated: panel.isVisible, force: false)
  }

  /// The screen the panel currently lives on, falling back to the screen under
  /// the cursor and then the main screen. Used for the height ceiling so it does
  /// not depend on where the mouse happens to be mid-translation.
  private func activeScreen() -> NSScreen? {
    if let panel, let screen = panel.screen {
      return screen
    }
    let mouseLocation = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
  }

  func updateLayout() {
    guard let controller, let panel else {
      return
    }

    resize(panel, for: controller, preservingTopLeft: true, animated: panel.isVisible, force: true)
  }

  private func makePanel(controller: LexiRayController) -> NSPanel {
    let contentSize = contentSize(for: controller)
    let panel = LexiRayFloatingPanel(
      contentRect: NSRect(origin: .zero, size: contentSize),
      styleMask: Self.panelStyleMask,
      backing: .buffered,
      defer: false
    )

    panel.title = "LexiRay Floating Panel"
    panel.setAccessibilityIdentifier("FloatingPanelWindow")
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

    // Clip ONLY the hosting content to the rounded shape. NSHostingView turns
    // its backing opaque (white) when the panel becomes key, and that square
    // backing painted over the rounded glass corners — which is why the white
    // corners only showed while the panel was selected. This clip container is
    // ours (not the SwiftUI-managed hosting layer), so the radius survives
    // relayout and holds in both key and non-key states.
    //
    // Crucially the clip lives *inside* the glass / effect view, wrapping only
    // the content. Masking the glass view's own parent forces it to composite
    // offscreen and stop sampling the live backdrop, which flattened the
    // translucency; keeping the glass unmasked preserves the see-through look.
    let clipView = FloatingPanelClipView(cornerRadius: cornerRadius)
    hostingView.translatesAutoresizingMaskIntoConstraints = false
    clipView.addSubview(hostingView)
    NSLayoutConstraint.activate([
      hostingView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
      hostingView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
      hostingView.topAnchor.constraint(equalTo: clipView.topAnchor),
      hostingView.bottomAnchor.constraint(equalTo: clipView.bottomAnchor)
    ])

    if #available(macOS 26.0, *) {
      let glassView = FloatingPanelGlassEffectView(cornerRadius: cornerRadius)
      glassView.style = .regular
      clipView.translatesAutoresizingMaskIntoConstraints = false
      glassView.contentView = clipView
      NSLayoutConstraint.activate([
        clipView.leadingAnchor.constraint(equalTo: glassView.leadingAnchor),
        clipView.trailingAnchor.constraint(equalTo: glassView.trailingAnchor),
        clipView.topAnchor.constraint(equalTo: glassView.topAnchor),
        clipView.bottomAnchor.constraint(equalTo: glassView.bottomAnchor)
      ])
      return glassView
    }

    let effectView = FloatingPanelVisualEffectView(cornerRadius: cornerRadius)
    effectView.material = .hudWindow
    effectView.blendingMode = .behindWindow
    effectView.state = .active
    clipView.translatesAutoresizingMaskIntoConstraints = false
    effectView.addSubview(clipView)
    NSLayoutConstraint.activate([
      clipView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
      clipView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
      clipView.topAnchor.constraint(equalTo: effectView.topAnchor),
      clipView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
    ])
    return effectView
  }

  private func focusSourceEditor(in panel: NSPanel) {
    guard let textView = findTextView(identifier: "FloatingPanelSourceEditor", in: panel.contentView) else {
      return
    }

    panel.makeFirstResponder(textView)
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

    menuTrackingDepth = 0
    menuTrackingEndedAt = nil
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(menuDidBeginTracking(_:)),
      name: NSMenu.didBeginTrackingNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(menuDidEndTracking(_:)),
      name: NSMenu.didEndTrackingNotification,
      object: nil
    )
    isObservingMenuTracking = true

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
      let eventWindowNumber = event.window?.windowNumber
      let eventWindowLevel = event.window?.level
      let menuOwnsEvent = MainActor.assumeIsolated {
        self?.isMenuTrackingEvent(timestamp: event.timestamp) == true
      }
      Task { @MainActor in
        self?.hideAfterLocalMouseEvent(
          eventWindowNumber: eventWindowNumber,
          eventWindowLevel: eventWindowLevel,
          menuOwnsEvent: menuOwnsEvent,
          screenLocation: screenLocation
        )
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
      let menuOwnsEvent = MainActor.assumeIsolated {
        self.isMenuTrackingEvent(timestamp: event.timestamp)
      }
      // Local event monitors are always invoked on the main thread as part of
      // the app's event dispatch, so main-actor isolation holds here. The
      // monitor must decide synchronously whether to swallow the key (returning
      // nil consumes it), which rules out an async hop — hence assumeIsolated
      // rather than MainActor.run.
      let shouldSwallowEvent = MainActor.assumeIsolated {
        self.shouldSwallowLocalKeyEvent(
          keyCode: keyCode,
          modifierFlags: NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue),
          eventWindowNumber: eventWindowNumber,
          panelWindowNumber: panelWindowNumber,
          panelIsVisible: panel?.isVisible == true,
          menuOwnsEvent: menuOwnsEvent
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

    if isObservingMenuTracking {
      NotificationCenter.default.removeObserver(self, name: NSMenu.didBeginTrackingNotification, object: nil)
      NotificationCenter.default.removeObserver(self, name: NSMenu.didEndTrackingNotification, object: nil)
      isObservingMenuTracking = false
    }
    menuTrackingDepth = 0
    menuTrackingEndedAt = nil
  }

  @objc private func menuDidBeginTracking(_: Notification) {
    menuTrackingDepth += 1
    menuTrackingEndedAt = nil
  }

  @objc private func menuDidEndTracking(_: Notification) {
    menuTrackingDepth = max(0, menuTrackingDepth - 1)
    menuTrackingEndedAt = ProcessInfo.processInfo.systemUptime
  }

  private func isMenuTrackingEvent(timestamp: TimeInterval) -> Bool {
    Self.shouldTreatAsMenuTrackingEvent(
      trackingDepth: menuTrackingDepth,
      trackingEndedAt: menuTrackingEndedAt,
      eventTimestamp: timestamp
    )
  }

  private func hideAfterOutsideClick(at screenLocation: NSPoint) {
    guard panel?.isVisible == true, controller?.isPanelPinned == false, !isLiveResizing else {
      return
    }

    if let panel, !expandedDismissFrame(panel).contains(screenLocation) {
      hide()
    }
  }

  private func hideAfterLocalMouseEvent(
    eventWindowNumber: Int?,
    eventWindowLevel: NSWindow.Level?,
    menuOwnsEvent: Bool,
    screenLocation: NSPoint
  ) {
    guard panel?.isVisible == true, controller?.isPanelPinned == false, !isLiveResizing else {
      return
    }

    guard let panel else {
      return
    }

    let insidePanel = expandedDismissFrame(panel).contains(screenLocation)
    if Self.shouldDismissLocalMouseEvent(
      eventWindowNumber: eventWindowNumber,
      eventWindowLevel: eventWindowLevel,
      panelWindowNumber: panel.windowNumber,
      insidePanel: insidePanel,
      menuOwnsEvent: menuOwnsEvent
    ) {
      hide()
    }
  }

  /// Panel frame grown by the edge tolerance so resize-grab clicks on the
  /// boundary count as "inside".
  private func expandedDismissFrame(_ panel: NSPanel) -> NSRect {
    panel.frame.insetBy(dx: -Self.dismissEdgeTolerance, dy: -Self.dismissEdgeTolerance)
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
    let automaticSize = contentSize(for: controller)
    let targetSize = Self.contentSize(
      automaticSize,
      respectingUserOverride: userContentSizeOverride,
      maximum: maximumContentSize(for: controller)
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
    panel.contentMaxSize = maximumContentSize(for: controller)
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

  /// Panel content size derived from the heights SwiftUI measured for the
  /// chrome and result content, instead of estimating text layout numerically.
  private func contentSize(for controller: LexiRayController) -> NSSize {
    let maximum = maximumContentSize(for: controller)
    let width = Self.panelContentWidth(
      savedWidth: controller.settings.floatingPanelLastSize.map { CGFloat($0.width) },
      isIdle: controller.panelState.isIdle,
      maximum: maximum.width
    )
    let height = Self.panelContentHeight(
      chrome: measuredChromeHeight,
      resultContent: measuredResultContentHeight,
      fallbackChrome: Self.fallbackChromeHeight(for: controller),
      maximum: maximum.height
    )
    return Self.clampedContentSize(NSSize(width: width, height: height), maximum: maximum)
  }

  /// Pure width resolution: honor a manual drag-width exactly (idle caps it at
  /// `idleMaximumContentWidth`), otherwise fall back to the fixed default. The
  /// panel grows only vertically as content arrives (like HapiGo).
  static func panelContentWidth(savedWidth: CGFloat?, isIdle: Bool, maximum: CGFloat) -> CGFloat {
    guard let savedWidth else {
      return clampedContentWidth(defaultContentWidth, maximum: maximum)
    }
    let width = isIdle ? min(idleMaximumContentWidth, savedWidth) : savedWidth
    return clampedContentWidth(width, maximum: maximum)
  }

  /// Pure height composition: sum of the measured chrome and (when present)
  /// result-content heights plus the fixed paddings the views apply, clamped to
  /// the shared minimum floor and the screen ceiling. Falls back to
  /// `fallbackChrome` before SwiftUI has reported a measurement. When the
  /// content exceeds the ceiling the result ScrollView scrolls.
  static func panelContentHeight(
    chrome: CGFloat,
    resultContent: CGFloat,
    fallbackChrome: CGFloat,
    maximum: CGFloat
  ) -> CGFloat {
    // Outer VStack padding (14 top + 14 bottom) around all panel content.
    let outerPadding: CGFloat = 28
    // Spacing between chrome and result area, plus the result container's own
    // inner padding (10 top + 10 bottom) — both fixed in FloatingPanelView.
    let chromeToResultSpacing: CGFloat = 10
    let resultContainerPadding: CGFloat = 20

    let effectiveChrome = chrome > 0 ? chrome : fallbackChrome
    var height = outerPadding + effectiveChrome
    if resultContent > 0 {
      height += chromeToResultSpacing + resultContainerPadding + resultContent
    }

    return clampedContentHeight(height, minimum: baselineMinimumContentHeight, maximum: maximum)
  }

  /// Height used before SwiftUI has reported a measurement (first frame), so the
  /// panel opens at a sensible size rather than collapsing.
  private static func fallbackChromeHeight(for controller: LexiRayController) -> CGFloat {
    let headerHeight: CGFloat = 28
    let headerToSourceSpacing: CGFloat = 10
    let sourceChromeHeight: CGFloat = 20 + 30 + 8
    return headerHeight
      + headerToSourceSpacing
      + sourceChromeHeight
      + FloatingPanelMetrics.sourceEditorMinimumHeight(isExpanded: controller.isExpanded)
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

  private func maximumContentSize(for controller: LexiRayController) -> NSSize {
    NSSize(
      width: 980,
      height: Self.maximumContentHeight(
        isExpanded: controller.isExpanded,
        visibleHeight: activeScreen()?.visibleFrame.height ?? 900
      )
    )
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

  /// Screen-aware height ceiling. Reads the panel's own screen height (resolved
  /// via `activeScreen`) rather than the cursor location so the ceiling is
  /// stable while a translation streams in.
  static func maximumContentHeight(isExpanded: Bool, visibleHeight: CGFloat) -> CGFloat {
    let appMaximum: CGFloat = isExpanded ? 760 : 680
    return max(320, min(appMaximum, visibleHeight - 96))
  }

  private static func clampedContentHeight(_ height: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
    min(maximum, max(minimum, height.rounded(.up)))
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
    panelIsVisible: Bool,
    menuOwnsEvent: Bool
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
      panelIsVisible: panelIsVisible,
      menuOwnsEvent: menuOwnsEvent
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
    panelIsVisible: Bool,
    menuOwnsEvent: Bool
  ) -> Bool {
    !menuOwnsEvent
      && isEscapeKey(keyCode: keyCode)
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

  nonisolated static func shouldDismissLocalMouseEvent(
    eventWindowNumber: Int?,
    eventWindowLevel: NSWindow.Level?,
    panelWindowNumber: Int?,
    insidePanel: Bool,
    menuOwnsEvent: Bool
  ) -> Bool {
    if menuOwnsEvent
      || eventWindowNumber == nil
      || eventWindowNumber == panelWindowNumber
      || eventWindowLevel == .popUpMenu
    {
      return false
    }

    // Menu tracking and borderless resize grabs can arrive without an owning
    // window. Other applications and the desktop are handled by the global
    // monitor, so an ambiguous local event must not dismiss the panel.
    return !insidePanel
  }

  nonisolated static func shouldTreatAsMenuTrackingEvent(
    trackingDepth: Int,
    trackingEndedAt: TimeInterval?,
    eventTimestamp: TimeInterval
  ) -> Bool {
    if trackingDepth > 0 {
      return true
    }
    guard let trackingEndedAt else {
      return false
    }
    return abs(trackingEndedAt - eventTimestamp) <= menuTrackingEventGraceInterval
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
  func windowDidBecomeKey(_ notification: Notification) {
    guard wantsSourceFocusOnKey,
          let panel = notification.object as? NSPanel,
          panel === self.panel
    else {
      return
    }

    wantsSourceFocusOnKey = false
    focusSourceEditor(in: panel)
  }

  func windowWillStartLiveResize(_: Notification) {
    isLiveResizing = true
  }

  func windowDidEndLiveResize(_: Notification) {
    isLiveResizing = false

    // Persist the final drag size once, rather than on every intermediate
    // windowDidResize notification (which fires dozens of times per drag).
    guard let controller, let panel, panel === self.panel else {
      return
    }
    let contentSize = panel.contentRect(forFrameRect: panel.frame).size
    controller.settings.recordFloatingPanelSize(
      width: contentSize.width,
      height: contentSize.height
    )
  }

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

    // Track the drag in memory so content updates don't snap the panel back; the
    // size is only written to settings when the live resize ends.
    let contentSize = panel.contentRect(forFrameRect: panel.frame).size
    userContentSizeOverride = Self.contentSize(
      contentSize,
      respectingUserOverride: nil,
      maximum: maximumContentSize(for: controller)
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

/// A plain container whose layer clips its subviews to the panel's rounded
/// shape. Because it is an ordinary view we own (not the SwiftUI-managed
/// NSHostingView, whose layer SwiftUI resets on relayout), the corner radius is
/// stable across focus changes and clips the hosting view's opaque key-state
/// backing that otherwise showed square white corners.
private final class FloatingPanelClipView: NSView {
  init(cornerRadius: CGFloat) {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = cornerRadius
    layer?.cornerCurve = .continuous
    layer?.masksToBounds = true
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

@available(macOS 26.0, *)
private final class FloatingPanelGlassEffectView: NSGlassEffectView {
  /// Trust NSGlassEffectView's own cornerRadius for the rounded shape: it renders
  /// the glass with correct Retina anti-aliasing. Stacking layer.cornerRadius +
  /// masksToBounds + a CAShapeLayer mask (whose contentsScale defaulted to 1×)
  /// re-clipped the corners at 1× on 2× displays, producing the jagged edge.
  init(cornerRadius: CGFloat) {
    super.init(frame: .zero)
    self.cornerRadius = cornerRadius
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

private final class FloatingPanelVisualEffectView: NSVisualEffectView {
  private let panelCornerRadius: CGFloat

  init(cornerRadius: CGFloat) {
    panelCornerRadius = cornerRadius
    super.init(frame: .zero)
    wantsLayer = true
    // Clip the rounded shape solely through `maskImage` below. Previously this
    // *also* set `layer.cornerRadius` + `masksToBounds`, so the corners were
    // clipped twice — and the mask bitmap was rasterized at 1×, so on a 2×
    // Retina display the second clip re-sampled the edge at half resolution and
    // produced the jagged / uneven border. A single resolution-independent mask
    // (Apple's recommended NSVisualEffectView route) renders cleanly.
    maskImage = FloatingPanelCornerMask.image(cornerRadius: cornerRadius)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    nil
  }
}

private enum FloatingPanelCornerMask {
  /// A small rounded-rect mask stretched by `capInsets`. Because it is drawn via
  /// `NSImage(size:flipped:drawingHandler:)`, AppKit re-renders it at whatever
  /// backing scale the destination needs (1×, 2×, …), so the corners stay smooth
  /// on Retina instead of being sampled at 1×.
  static func image(cornerRadius: CGFloat) -> NSImage {
    // Just large enough to hold both rounded corners plus a 1pt stretchable
    // middle strip; capInsets tile the center to any panel size.
    let side = cornerRadius * 2 + 1
    let size = NSSize(width: side, height: side)

    let image = NSImage(size: size, flipped: false) { rect in
      NSColor.black.setFill()
      NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
      return true
    }
    image.capInsets = NSEdgeInsets(
      top: cornerRadius,
      left: cornerRadius,
      bottom: cornerRadius,
      right: cornerRadius
    )
    image.resizingMode = .stretch
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
