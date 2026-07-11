import SwiftUI

/// HapiGo-style large language dropdown used for the panel's source and target
/// pickers. Shows the effective language (or "Auto") in a tall, comfortable
/// button; the menu offers Auto, a Once/Always mode switch, a common-language
/// shortlist, and an "Others" submenu.
struct LanguagePickerButton: View {
  let title: String
  /// Effective selection code; `nil` shows the Auto checkmark.
  let selection: String?
  let onSelect: (String?, LanguageSelectionMode) -> Void

  /// Whether the next language pick applies once or becomes the default. Starts
  /// on "Once" like HapiGo so a pick is non-destructive by default.
  @State private var mode: LanguageSelectionMode = .once

  var body: some View {
    Menu {
      Button {
        onSelect(nil, mode)
      } label: {
        menuItemLabel("Auto", checked: selection == nil)
      }

      Divider()

      Picker("Mode", selection: $mode) {
        Text("Once").tag(LanguageSelectionMode.once)
        Text("Always").tag(LanguageSelectionMode.always)
      }
      .pickerStyle(.inline)

      Divider()

      ForEach(LanguageCatalog.common) { option in
        Button {
          onSelect(option.code, mode)
        } label: {
          menuItemLabel(option.displayName, checked: option.code == selection)
        }
      }

      Divider()

      Menu("Others") {
        ForEach(LanguageCatalog.others) { option in
          Button {
            onSelect(option.code, mode)
          } label: {
            menuItemLabel(option.displayName, checked: option.code == selection)
          }
        }
      }
    } label: {
      LanguagePickerButtonLabel(title: title, isActive: selection != nil)
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    // No width frame: the Menu sizes to its label's content and stays
    // compressible, so a long "Auto: Simplified Chinese" title truncates in the
    // tight single row instead of overflowing (and it never fills the row the
    // way maxWidth:.infinity did).
  }

  private func menuItemLabel(_ text: String, checked: Bool) -> some View {
    HStack {
      Text(text)
      if checked {
        Image(systemName: "checkmark")
      }
    }
  }
}

private struct LanguagePickerButtonLabel: View {
  let title: String
  let isActive: Bool
  @State private var isHovered = false

  var body: some View {
    HStack(spacing: 5) {
      Text(title)
        .font(.caption.weight(.medium))
        .lineLimit(1)
        .truncationMode(.tail)
      Image(systemName: "chevron.down")
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(.secondary)
    }
    .foregroundStyle(isActive ? Color.accentColor : Color.primary)
    .padding(.horizontal, 10)
    .frame(height: 26)
    .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
    }
    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .onHover { isHovered = $0 }
    .animation(.easeOut(duration: 0.12), value: isHovered)
  }

  private var background: Color {
    isHovered ? Color.primary.opacity(0.14) : Color.primary.opacity(0.09)
  }
}
