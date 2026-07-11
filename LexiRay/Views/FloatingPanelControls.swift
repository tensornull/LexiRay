import SwiftUI

/// Applies the platform-native capsule button style to the panel's direction control.
/// Uses Liquid Glass on macOS 26+ and the bordered capsule on earlier releases, and
/// only tints the active (manual) state — matching Apple's "tint the primary action only"
/// guidance so the control reads as neutral chrome until the user pins a direction.
struct DirectionSwapButtonStyleModifier: ViewModifier {
  let isManual: Bool

  func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      if isManual {
        content
          .buttonStyle(.glassProminent)
          .buttonBorderShape(.capsule)
          .tint(.accentColor)
      } else {
        content
          .buttonStyle(.glass)
          .buttonBorderShape(.capsule)
      }
    } else {
      if isManual {
        content
          .buttonStyle(.borderedProminent)
          .buttonBorderShape(.capsule)
          .tint(.accentColor)
      } else {
        content
          .buttonStyle(.bordered)
          .buttonBorderShape(.capsule)
      }
    }
  }
}

extension View {
  func directionSwapButtonStyle(isManual: Bool) -> some View {
    modifier(DirectionSwapButtonStyleModifier(isManual: isManual))
  }
}

struct FloatingPanelIconButtonStyle: ButtonStyle {
  var isActive = false

  func makeBody(configuration: Configuration) -> some View {
    FloatingPanelIconButtonBody(configuration: configuration, isActive: isActive)
  }
}

/// The shared 28×28 rounded hover-chip that backs every floating-panel icon
/// control, so the button style and the menu label render identically.
private struct FloatingPanelIconChip<Label: View>: View {
  let isActive: Bool
  let isPressed: Bool
  let isEnabled: Bool
  let isHovered: Bool
  @ViewBuilder let label: Label

  var body: some View {
    label
      .font(.system(size: 15, weight: .medium))
      .foregroundStyle(foregroundColor)
      .frame(width: 28, height: 28)
      .background(backgroundColor, in: RoundedRectangle(cornerRadius: 6))
      .contentShape(RoundedRectangle(cornerRadius: 6))
      .scaleEffect(isPressed ? 0.96 : 1)
      .animation(.easeOut(duration: 0.12), value: isHovered)
      .animation(.easeOut(duration: 0.08), value: isPressed)
  }

  private var foregroundColor: Color {
    if !isEnabled {
      return .secondary.opacity(0.45)
    }
    return isActive ? .accentColor : .secondary
  }

  private var backgroundColor: Color {
    guard isEnabled else {
      return .clear
    }
    if isPressed {
      return Color.primary.opacity(0.16)
    }
    if isHovered || isActive {
      return Color.primary.opacity(isActive ? 0.11 : 0.08)
    }
    return .clear
  }
}

private struct FloatingPanelIconButtonBody: View {
  @Environment(\.isEnabled) private var isEnabled
  let configuration: ButtonStyle.Configuration
  let isActive: Bool
  @State private var isHovered = false

  var body: some View {
    FloatingPanelIconChip(
      isActive: isActive,
      isPressed: configuration.isPressed,
      isEnabled: isEnabled,
      isHovered: isHovered
    ) {
      configuration.label
    }
    .onHover { isHovered = $0 }
  }
}

struct FloatingPanelIconMenuLabel: View {
  let systemName: String
  var isActive = false
  @State private var isHovered = false

  var body: some View {
    FloatingPanelIconChip(
      isActive: isActive,
      isPressed: false,
      isEnabled: true,
      isHovered: isHovered
    ) {
      Image(systemName: systemName)
    }
    .onHover { isHovered = $0 }
  }
}

enum CopyToastSurface: Equatable {
  case mainWindow
  case floatingPanel
}

struct CopyToast: Equatable, Identifiable {
  let id = UUID()
  let message: String
  let surface: CopyToastSurface
}

struct CopyToastView: View {
  let toast: CopyToast

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
      Text(toast.message)
        .font(.body.weight(.semibold))
        .foregroundStyle(.green)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 9)
    .background(.regularMaterial, in: Capsule())
    .overlay {
      Capsule()
        .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.14), radius: 12, x: 0, y: 4)
    .accessibilityLabel(toast.message)
  }
}
