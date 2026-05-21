import SwiftUI

struct TranslationBatchResultsView: View {
  @ObservedObject var controller: LexiRayController
  let batch: TranslationBatch
  var showsSourcePreview = true
  var resultLineLimit: Int?
  var compact = false

  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 10 : 12) {
      if showsSourcePreview {
        sourcePreview
      }

      VStack(alignment: .leading, spacing: 0) {
        ForEach(batch.entries) { entry in
          ProviderTranslationResultRow(
            controller: controller,
            settings: controller.settings,
            entry: entry,
            resultLineLimit: resultLineLimit,
            compact: compact
          )

          if entry.id != batch.entries.last?.id {
            Divider()
          }
        }
      }
    }
  }

  private var sourcePreview: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Source")
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)

      Text(batch.request.text)
        .font(compact ? .body : .body.weight(.medium))
        .foregroundStyle(.primary)
        .lineLimit(sourceLineLimit)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var sourceLineLimit: Int? {
    if compact {
      return 4
    }

    return resultLineLimit == nil ? nil : 6
  }
}

private struct ProviderTranslationResultRow: View {
  @ObservedObject var controller: LexiRayController
  @ObservedObject var settings: SettingsStore
  let entry: ProviderTranslationEntry
  var resultLineLimit: Int?
  var compact: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 7 : 8) {
      HStack(alignment: .center, spacing: 8) {
        Image(systemName: entry.providerID.systemImage)
          .foregroundStyle(.secondary)
          .frame(width: 15)

        Text(entry.providerName)
          .font((compact ? Font.callout : Font.body).weight(.semibold))
          .lineLimit(1)

        if entry.providerName != entry.providerID.displayName {
          Text(entry.providerID.displayName)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
        }

        Spacer(minLength: 12)

        trailingControls
      }

      if !entry.status.isDisabled {
        content
      }
    }
    .padding(.vertical, entry.status.isDisabled ? 8 : compact ? 10 : 11)
  }

  @ViewBuilder
  private var trailingControls: some View {
    switch entry.status {
    case .disabled:
      HStack(spacing: 6) {
        StatusPill(title: "Off", systemName: "pause.circle", color: .secondary)
        providerToggleButton
      }
    case .translating:
      HStack(spacing: 6) {
        ProgressView()
          .controlSize(.small)
        StatusPill(title: "Translating", systemName: "clock", color: .secondary)
        providerToggleButton
      }
    case .streaming:
      HStack(spacing: 6) {
        ProgressView()
          .controlSize(.small)
        StatusPill(title: "Streaming", systemName: "clock", color: .secondary)
        providerToggleButton
      }
    case let .success(result):
      HStack(spacing: 6) {
        iconButton(systemName: "doc.on.doc", help: "Copy") {
          controller.copyResultToClipboard(result)
        }

        copyFormatMenu(result)

        iconButton(
          systemName: controller.isSpeaking(result) ? "stop.fill" : "speaker.wave.2",
          help: controller.isSpeaking(result) ? "Stop" : "Speak",
          isActive: controller.isSpeaking(result)
        ) {
          controller.toggleSpeak(result)
        }

        providerToggleButton
      }
    case .failure:
      HStack(spacing: 6) {
        StatusPill(title: "Failed", systemName: "exclamationmark.triangle.fill", color: .orange)
        providerToggleButton
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    switch entry.status {
    case .disabled:
      EmptyView()
    case .translating:
      Text("Waiting for \(entry.providerName)...")
        .font(.body)
        .foregroundStyle(.secondary)
    case let .streaming(partialText):
      RichTranslationText(
        text: partialText,
        font: compact ? .callout : .body,
        lineLimit: resultLineLimit
      )
    case let .success(result):
      RichTranslationText(
        text: result.translatedText,
        font: compact ? .callout : .body,
        lineLimit: resultLineLimit
      )
    case let .failure(message):
      Text(message)
        .font(.body)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var providerToggleButton: some View {
    iconButton(
      systemName: controller.isProviderEnabled(entry.providerConfigurationID) ? "chevron.down" : "chevron.right",
      help: controller.isProviderEnabled(entry.providerConfigurationID) ? "Disable Provider" : "Enable Provider"
    ) {
      controller.toggleProviderEnabled(entry.providerConfigurationID)
    }
  }

  private func copyFormatMenu(_ result: TranslationResult) -> some View {
    Menu {
      ForEach(CopyFormat.allCases) { format in
        Button {
          controller.copyResultToClipboard(result, format: format)
        } label: {
          HStack {
            Text(format.displayName)
            if format == settings.defaultCopyFormat {
              Image(systemName: "checkmark")
            }
          }
        }
      }
    } label: {
      Image(systemName: "chevron.down")
        .frame(width: 22, height: 22)
    }
    .menuStyle(.borderlessButton)
    .help("Copy Format")
  }

  private func iconButton(
    systemName: String,
    help: String,
    isActive: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .frame(width: 22, height: 22)
        .foregroundStyle(isActive ? Color.accentColor : Color.primary)
    }
    .buttonStyle(.borderless)
    .help(help)
  }
}

private struct StatusPill: View {
  let title: String
  let systemName: String
  let color: Color

  var body: some View {
    Label(title, systemImage: systemName)
      .font(.caption)
      .foregroundStyle(color)
      .labelStyle(.titleAndIcon)
  }
}
