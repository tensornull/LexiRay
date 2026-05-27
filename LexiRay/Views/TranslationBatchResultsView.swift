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
        ProviderIconView(providerID: entry.providerID)
          .frame(width: 17)

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
      ProviderFailureDetailView(message: message)
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
      FloatingPanelIconMenuLabel(systemName: "chevron.down")
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
    }
    .buttonStyle(FloatingPanelIconButtonStyle(isActive: isActive))
    .help(help)
  }
}

private struct ProviderFailureDetailView: View {
  let message: String

  private var parts: ProviderFailureMessageParts {
    ProviderFailureMessageParts(message)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(parts.summary)
        .font(.body)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      ForEach(Array(parts.details.enumerated()), id: \.offset) { _, detail in
        TranslationCodeBlockView(language: detail.title, code: detail.body)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }
}

private struct ProviderFailureMessageParts {
  let summary: String
  let details: [(title: String, body: String)]

  init(_ message: String) {
    let markers = ["Response body:", "Stream event:"]
    var earliestMarker: (range: Range<String.Index>, marker: String)?

    for marker in markers {
      guard let range = message.range(of: marker) else {
        continue
      }
      if earliestMarker == nil || range.lowerBound < earliestMarker!.range.lowerBound {
        earliestMarker = (range, marker)
      }
    }

    guard let firstMarker = earliestMarker else {
      summary = message
      details = []
      return
    }

    summary = String(message[..<firstMarker.range.lowerBound]).trimmedForQuery
    details = ProviderFailureMessageParts.extractDetails(
      from: String(message[firstMarker.range.lowerBound...]),
      markers: markers
    )
  }

  private static func extractDetails(
    from text: String,
    markers: [String]
  ) -> [(title: String, body: String)] {
    var details: [(title: String, body: String)] = []
    var remaining = text

    while let marker = markers.compactMap({ marker -> (String, Range<String.Index>)? in
      remaining.range(of: marker).map { (marker, $0) }
    }).min(by: { $0.1.lowerBound < $1.1.lowerBound }) {
      let bodyStart = marker.1.upperBound
      let tail = String(remaining[bodyStart...])
      let nextMarkerRange = markers
        .compactMap { tail.range(of: $0) }
        .min(by: { $0.lowerBound < $1.lowerBound })

      let body: String
      if let nextMarkerRange {
        body = String(tail[..<nextMarkerRange.lowerBound]).trimmedForQuery
        remaining = String(tail[nextMarkerRange.lowerBound...])
      } else {
        body = tail.trimmedForQuery
        remaining = ""
      }

      if !body.isEmpty {
        details.append((title: marker.0.replacingOccurrences(of: ":", with: ""), body: body))
      }

      if remaining.isEmpty {
        break
      }
    }

    return details
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
