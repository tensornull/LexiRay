import AppKit
import SwiftUI

struct SourceTextEditor: View {
  static var textInset: CGSize {
    CGSize(width: 11, height: 9)
  }

  static let lineFragmentPadding: CGFloat = 0

  static var textColor: NSColor {
    .labelColor
  }

  @Binding var text: String
  let placeholder: String
  var minHeight: CGFloat = 56
  var maxHeight: CGFloat = 150
  var accessibilityIdentifier = "SourceTextEditor"
  var helpText: String?
  var onMoveUp: (() -> Bool)?
  var onMoveDown: (() -> Bool)?
  var onHeightChange: (() -> Void)?

  @State private var isFocused = false
  @State private var measuredTextHeight: CGFloat = 0
  @State private var hasMarkedText = false

  var body: some View {
    ZStack(alignment: .topLeading) {
      // Placeholder sits *behind* the transparent text view so the insertion
      // point and IME marked text always draw above it, like HapiGo.
      if text.isEmpty && !hasMarkedText {
        Text(placeholder)
          .font(.body)
          .foregroundStyle(.tertiary)
          .padding(.leading, Self.textInset.width)
          .padding(.top, Self.textInset.height)
          .allowsHitTesting(false)
      }

      SourceTextView(
        text: $text,
        isFocused: $isFocused,
        hasMarkedText: $hasMarkedText,
        textInset: Self.textInset,
        lineFragmentPadding: Self.lineFragmentPadding,
        accessibilityIdentifier: accessibilityIdentifier,
        onMeasuredHeightChange: handleMeasuredHeightChange,
        onMoveUp: onMoveUp,
        onMoveDown: onMoveDown
      )
    }
    .frame(minHeight: editorHeight, maxHeight: editorHeight)
    .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(
          isFocused ? Color.accentColor.opacity(0.72) : Color(nsColor: .separatorColor).opacity(0.38),
          lineWidth: isFocused ? 1.25 : 1
        )
    }
    .help(helpText ?? placeholder)
  }

  private var editorHeight: CGFloat {
    let measured = measuredTextHeight > 0 ? measuredTextHeight : minHeight
    return min(maxHeight, max(minHeight, measured))
  }

  private func handleMeasuredHeightChange(_ measuredHeight: CGFloat) {
    let clampedHeight = min(maxHeight, max(minHeight, measuredHeight))
    guard abs(clampedHeight - measuredTextHeight) > 1 else {
      return
    }

    measuredTextHeight = clampedHeight
    onHeightChange?()
  }
}

private struct SourceTextView: NSViewRepresentable {
  @Binding var text: String
  @Binding var isFocused: Bool
  @Binding var hasMarkedText: Bool
  let textInset: CGSize
  let lineFragmentPadding: CGFloat
  let accessibilityIdentifier: String
  let onMeasuredHeightChange: (CGFloat) -> Void
  let onMoveUp: (() -> Bool)?
  let onMoveDown: (() -> Bool)?

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.borderType = .noBorder
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.identifier = NSUserInterfaceItemIdentifier(accessibilityIdentifier)

    let textView = SourceTextNSTextView()
    textView.historyNavigationHandler = { [coordinator = context.coordinator] direction in
      coordinator.handleHistoryNavigation(direction)
    }
    textView.markedTextStateDidChange = { [coordinator = context.coordinator] hasMarkedText in
      coordinator.updateHasMarkedText(hasMarkedText)
    }
    textView.appearanceDidChange = { [coordinator = context.coordinator] textView in
      coordinator.applyTextAttributes(to: textView)
    }
    textView.contentHeightDidChange = { [coordinator = context.coordinator, weak textView] in
      guard let textView else {
        return
      }
      coordinator.scheduleHeightRefresh(for: textView)
    }
    configure(textView)
    textView.delegate = context.coordinator
    textView.string = text
    textView.identifier = NSUserInterfaceItemIdentifier(accessibilityIdentifier)

    scrollView.documentView = textView
    context.coordinator.scheduleHeightRefresh(for: textView)
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.parent = self

    guard let textView = scrollView.documentView as? NSTextView else {
      return
    }

    // While IME composition is in progress the text view is the source of
    // truth: the storage holds the inline marked text (pinyin preview), and
    // reconfiguring fonts/typing attributes or replacing `string` mid-
    // composition aborts the IME transaction. Leave the view untouched; the
    // binding re-syncs from textDidChange once the composition commits.
    guard !textView.hasMarkedText() else {
      return
    }

    configure(textView)

