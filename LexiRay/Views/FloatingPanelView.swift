import SwiftUI

struct FloatingPanelView: View {
  @ObservedObject var controller: LexiRayController
  @ObservedObject private var settings: SettingsStore
  @Environment(\.openWindow) private var openWindow

  init(controller: LexiRayController) {
    _controller = ObservedObject(wrappedValue: controller)
    _settings = ObservedObject(wrappedValue: controller.settings)
  }

  var body: some View {
    ZStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 10) {
        header
        sourceComposer
        if showsResultArea {
          resultArea
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .topLeading)

      if let toast = controller.copyToast, toast.surface == .floatingPanel {
        CopyToastView(toast: toast)
          .padding(.top, 18)
          .transition(.opacity.combined(with: .scale(scale: 0.96)))
          .zIndex(2)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color.clear)
    .animation(.easeInOut(duration: 0.16), value: showsResultArea)
    .animation(.easeInOut(duration: 0.16), value: controller.copyToast?.id)
    .onReceive(settings.$providerConfigurations) { _ in
      refreshLayoutForStandbyProviderChanges()
    }
    .onReceive(settings.$apiKeyRevision) { _ in
      refreshLayoutForStandbyProviderChanges()
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 8) {
      Text(controller.activeHistoryPositionText ?? "LexiRay")
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
      sourceHeaderRow

      SourceTextEditor(
        text: $controller.panelSourceText,
        placeholder: sourcePlaceholder,
        minHeight: sourceEditorMinimumHeight,
        maxHeight: sourceEditorMaximumHeight,
        accessibilityIdentifier: "FloatingPanelSourceEditor",
        helpText: sourceEditorHelpText,
        onMoveUp: controller.showPreviousHistory,
        onMoveDown: controller.showNextHistory,
        onHeightChange: controller.refreshFloatingPanelLayout
      )
    }
    .padding(10)
    .background(.black.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(Color(nsColor: .separatorColor).opacity(0.34), lineWidth: 1)
    }
    .transaction { transaction in
      transaction.animation = nil
    }
  }

  /// Compact single-row header: source ⇄ target language pickers plus the
  /// clear / translate actions, matching the original tight footprint.
  private var sourceHeaderRow: some View {
    HStack(spacing: 8) {
      Text("Source")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      LanguagePickerButton(
        title: sourcePickerTitle,
        selection: controller.panelSourceSelection,
        onSelect: { code, mode in controller.selectPanelSourceLanguage(code, mode: mode) }
      )

      Button {
        controller.swapPanelDirection()
      } label: {
        Image(systemName: "arrow.left.arrow.right")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(width: 24, height: 26)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(controller.panelSourceText.nonEmptyTrimmed == nil)
      .help("Swap translation direction")

      LanguagePickerButton(
        title: targetPickerTitle,
        selection: controller.panelTargetSelection,
        onSelect: { code, mode in controller.selectPanelTargetLanguage(code, mode: mode) }
      )

      if controller.lastSelectionSource != .unavailable {
        PanelPill(title: controller.lastSelectionSource.displayName, systemName: sourceIcon, color: sourceColor)
      }

      Spacer(minLength: 8)

      panelButton(systemName: "xmark.circle.fill", help: "Clear Source", action: controller.clearPanelSourceText)
        .opacity(controller.panelSourceText.isEmpty ? 0 : 1)
        .disabled(controller.panelSourceText.isEmpty)
        .accessibilityHidden(controller.panelSourceText.isEmpty)

      Button {
        controller.submitPanelSourceText()
      } label: {
        Label(translateButtonTitle, systemImage: "arrow.right.circle.fill")
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.small)
      .frame(width: 132, height: 30)
      .keyboardShortcut(.return, modifiers: [.command])
      .disabled(controller.panelSourceText.nonEmptyTrimmed == nil)
      .help("Translate")
    }
    .frame(height: 30)
  }

  private var resultArea: some View {
    resultContent
      .padding(10)
      .frame(maxWidth: .infinity, maxHeight: resultAreaMaximumHeight, alignment: .topLeading)
      .background(.black.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1)
      }
  }

