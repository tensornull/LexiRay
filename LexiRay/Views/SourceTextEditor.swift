import AppKit
import SwiftUI

struct SourceTextEditor: View {
  static let textInset = CGSize(width: 11, height: 9)
  static let lineFragmentPadding: CGFloat = 0

  @Binding var text: String
  let placeholder: String
  var minHeight: CGFloat = 116
  var accessibilityIdentifier = "SourceTextEditor"
  var onMoveUp: (() -> Bool)?
  var onMoveDown: (() -> Bool)?

  @State private var isFocused = false

  var body: some View {
    ZStack(alignment: .topLeading) {
      SourceTextView(
        text: $text,
        isFocused: $isFocused,
        textInset: Self.textInset,
        lineFragmentPadding: Self.lineFragmentPadding,
        accessibilityIdentifier: accessibilityIdentifier,
        onMoveUp: onMoveUp,
        onMoveDown: onMoveDown
      )

      if text.isEmpty {
        Text(placeholder)
          .font(.body)
          .foregroundStyle(.tertiary)
          .padding(.leading, Self.textInset.width)
          .padding(.top, Self.textInset.height)
          .allowsHitTesting(false)
      }
    }
    .frame(minHeight: minHeight, maxHeight: minHeight)
    .background(Color(nsColor: .textBackgroundColor).opacity(0.34), in: RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(
          isFocused ? Color.accentColor.opacity(0.75) : Color(nsColor: .separatorColor).opacity(0.55),
          lineWidth: isFocused ? 1.25 : 1
        )
    }
  }
}

private struct SourceTextView: NSViewRepresentable {
  @Binding var text: String
  @Binding var isFocused: Bool
  let textInset: CGSize
  let lineFragmentPadding: CGFloat
  let accessibilityIdentifier: String
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
    configure(textView)
    textView.delegate = context.coordinator
    textView.string = text
    textView.identifier = NSUserInterfaceItemIdentifier(accessibilityIdentifier)

    scrollView.documentView = textView
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.parent = self

    guard let textView = scrollView.documentView as? NSTextView else {
      return
    }

    configure(textView)
    if textView.string != text {
      context.coordinator.isProgrammaticUpdate = true
      textView.string = text
      context.coordinator.isProgrammaticUpdate = false
    }
  }

  private func configure(_ textView: NSTextView) {
    textView.drawsBackground = false
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.isEditable = true
    textView.isSelectable = true
    textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    textView.textColor = .textColor
    textView.insertionPointColor = .controlAccentColor
    textView.textContainerInset = textInset
    textView.textContainer?.lineFragmentPadding = lineFragmentPadding
    textView.textContainer?.widthTracksTextView = true
    textView.isHorizontallyResizable = false
    textView.isVerticallyResizable = true
    textView.minSize = NSSize(width: 0, height: scrollViewDefaultHeight)
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    textView.autoresizingMask = [.width]
    textView.usesFindPanel = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
  }

  private var scrollViewDefaultHeight: CGFloat {
    116
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: SourceTextView
    var isProgrammaticUpdate = false

    init(_ parent: SourceTextView) {
      self.parent = parent
    }

    func textDidChange(_ notification: Notification) {
      guard !isProgrammaticUpdate else {
        return
      }

      guard let textView = notification.object as? NSTextView else {
        return
      }
      parent.text = textView.string
    }

    func textDidBeginEditing(_: Notification) {
      DispatchQueue.main.async { [weak self] in
        self?.parent.isFocused = true
      }
    }

    func textDidEndEditing(_: Notification) {
      DispatchQueue.main.async { [weak self] in
        self?.parent.isFocused = false
      }
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
  }
}

private final class SourceTextNSTextView: NSTextView {
  var historyNavigationHandler: ((SourceTextHistoryDirection) -> Bool)?

  override func keyDown(with event: NSEvent) {
    if let direction = SourceTextHistoryDirection(event: event),
       historyNavigationHandler?(direction) == true
    {
      return
    }

    super.keyDown(with: event)
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