    if textView.string != text {
      context.coordinator.isProgrammaticUpdate = true
      textView.string = text
      context.coordinator.isProgrammaticUpdate = false
    }
    context.coordinator.scheduleHeightRefresh(for: textView)
  }

  private func configure(_ textView: NSTextView) {
    textView.drawsBackground = false
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.isEditable = true
    textView.isSelectable = true
    let textAttributes = Self.textAttributes()
    textView.font = Self.textFont
    textView.textColor = Self.textColor
    textView.typingAttributes = textAttributes
    if let textStorage = textView.textStorage, textStorage.length > 0 {
      textStorage.addAttributes(textAttributes, range: NSRange(location: 0, length: textStorage.length))
    }
    textView.insertionPointColor = .controlAccentColor
    textView.textContainerInset = textInset
    textView.textContainer?.lineFragmentPadding = lineFragmentPadding
    textView.textContainer?.widthTracksTextView = true
    textView.isHorizontallyResizable = false
    textView.isVerticallyResizable = true
    textView.minSize = NSSize(width: 0, height: 0)
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.textContainer?.containerSize = NSSize(
      width: max(0, textView.bounds.width - textInset.width * 2),
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.autoresizingMask = [.width]
    textView.usesFindPanel = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
  }

  private static var textFont: NSFont {
    NSFont.systemFont(ofSize: NSFont.systemFontSize)
  }

  private static var textColor: NSColor {
    SourceTextEditor.textColor
  }

  private static func textAttributes() -> [NSAttributedString.Key: Any] {
    [
      .font: textFont,
      .foregroundColor: textColor
    ]
  }

  @MainActor
  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: SourceTextView
    var isProgrammaticUpdate = false
    private var pendingHeightRefresh = false
    private var lastReportedHeight: CGFloat = 0

    init(_ parent: SourceTextView) {
      self.parent = parent
    }

    func scheduleHeightRefresh(for textView: NSTextView) {
      guard !pendingHeightRefresh else {
        return
      }
      pendingHeightRefresh = true
      Task { @MainActor [weak self, weak textView] in
        guard let self, let textView else {
          return
        }
        pendingHeightRefresh = false
        reportHeight(for: textView)
      }
    }

    func textDidChange(_ notification: Notification) {
      guard !isProgrammaticUpdate else {
        return
      }

      guard let textView = notification.object as? NSTextView else {
        return
      }
      parent.text = textView.string
      updateHasMarkedText(textView.hasMarkedText())

      let editedText = textView.string
      Task { @MainActor [weak self, weak textView] in
        guard let self, let textView, textView.string == editedText else {
          return
        }
        applyTextAttributes(to: textView)
      }
      scheduleHeightRefresh(for: textView)
    }

    func textDidBeginEditing(_ notification: Notification) {
      DispatchQueue.main.async { [weak self] in
        self?.parent.isFocused = true
      }
    }

    func textDidEndEditing(_ notification: Notification) {
      DispatchQueue.main.async { [weak self] in
        self?.parent.isFocused = false
        self?.updateHasMarkedText(false)
      }
    }

    func updateHasMarkedText(_ newValue: Bool) {
      guard parent.hasMarkedText != newValue else {
        return
      }
      parent.hasMarkedText = newValue
    }

    @MainActor
    func handleHistoryNavigation(_ direction: SourceTextHistoryDirection) -> Bool {
      switch direction {
      case .previous:
        parent.onMoveUp?() ?? false
      case .next:
        parent.onMoveDown?() ?? false
      }
    }

    private func reportHeight(for textView: NSTextView) {
      guard let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
      else {
        return
      }

      layoutManager.ensureLayout(for: textContainer)
      let usedHeight = layoutManager.usedRect(for: textContainer).height
      let measuredHeight = ceil(usedHeight + parent.textInset.height * 2)
      guard abs(measuredHeight - lastReportedHeight) > 1 else {
        return
      }

      lastReportedHeight = measuredHeight
      parent.onMeasuredHeightChange(measuredHeight)
    }

    func applyTextAttributes(to textView: NSTextView) {
      let textAttributes = SourceTextView.textAttributes()
      textView.textColor = SourceTextView.textColor
      textView.typingAttributes = textAttributes
      if let textStorage = textView.textStorage, textStorage.length > 0 {
        textStorage.addAttributes(textAttributes, range: NSRange(location: 0, length: textStorage.length))
        textView.layoutManager?.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: textStorage.length))
      }
      textView.setNeedsDisplay(textView.bounds)
    }
  }
}

private final class SourceTextNSTextView: NSTextView {
  var historyNavigationHandler: ((SourceTextHistoryDirection) -> Bool)?
  var contentHeightDidChange: (() -> Void)?
  var appearanceDidChange: ((SourceTextNSTextView) -> Void)?
  var markedTextStateDidChange: ((Bool) -> Void)?

  // IME composition hooks: `textDidChange` is not a reliable signal for
  // marked-text transitions, so report state from the NSTextInputClient
  // entry points directly.
  //
  // The notification is deferred to the next runloop turn: mutating SwiftUI
  // state synchronously from inside the text input system re-enters
  // updateNSView while the IME transaction is still open, which aborts the
  // inline composition (the pinyin preview never reaches the screen).
  override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
    super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    notifyMarkedTextStateChange()
  }

  override func unmarkText() {
    super.unmarkText()
    notifyMarkedTextStateChange()
  }

  override func insertText(_ string: Any, replacementRange: NSRange) {
    super.insertText(string, replacementRange: replacementRange)
    notifyMarkedTextStateChange()
  }

  private func notifyMarkedTextStateChange() {
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        return
      }
      self.markedTextStateDidChange?(self.hasMarkedText())
    }
  }

  override func layout() {
    super.layout()
    textContainer?.containerSize = NSSize(
      width: max(0, bounds.width - textContainerInset.width * 2),
      height: CGFloat.greatestFiniteMagnitude
    )
    contentHeightDidChange?()
  }

  override func keyDown(with event: NSEvent) {
    if let direction = SourceTextHistoryDirection(event: event),
       historyNavigationHandler?(direction) == true
    {
      return
    }

    super.keyDown(with: event)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    appearanceDidChange?(self)
  }
}

private enum SourceTextHistoryDirection {
  case previous
  case next

  init?(event: NSEvent) {
    let modifierFlags = event.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting([.numericPad, .function])
    guard modifierFlags.isEmpty else {
      return nil
    }

    switch event.keyCode {
    case 126:
      self = .previous
    case 125:
      self = .next
    default:
      return nil
    }
  }
}