  private var idleView: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(standbyProviderConfigurations.enumerated()), id: \.element.id) { index, configuration in
          ProviderStandbyRow(settings: settings, configuration: configuration)
            .padding(.vertical, 4)

          if index < standbyProviderConfigurations.count - 1 {
            Divider()
              .opacity(0.52)
              .padding(.leading, 28)
          }
        }
      }
      .padding(.vertical, 2)
      .frame(maxWidth: .infinity, alignment: .topLeading)
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
    GeometryReader { proxy in
      ScrollView {
        TranslationBatchResultsView(
          controller: controller,
          batch: batch,
          showsSourcePreview: false,
          resultLineLimit: nil,
          copyToastSurface: .floatingPanel
        )
        .padding(.trailing, 12)
        .frame(width: max(0, proxy.size.width), alignment: .topLeading)
      }
      .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
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
    }
    .buttonStyle(FloatingPanelIconButtonStyle(isActive: isActive))
    .accessibilityLabel(help)
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

  /// Auto mode shows the resolved language ("Auto: English") and refreshes as the
  /// detected/translated direction updates, matching HapiGo; a pinned language
  /// shows its own name. Reads panelState/panelSourceText so SwiftUI re-renders
  /// the titles the moment a translation lands.
  private var sourcePickerTitle: String {
    languagePickerTitle(selection: controller.panelSourceSelection, resolved: controller.resolvedPanelDirection().source)
  }

  private var targetPickerTitle: String {
    languagePickerTitle(selection: controller.panelTargetSelection, resolved: controller.resolvedPanelDirection().target)
  }

  private func languagePickerTitle(selection: String?, resolved: String?) -> String {
    if let selection {
      return LanguageCatalog.displayName(for: selection)
    }
    if let resolved {
      return "Auto: \(LanguageCatalog.displayName(for: resolved))"
    }
    return "Auto"
  }

  private var sourceIcon: String {
    switch controller.lastSelectionSource {
    case .accessibility:
      "accessibility"
    case .browserAppleScript:
      "safari"
    case .simulatedCopy:
      "doc.on.clipboard"
    case .manual:
      "keyboard"
    case .ocr:
      "text.viewfinder"
    case .unavailable:
      "questionmark.circle"
    }
  }

  private var sourceColor: Color {
    controller.lastSelectionSource == .unavailable ? .secondary : .accentColor
  }

  private var sourcePlaceholder: String {
    controller.canNavigateTranslationHistory ? "Type or paste text  ↑  ↓  History" : "Type or edit source text"
  }

  private var sourceEditorHelpText: String? {
    controller.canNavigateTranslationHistory ? "Press Up or Down to browse translation history." : nil
  }

  private var translateButtonTitle: String {
    switch controller.panelState {
    case .idle, .error:
      "Translate"
    case .loading, .batch, .result:
      "Retranslate"
    }
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

  private var showsResultArea: Bool {
    switch controller.panelState {
    case .idle:
      !standbyProviderConfigurations.isEmpty
    case .loading, .batch, .result, .error:
      true
    }
  }

  private var standbyProviderConfigurations: [ProviderConfiguration] {
    settings.panelOrderedProviderConfigurations()
  }

  private var resultAreaMaximumHeight: CGFloat? {
    switch controller.panelState {
    case .idle:
      .infinity
    case .loading, .batch, .result, .error:
      .infinity
    }
  }

  private var sourceEditorMinimumHeight: CGFloat {
    controller.isExpanded ? 80 : 56
  }

  private var sourceEditorMaximumHeight: CGFloat {
    controller.isExpanded ? 240 : 150
  }

  private func refreshLayoutForStandbyProviderChanges() {
    guard case .idle = controller.panelState else {
      return
    }

    controller.refreshFloatingPanelLayout()
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

private struct ProviderStandbyRow: View {
  let settings: SettingsStore
  let configuration: ProviderConfiguration

  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      ProviderIconView(providerID: configuration.providerID)

      VStack(alignment: .leading, spacing: 3) {
        Text(configuration.effectiveDisplayName)
          .font(.callout.weight(.semibold))
          .lineLimit(1)

        if configuration.hasCustomDisplayName {
          Text(configuration.providerID.displayName)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      Spacer(minLength: 12)

      PanelPill(title: status.title, systemName: status.systemName, color: status.color)
    }
    .frame(minHeight: 48, alignment: .center)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(configuration.effectiveDisplayName), \(status.title)")
  }

  private var status: ProviderStandbyStatus {
    guard configuration.isEnabled else {
      return .off
    }

    if configuration.providerID.needsAPIKey,
       !settings.hasAPIKey(forConfigurationID: configuration.id)
    {
      return .keyNeeded
    }

    return .standBy
  }
}

private enum ProviderStandbyStatus {
  case standBy
  case off
  case keyNeeded

  var title: String {
    switch self {
    case .standBy:
      "Stand by"
    case .off:
      "Off"
    case .keyNeeded:
      "Key needed"
    }
  }

  var systemName: String {
    switch self {
    case .standBy:
      "checkmark.circle"
    case .off:
      "pause.circle"
    case .keyNeeded:
      "key.fill"
    }
  }

  var color: Color {
    switch self {
    case .standBy:
      .accentColor
    case .off:
      .secondary
    case .keyNeeded:
      .orange
    }
  }
}
