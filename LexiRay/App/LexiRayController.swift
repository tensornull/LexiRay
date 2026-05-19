import AppKit
import Combine
import Foundation

@MainActor
final class LexiRayController: ObservableObject {
  static let shared = LexiRayController()

  @Published var panelState: PanelState = .idle
  @Published var isPanelPinned = false
  @Published var isExpanded = false
  @Published var lastSelectionSource: SelectionSource = .unavailable
  @Published var lastOCRText = ""
  @Published private(set) var speakingResultID: UUID?

  let settings: SettingsStore

  private let selectionService: TextSelectionReading
  private let permissionChecker: PermissionChecking
  private let pipeline: TranslationPipeline
  private let hotKeyService = GlobalHotKeyService()
  private let ocrService = OCRService()
  private let ocrSelectionOverlay = OCRSelectionOverlayController()
  private let speechService: SpeechControlling
  private var floatingPanel: FloatingPanelPresenting!
  private var translationTask: Task<Void, Never>?
  private var providerTranslationTasks: [ProviderID: Task<Void, Never>] = [:]
  private var activeBatchID: UUID?

  init(
    settings: SettingsStore = SettingsStore(),
    selectionService: TextSelectionReading = TextSelectionService(),
    permissionChecker: PermissionChecking = SystemPermissionChecker(),
    floatingPanelFactory: ((LexiRayController) -> FloatingPanelPresenting)? = nil,
    pipeline: TranslationPipeline? = nil,
    speechService: SpeechControlling? = nil
  ) {
    self.settings = settings
    self.selectionService = selectionService
    self.permissionChecker = permissionChecker
    self.pipeline = pipeline ?? TranslationPipeline(settings: settings)
    self.speechService = speechService ?? SpeechService()
    floatingPanel = floatingPanelFactory?(self) ?? FloatingPanelController(controller: self)
    self.speechService.onStateChange = { [weak self] isSpeaking in
      if !isSpeaking {
        self?.speakingResultID = nil
      }
    }
  }

  func start() {
    guard !AppRuntime.isRunningTests else {
      return
    }

    permissionChecker.requestAccessibilityIfNeeded(prompt: false)
    hotKeyService.registerDefaultHotKeys(
      translate: { [weak self] in
        self?.translateCurrentSelection()
      },
      ocr: { [weak self] in
        self?.translateOCRRegion()
      }
    )
    AppLog.app.info("LexiRay started")
  }

  func translateCurrentSelection() {
    cancelTranslationWork()
    isExpanded = false
    panelState = .loading(PanelLoadingState(title: "Reading selection...", preview: nil))

    translationTask = Task { @MainActor [weak self] in
      guard let self else {
        return
      }

      let selection = await selectionService.readSelectedText()
      guard !Task.isCancelled else {
        return
      }

      lastSelectionSource = selection.source

      guard let text = selection.text?.nonEmptyTrimmed else {
        panelState = .error(selectionUnavailableMessage(for: selection.failureReason))
        floatingPanel.show()
        return
      }

      panelState = .loading(PanelLoadingState(title: "Translating...", preview: text))
      floatingPanel.show()
      await Task.yield()

      startBatchTranslation(text: text, source: selection.source)
    }
  }

  func translateManualText(_ text: String) {
    translate(text: text, source: .manual)
  }

  func translateOCRRegion() {
    cancelTranslationWork()
    isExpanded = false
    panelState = .loading(PanelLoadingState(title: "Drag to select an OCR region...", preview: nil))
    lastSelectionSource = .ocr
    floatingPanel.show()

    ocrSelectionOverlay.beginSelection { [weak self] rect in
      guard let self else {
        return
      }

      guard let rect else {
        panelState = .idle
        hideFloatingPanelIfNeeded()
        return
      }

      recognizeAndTranslateOCR(in: rect)
    }
  }

  func translateLastOCRText() {
    translate(text: lastOCRText, source: .ocr)
  }

