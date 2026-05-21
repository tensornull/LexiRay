import SwiftUI

struct FloatingPanelView: View {
  @ObservedObject var controller: LexiRayController
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      content
    }
    .padding(14)
    .frame(width: panelSize.width, height: panelSize.height, alignment: .topLeading)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(.separator.opacity(0.7), lineWidth: 1)
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text("LexiRay Translate")
          .font(.title3.weight(.semibold))
          .lineLimit(1)

        Text(headerSubtitle)
          .font(.caption.weight(.medium))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer()

      panelButton(
        systemName: "gearshape",
        help: "Settings",
        action: openSettings
      )

      panelButton(
        systemName: controller.isPanelPinned ? "pin.fill" : "pin",
        help: controller.isPanelPinned ? "Unpin" : "Pin",
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
  private var content: some View {
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

  private var idleView: some View {
    HStack(spacing: 10) {
      Image(systemName: "keyboard")
        .foregroundStyle(.secondary)
      Text(controller.settings.translateHotKey.displayString)
        .font(.body)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
          .lineLimit(controller.isExpanded ? nil : 4)
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
        showsSourcePreview: true,
        resultLineLimit: controller.isExpanded ? nil : 8
      )
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

  private func panelButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .frame(width: 26, height: 26)
    }
    .buttonStyle(.borderless)
    .help(help)
  }

  private func openSettings() {
    controller.openSettingsFromFloatingPanel()
    openWindow(id: "main")
    AppWindowPresenter.bringMainWindowToFrontSoon()
  }

  private var headerSubtitle: String {
    switch controller.panelState {
    case .idle:
      "Ready"
    case let .loading(state):
      state.title
    case let .batch(batch):
      LanguageDetector.directionLabel(
        sourceLanguage: batch.request.sourceLanguage,
        targetLanguage: batch.request.targetLanguage
      )
    case let .result(result):
      LanguageDetector.directionLabel(
        sourceLanguage: result.request.sourceLanguage,
        targetLanguage: result.request.targetLanguage
      )
    case .error:
      "Needs attention"
    }
  }

  private var panelSize: CGSize {
    FloatingPanelController.contentSize(for: controller)
  }
}
