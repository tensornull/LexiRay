import SwiftUI

struct FloatingPanelView: View {
  @ObservedObject var controller: LexiRayController
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      header
      sourceComposer
      resultArea
    }
    .padding(12)
    .frame(width: panelSize.width, height: panelSize.height, alignment: .topLeading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 8) {
      Text("LexiRay")
        .font(.headline.weight(.semibold))
        .lineLimit(1)

      PanelPill(title: statusTitle, systemName: statusIcon, color: statusColor)

      Spacer()

      panelButton(
        systemName: "gearshape",
        help: "Settings",
        action: openSettings
      )

      panelButton(
        systemName: controller.isPanelPinned ? "pin.fill" : "pin",
        help: controller.isPanelPinned ? "Unpin" : "Pin",
        isActive: controller.isPanelPinned,
        action: controller.togglePinned
      )

      panelButton(
        systemName: controller.isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
        help: controller.isExpanded ? "Collapse" : "Expand",
        action: controller.toggleExpanded
      )

      panelButton(systemName: "xmark", help: "Close", action: controller.hideFloatingPanel)
    }
  }

  @ViewBuilder
  private var resultContent: some View {
    switch controller.panelState {
    case .idle:
      idleView
    case let .loading(state):
      loadingView(state)
    case let .batch(batch):
      batchView(batch)
    case let .result(result):
      resultView(result)
    case let .error(message):
      errorView(message)
    }
  }

  private var sourceComposer: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Text("Source")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)

        PanelPill(title: directionLabel, systemName: "arrow.left.arrow.right", color: .secondary)

        Spacer()

        if !controller.panelSourceText.isEmpty {
          panelButton(systemName: "xmark.circle.fill", help: "Clear Source", action: controller.clearPanelSourceText)
        }

        Button {
          controller.submitPanelSourceText()
        } label: {
          Label(translateButtonTitle, systemImage: "arrow.right.circle.fill")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .keyboardShortcut(.return, modifiers: [.command])
        .disabled(controller.panelSourceText.nonEmptyTrimmed == nil)
        .help("Translate")
      }

      SourceTextEditor(
        text: $controller.panelSourceText,
        placeholder: "Type or edit source text",
        minHeight: controller.isExpanded ? 150 : 116,
        accessibilityIdentifier: "FloatingPanelSourceEditor"
      )
    }
    .padding(10)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.34), in: RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color(nsColor: .separatorColor).opacity(0.48), lineWidth: 1)
    }
  }

  private var resultArea: some View {
    resultContent
      .padding(10)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(Color(nsColor: .textBackgroundColor).opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(Color(nsColor: .separatorColor).opacity(0.42), lineWidth: 1)
      }
  }

  private var idleView: some View {
    VStack(alignment: .leading, spacing: 6) {
      Image(systemName: "text.viewfinder")
        .foregroundStyle(.secondary)
      Text("Ready")
        .font(.body.weight(.medium))
      Text("No source text yet.")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func loadingView(_ state: PanelLoadingState) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        ProgressView()
          .controlSize(.small)
        Text(state.title)
          .font(.body.weight(.medium))
      }

      if let preview = state.preview?.nonEmptyTrimmed {
        Text(preview)
          .font(.body)
          .foregroundStyle(.secondary)
          .lineLimit(controller.isExpanded ? nil : 2)
          .textSelection(.enabled)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func resultView(_ result: TranslationResult) -> some View {
    let batch = TranslationBatch(
      request: result.request,
      entries: [
        ProviderTranslationEntry(
          providerConfigurationID: result.providerConfigurationID,
          providerID: result.providerID,
          providerName: result.providerName,
          status: .success(result)
        )
      ]
    )

    return batchView(batch)
  }

  private func batchView(_ batch: TranslationBatch) -> some View {
    ScrollView {
      TranslationBatchResultsView(
        controller: controller,
        batch: batch,
        showsSourcePreview: false,
        resultLineLimit: nil
      )
      .padding(.trailing, 12)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func errorView(_ message: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        Text("No Translation")
          .font(.body.weight(.medium))
      }

      Text(message)
        .font(.body)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func panelButton(
    systemName: String,
    help: String,
    isActive: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .frame(width: 24, height: 24)
        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
    }
    .buttonStyle(.borderless)
    .help(help)
  }

  private func openSettings() {
    controller.openSettingsFromFloatingPanel()
    AppWindowPresenter.requestMainWindowPresentation()
    openWindow(id: "main")
    AppWindowPresenter.presentMainWindowIfAvailable()
  }

  private var statusTitle: String {
    switch controller.panelState {
    case .idle:
      "Ready"
    case let .loading(state):
      state.title
    case let .batch(batch):
      if hasInFlightEntry(in: batch) {
        "Translating"
      } else if !batch.successfulResults.isEmpty {
        "Translated"
      } else if batch.entries.allSatisfy(\.status.isDisabled) {
        "No active provider"
      } else {
        "Needs attention"
      }
    case .result:
      "Translated"
    case .error:
      "Needs attention"
    }
  }

  private var statusIcon: String {
    switch controller.panelState {
    case .idle:
      "checkmark.circle"
    case .loading:
      "clock"
    case let .batch(batch):
      hasInFlightEntry(in: batch) ? "clock" : "checkmark.circle"
    case .result:
      "checkmark.circle"
    case .error:
      "exclamationmark.triangle"
    }
  }

  private var statusColor: Color {
    switch controller.panelState {
    case .error:
      .orange
    case let .batch(batch) where batch.entries.allSatisfy(\.status.isDisabled):
      .secondary
    default:
      .accentColor
    }
  }

  private var directionLabel: String {
    switch controller.panelState {
    case let .batch(batch):
      return LanguageDetector.directionLabel(
        sourceLanguage: batch.request.sourceLanguage,
        targetLanguage: batch.request.targetLanguage
      )
    case let .result(result):
      return LanguageDetector.directionLabel(
        sourceLanguage: result.request.sourceLanguage,
        targetLanguage: result.request.targetLanguage
      )
    case .idle, .loading, .error:
      let sourceLanguage = controller.panelSourceText.nonEmptyTrimmed.flatMap {
        LanguageDetector.dominantLanguageCode(for: $0)
      }
      return LanguageDetector.directionLabel(
        sourceLanguage: sourceLanguage,
        targetLanguage: controller.settings.resolvedTargetLanguage(for: sourceLanguage)
      )
    }
  }

  private var translateButtonTitle: String {
    switch controller.panelState {
    case .idle, .error:
      "Translate"
    case .loading, .batch, .result:
      "Retranslate"
    }
  }

  private var panelSize: CGSize {
    FloatingPanelController.contentSize(for: controller)
  }

  private func hasInFlightEntry(in batch: TranslationBatch) -> Bool {
    batch.entries.contains { entry in
      switch entry.status {
      case .translating, .streaming:
        true
      case .disabled, .success, .failure:
        false
      }
    }
  }
}

private struct PanelPill: View {
  let title: String
  let systemName: String
  let color: Color

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: systemName)
      Text(title)
        .lineLimit(1)
    }
    .font(.caption.weight(.medium))
    .foregroundStyle(color)
    .padding(.horizontal, 7)
    .padding(.vertical, 3)
    .background(.quaternary, in: Capsule())
  }
}