  private func recognizeAndTranslateOCR(in rect: CGRect) {
    cancelTranslationWork()
    isExpanded = false
    panelState = .loading(PanelLoadingState(title: "Recognizing text...", preview: nil))
    floatingPanel.show()

    translationTask = Task { @MainActor [weak self] in
      guard let self else {
        return
      }

      do {
        let text = try await ocrService.captureAndRecognizeText(in: rect)
        guard !Task.isCancelled else {
          return
        }

        lastOCRText = text
        await translateRecognizedText(text)
      } catch {
        panelState = .error(error.localizedDescription)
        floatingPanel.show()
        AppLog.ocr.error("OCR failed: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  private func translateRecognizedText(_ text: String) async {
    lastSelectionSource = .ocr
    panelState = .loading(PanelLoadingState(title: "Translating OCR text...", preview: text))
    floatingPanel.show()
    await Task.yield()

    startBatchTranslation(text: text, source: .ocr)
  }

  private func translate(text: String, source: SelectionSource) {
    cancelTranslationWork()
    isExpanded = false
    panelState = .loading(PanelLoadingState(title: "Translating...", preview: text))
    lastSelectionSource = source
    floatingPanel.show()

    startBatchTranslation(text: text, source: source)
  }

  func copyResultToClipboard() {
    guard let result = currentResults.first else {
      return
    }

    copyResultToClipboard(result)
  }

  func copyResultToClipboard(_ result: TranslationResult) {
    copyResultToClipboard(result, format: settings.defaultCopyFormat)
  }

  func copyResultToClipboard(_ result: TranslationResult, format: CopyFormat) {
    TranslationPasteboardWriter.write(result: result, format: format)
    settings.defaultCopyFormat = format
  }

  func speakResult() {
    guard let result = currentResults.first else {
      return
    }

    speakResult(result)
  }

  func speakResult(_ result: TranslationResult) {
    toggleSpeak(result)
  }

  func toggleSpeak(_ result: TranslationResult) {
    if isSpeaking(result) {
      stopSpeaking()
      return
    }

    stopSpeaking()
    if speechService.speak(result.translatedText, languageCode: result.request.targetLanguage) {
      speakingResultID = result.id
    }
  }

  func stopSpeaking() {
    speechService.stop()
    speakingResultID = nil
  }

  func isSpeaking(_ result: TranslationResult) -> Bool {
    speakingResultID == result.id && speechService.isSpeaking
  }

  func isProviderEnabled(_ providerID: ProviderID) -> Bool {
    settings.configuration(for: providerID).isEnabled
  }

  func toggleProviderEnabled(_ providerID: ProviderID) {
    if isProviderEnabled(providerID) {
      disableProvider(providerID)
    } else {
      enableProvider(providerID)
    }
  }

  func togglePinned() {
    isPanelPinned.toggle()
    floatingPanel.updatePinnedState(isPinned: isPanelPinned)
  }

  func toggleExpanded() {
    isExpanded.toggle()
    floatingPanel.updateLayout()
  }

  func hideFloatingPanelIfNeeded() {
    floatingPanel.hideIfNeeded()
  }

  func hideFloatingPanel() {
    floatingPanel.hide()
  }

  private func selectionUnavailableMessage(for reason: SelectionFailureReason?) -> String {
    if reason == .accessibilityPermissionMissing || !permissionChecker.isAccessibilityTrusted {
      permissionChecker.requestAccessibilityIfNeeded(prompt: true)
      return "Grant Accessibility permission to LexiRay, then select text and press \(AppConstants.defaultHotKeyDescription) again."
    }

    if reason == .copyFailed {
      return "No readable selection. Select text again, then check Accessibility, Input Monitoring, or Automation permissions if this keeps happening."
    }

    return "Select text, then press \(AppConstants.defaultHotKeyDescription)."
  }

  private func startBatchTranslation(text: String, source: SelectionSource) {
    cancelProviderTranslationTasks()

    do {
      let batch = try pipeline.makeBatch(text: text, selectionSource: source)
      activeBatchID = batch.id
      panelState = .batch(batch)
      floatingPanel.show(activating: false, repositioning: false)

      let batchID = batch.id
      let request = batch.request
      for entry in batch.entries where entry.isTranslatable {
        startProviderTranslation(entry, batchID: batchID, request: request)
      }
    } catch {
      activeBatchID = nil
      panelState = .error(error.localizedDescription)
      floatingPanel.show(activating: false, repositioning: false)
      AppLog.translation.error("Translation failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func startProviderTranslation(_ entry: ProviderTranslationEntry, batchID: UUID, request: TranslationRequest) {
    providerTranslationTasks[entry.providerID]?.cancel()
    providerTranslationTasks[entry.providerID] = Task { @MainActor [weak self] in
      guard let self else {
        return
      }

      let updatedEntry = await self.pipeline.stream(entry, request: request) { partialEntry in
        guard !Task.isCancelled, self.activeBatchID == batchID else {
          return
        }

        self.updateBatchEntry(batchID: batchID, entry: partialEntry)
        self.floatingPanel.refreshContentLayout()
      }

      self.providerTranslationTasks[entry.providerID] = nil
      guard !Task.isCancelled, self.activeBatchID == batchID else {
        return
      }

      self.updateBatchEntry(batchID: batchID, entry: updatedEntry)
      self.floatingPanel.refreshContentLayout()

      if case let .success(result) = updatedEntry.status {
        AppLog.translation.info("Translation completed with \(result.providerName, privacy: .public)")
      } else if case let .failure(message) = updatedEntry.status {
        AppLog.translation.error("Translation failed with \(updatedEntry.providerName, privacy: .public): \(message, privacy: .public)")
      }
    }
  }

  private func disableProvider(_ providerID: ProviderID) {
    if currentResults.contains(where: { $0.providerID == providerID && $0.id == speakingResultID }) {
      stopSpeaking()
    }

    var configuration = settings.configuration(for: providerID)
    configuration.isEnabled = false
    settings.updateConfiguration(configuration)
    providerTranslationTasks[providerID]?.cancel()
    providerTranslationTasks[providerID] = nil

    guard let activeBatchID,
          case let .batch(batch) = panelState,
          let entry = batch.entries.first(where: { $0.providerID == providerID })
    else {
      return
    }

    updateBatchEntry(batchID: activeBatchID, entry: entry.updating(status: .disabled))
    floatingPanel.refreshContentLayout()
  }

  private func enableProvider(_ providerID: ProviderID) {
    let configuration = settings.configuration(for: providerID)
    guard !providerID.needsAPIKey || settings.hasAPIKey(for: providerID) else {
      updateProviderFailure(providerID, message: TranslationError.missingAPIKey.localizedDescription)
      return
    }

    var enabledConfiguration = configuration
    enabledConfiguration.isEnabled = true
    settings.updateConfiguration(enabledConfiguration)

    guard let activeBatchID,
          case let .batch(batch) = panelState,
          batch.entries.contains(where: { $0.providerID == providerID })
    else {
      return
    }

    let entry = ProviderTranslationEntry(
      providerID: providerID,
      providerName: enabledConfiguration.effectiveDisplayName,
      status: .translating
    )
    updateBatchEntry(batchID: activeBatchID, entry: entry)
    floatingPanel.refreshContentLayout()
    startProviderTranslation(
      entry,
      batchID: activeBatchID,
      request: batch.request
    )
  }

  private func updateProviderFailure(_ providerID: ProviderID, message: String) {
    guard let activeBatchID,
          case let .batch(batch) = panelState,
          let entry = batch.entries.first(where: { $0.providerID == providerID })
    else {
      return
    }

    updateBatchEntry(batchID: activeBatchID, entry: entry.updating(status: .failure(message)))
    floatingPanel.refreshContentLayout()
  }

  private func updateBatchEntry(batchID: UUID, entry: ProviderTranslationEntry) {
    guard case var .batch(batch) = panelState, batch.id == batchID else {
      return
    }

    batch.update(entry)
    panelState = .batch(batch)
  }

  private var currentResults: [TranslationResult] {
    switch panelState {
    case let .batch(batch):
      batch.successfulResults
    case let .result(result):
      [result]
    case .idle, .loading, .error:
      []
    }
  }

  private func cancelTranslationWork() {
    stopSpeaking()
    translationTask?.cancel()
    translationTask = nil
    cancelProviderTranslationTasks()
    activeBatchID = nil
  }

  private func cancelProviderTranslationTasks() {
    providerTranslationTasks.values.forEach { $0.cancel() }
    providerTranslationTasks = [:]
  }
}
