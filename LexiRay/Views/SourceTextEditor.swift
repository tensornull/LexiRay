import SwiftUI

struct SourceTextEditor: View {
  @Binding var text: String
  let placeholder: String
  var minHeight: CGFloat = 116
  var accessibilityIdentifier = "SourceTextEditor"

  @FocusState private var isFocused: Bool

  var body: some View {
    ZStack(alignment: .topLeading) {
      if text.isEmpty {
        Text(placeholder)
          .foregroundStyle(.tertiary)
          .padding(.horizontal, 11)
          .padding(.vertical, 10)
          .allowsHitTesting(false)
      }

      TextEditor(text: $text)
        .font(.body)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .focused($isFocused)
        .accessibilityLabel("Source Text")
        .accessibilityIdentifier(accessibilityIdentifier)
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
