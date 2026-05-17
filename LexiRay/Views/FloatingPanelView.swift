import SwiftUI

struct FloatingPanelView: View {
  @ObservedObject var controller: LexiRayController

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header

      Divider()

      content

      Spacer(minLength: 0)
    }
    .padding(16)
    .frame(width: 430, height: controller.isExpanded ? 420 : 286)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .stroke(.separator.opacity(0.7), lineWidth: 1)
    }
  }

  private var header: some View {
    HStack(spacing: 10) {
      Image(systemName: "text.magnifyingglass")
        .font(.title3)

      Text("LexiRay")
        .font(.headline)

      Spacer()

      Button {
        controller.togglePinned()
      } label: {
        Image(systemName: controller.isPanelPinned ? "pin.fill" : "pin")
      }
      .buttonStyle(.borderless)
      .help(controller.isPanelPinned ? "Unpin" : "Pin")

      Button {
        controller.toggleExpanded()
      } label: {
        Image(systemName: controller.isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
      }
      .buttonStyle(.borderless)
      .help(controller.isExpanded ? "Collapse" : "Expand")
    }
  }

  @ViewBuilder
  private var content: some View {
    switch controller.panelState {
    case .idle:
      ContentUnavailableView("Ready", systemImage: "keyboard", description: Text(AppConstants.defaultHotKeyDescription))
    case let .loading(text):
      VStack(alignment: .leading, spacing: 12) {
        ProgressView()
        Text(text)
          .font(.body)
          .foregroundStyle(.secondary)
          .lineLimit(4)
          .textSelection(.enabled)
      }
    case let .result(result):
      resultView(result)
    case let .error(message):
      ContentUnavailableView("No Translation", systemImage: "exclamationmark.triangle", description: Text(message))
    }
  }

  private func resultView(_ result: TranslationResult) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(result.translatedText)
        .font(.title3)
        .textSelection(.enabled)
        .lineLimit(controller.isExpanded ? nil : 6)

      if controller.settings.showProviderDetails {
        HStack(spacing: 8) {
          Label(result.providerName, systemImage: "bolt.horizontal.circle")
          Text(result.request.selectionSource.displayName)
          if let detectedLanguage = result.detectedLanguage {
            Text(detectedLanguage)
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      HStack {
        Button {
          controller.copyResultToClipboard()
        } label: {
          Label("Copy", systemImage: "doc.on.doc")
        }

        Button {
          controller.speakResult()
        } label: {
          Label("Speak", systemImage: "speaker.wave.2")
        }

        Spacer()
      }
    }
  }
}
