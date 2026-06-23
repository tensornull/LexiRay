import AppKit
import Combine
import Foundation

@MainActor
final class LexiRayController: ObservableObject {
  static let shared = LexiRayController()

  @Published var panelState: PanelState = .idle
  @Published var isPanelPinned = false
  @Published var isExpanded = false
  @Published var panelSourceText = "" {
    didSet {
      if panelSourceText.nonEmptyTrimmed != nil {
        markPanelContentActivity()
      }
      updateHistoryNavigationForSourceChange()
      floatingPanel?.refreshContentLayout()
    }
  }

  @Published var lastSelectionSource: SelectionSource = .unavailable
  @Published var lastOCRText = ""
  @Published var selectedMainSection: MainSection = .dashboard
  @Published private(set) var appIdentity: AppIdentitySnapshot
  @Published private(set) var copyToast: CopyToast?
  @Published private(set) var speakingResultID: UUID?
  @Published private(set) var activeHistoryPositionText: String?
  @Published private(set) var hasTranslationHistory = false

  let settings: SettingsStore
  let permissionMonitor: PermissionStatusMonitor

  private let selectionService: TextSelectionReading
  private let permissionChecker: PermissionChecking
  private let pipeline: TranslationPipeline
  private let hotKeyService: HotKeyRegistering
  private let appIdentityChecker: AppIdentityChecking
  private let ocrService: OCRRecognizing
  private let ocrSelectionOverlay: OCRRegionSelecting
  private let speechService: SpeechControlling
  private let historyStore: TranslationHistoryStore
  private var floatingPanel: FloatingPanelPresenting!
  private var translationTask: Task<Void, Never>?
  private let providerTranslationTasks = ProviderTranslationTaskCoordinator()
  private var copyToastTask: Task<Void, Never>?
  private var activeBatchID: UUID?
  private var recordedHistoryMetadataByBatchID: [UUID: RecordedHistoryMetadata] = [:]
  private var autoCopiedBatchIDs: Set<UUID> = []
  private var translationHistory: [TranslationHistoryItem] {
    didSet {
      hasTranslationHistory = !translationHistory.isEmpty
      updateActiveHistoryPositionText()
    }
  }

  private var historyNavigationIndex: Int? {
    didSet {
      updateActiveHistoryPositionText()
    }
  }

  private var isRestoringHistorySource = false
  private var settingsCancellables: Set<AnyCancellable> = []

  /// Timestamp of the last time the panel held meaningful content (source text
  /// or a translation result). Used to restore the previous panel contents when
  /// the user re-summons the panel shortly after dismissing it without making a
  /// new text selection.
  private var lastPanelContentAt: Date?
  private static let panelContentRetention: TimeInterval = 300

  private struct RecordedHistoryMetadata {
    let itemID: UUID
    let createdAt: Date
  }

  init(
    settings: SettingsStore = SettingsStore(allowsMockProvider: AppRuntime.allowsMockProvider),
    selectionService: TextSelectionReading = TextSelectionService(),
    permissionChecker: PermissionChecking = SystemPermissionChecker(),
    hotKeyService: HotKeyRegistering = GlobalHotKeyService(),
    appIdentityChecker: AppIdentityChecking = AppIdentityCheckerFactory.makeDefault(),
    floatingPanelFactory: ((LexiRayController) -> FloatingPanelPresenting)? = nil,
    pipeline: TranslationPipeline? = nil,
    ocrService: OCRRecognizing? = nil,
    ocrSelectionOverlay: OCRRegionSelecting? = nil,
    historyStore: TranslationHistoryStore = TranslationHistoryStore(),
    speechService: SpeechControlling? = nil,
    permissionMonitor: PermissionStatusMonitor? = nil
  ) {
    self.settings = settings
    self.selectionService = selectionService
    self.permissionChecker = permissionChecker
    self.permissionMonitor = permissionMonitor ?? PermissionStatusMonitor(permissionChecker: permissionChecker)
    self.hotKeyService = hotKeyService
    self.appIdentityChecker = appIdentityChecker
    self.pipeline = pipeline ?? TranslationPipeline(settings: settings)
    self.ocrService = ocrService ?? OCRService()
    self.ocrSelectionOverlay = ocrSelectionOverlay ?? OCRSelectionOverlayController()
    self.speechService = speechService ?? SpeechService()
    self.historyStore = historyStore
    appIdentity = appIdentityChecker.currentSnapshot
    translationHistory = historyStore.load(limit: settings.translationHistoryLimit)
    floatingPanel = floatingPanelFactory?(self) ?? FloatingPanelController(controller: self)
    hasTranslationHistory = !translationHistory.isEmpty
    updateActiveHistoryPositionText()
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

    refreshAppIdentity()
    permissionChecker.requestAccessibilityIfNeeded(prompt: false)
    permissionMonitor.start()
    registerHotKeys()
    observeSettings()
    AppLog.app.info("LexiRay started")
  }

  func startForTesting() {
    registerHotKeys()
    observeSettings()
  }

  /// Test hook: force the panel content-retention window to be considered
  /// expired so the next no-selection summon falls back to a blank composer.
  func expirePanelContentRetentionForTesting() {
    guard lastPanelContentAt != nil else {
      return
    }
    lastPanelContentAt = Date().addingTimeInterval(-(Self.panelContentRetention + 1))
  }

  func selectDashboard() {
    selectedMainSection = .dashboard
  }

  func selectSettings() {
    selectedMainSection = .settings
  }

  func openSettingsFromFloatingPanel() {
    selectSettings()
    hideFloatingPanelIfNeeded()
  }

  func translateCurrentSelection() {
    guard preparePermissionSensitiveWorkflow() else {
      return
    }

    translationTask?.cancel()
    translationTask = nil

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
        translationTask = nil
        showSelectionFallback(for: selection.failureReason)
        return
      }

      cancelTranslationWork(cancelSelectionTask: false)
      translationTask = nil
      isExpanded = false
      panelSourceText = text
      panelState = .loading(PanelLoadingState(title: "Translating...", preview: text))
      floatingPanel.show(activating: false, repositioning: false)
      await Task.yield()

      startBatchTranslation(text: text, source: selection.source, bypassCache: true)
    }
  }

  func translateManualText(_ text: String) {
    translate(text: text, source: .manual)
  }

  func submitPanelSourceText() {
    guard let text = panelSourceText.nonEmptyTrimmed else {
      return
    }

    historyNavigationIndex = nil
    translate(text: text, source: .manual)
  }

  func clearPanelSourceText() {
    historyNavigationIndex = nil
    panelSourceText = ""
  }

  func translateOCRRegion() {
    guard preparePermissionSensitiveWorkflow() else {
      return
    }

    cancelTranslationWork()
    isExpanded = false
    panelSourceText = ""
    panelState = .loading(PanelLoadingState(title: "Drag to select an OCR region...", preview: nil))
    lastSelectionSource = .ocr
    floatingPanel.hide()

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
    panelSourceText = ""
    panelState = .loading(PanelLoadingState(title: "Recognizing text...", preview: nil))

    translationTask = Task { @MainActor [weak self] in
      guard let self else {
        return
      }

      do {
        try? await Task.sleep(nanoseconds: 120_000_000)
        guard !Task.isCancelled else {
          return
        }

        let text = try await ocrService.captureAndRecognizeText(in: rect)
        guard !Task.isCancelled else {
          return
        }

        lastOCRText = text
        await translateRecognizedText(text)
      } catch {
        panelState = .error(error.localizedDescription)
        floatingPanel.show(activating: false, repositioning: false)
        AppLog.ocr.error("OCR failed: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  private func translateRecognizedText(_ text: String) async {
    lastSelectionSource = .ocr
    panelSourceText = text
    panelState = .loading(PanelLoadingState(title: "Translating OCR text...", preview: text))
    floatingPanel.show(activating: false, repositioning: false)
    await Task.yield()

    startBatchTranslation(text: text, source: .ocr, bypassCache: true)
  }

  private func translate(text: String, source: SelectionSource) {
    guard let text = text.nonEmptyTrimmed else {
      return
    }

    cancelTranslationWork()
    isExpanded = false
    panelSourceText = text
    panelState = .loading(PanelLoadingState(title: "Translating...", preview: text))
    lastSelectionSource = source
    floatingPanel.show(activating: false, repositioning: false)

    startBatchTranslation(text: text, source: source, bypassCache: true)
  }

  func copyResultToClipboard() {
    guard let result = currentResults.first else {
      return
    }

    copyResultToClipboard(result, surface: .floatingPanel)
  }

  func copyResultToClipboard(_ result: TranslationResult, surface: CopyToastSurface = .floatingPanel) {
    copyResultToClipboard(result, format: settings.defaultCopyFormat, surface: surface)
  }

  func copyResultToClipboard(
    _ result: TranslationResult,
    format: CopyFormat,
    surface: CopyToastSurface = .floatingPanel
  ) {
    TranslationPasteboardWriter.write(result: result, format: format)
    settings.defaultCopyFormat = format
    showCopyToast(surface: surface)
  }

  func refreshAppIdentity() {
    let currentIdentity = appIdentityChecker.currentSnapshot
    guard appIdentity != currentIdentity else {
      return
    }
    appIdentity = currentIdentity
  }

  func copyAppDiagnosticsToClipboard(surface: CopyToastSurface = .mainWindow) {
    refreshAppIdentity()
    let diagnostics = [
      appIdentity.diagnosticsText,
      "Accessibility trusted: \(PermissionService.isAccessibilityTrusted)",
      "Screen Recording trusted: \(PermissionService.isScreenCaptureTrusted)"
    ].joined(separator: "\n")
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(diagnostics, forType: .string)
    showCopyToast(surface: surface)
  }

  func openInstallLocation() {
    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
  }

  func openPrivacySettings() {
    PermissionService.openPrivacySettings()
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

  func isProviderEnabled(_ configurationID: String) -> Bool {
    settings.configuration(for: configurationID)?.isEnabled ?? false
  }

  func toggleProviderEnabled(_ configurationID: String) {
    if isProviderEnabled(configurationID) {
      disableProvider(configurationID)
    } else {
      enableProvider(configurationID)
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

  func refreshFloatingPanelLayout() {
    floatingPanel.refreshContentLayout()
  }

  func showPreviousHistory() -> Bool {
    guard canNavigateTranslationHistory else {
      return false
    }

    let index: Int
    if let historyNavigationIndex {
      index = max(0, historyNavigationIndex - 1)
    } else if let currentHistoryIndex = currentPresentedHistoryIndex {
      index = max(0, currentHistoryIndex - 1)
    } else {
      index = translationHistory.count - 1
    }

    restoreHistory(at: index)
    return true
  }

  func showNextHistory() -> Bool {
    guard let historyNavigationIndex = historyNavigationIndex ?? currentPresentedHistoryIndex else {
      return false
    }

    if historyNavigationIndex < translationHistory.count - 1 {
      restoreHistory(at: historyNavigationIndex + 1)
    } else {
      restoreBlankComposerAfterHistory()
    }

    return true
  }

  var canNavigateTranslationHistory: Bool {
    !translationHistory.isEmpty && (panelSourceText.isEmpty || historyNavigationIndex != nil || currentPresentedHistoryIndex != nil)
  }

  private func showSelectionFallback(for reason: SelectionFailureReason?) {
    if reason == .accessibilityPermissionMissing {
      showSelectionPermissionError()
      return
    }

    // No current text selection: if the panel still holds recent content from a
    // previous translation (within the retention window), restore it instead of
    // clearing to a blank composer.
    if shouldRestoreRetainedPanelContent {
      showRetainedPanel()
      return
    }

    showBlankComposer()
  }

  /// Whether the panel currently holds recent, non-empty content that should be
  /// restored on re-summon rather than wiped.
  private var shouldRestoreRetainedPanelContent: Bool {
    guard let lastPanelContentAt,
          Date().timeIntervalSince(lastPanelContentAt) <= Self.panelContentRetention
    else {
      return false
    }

    if panelSourceText.nonEmptyTrimmed != nil {
      return true
    }

    switch panelState {
    case .batch, .result:
      return true
    case .idle, .loading, .error:
      return false
    }
  }

  /// Re-show the panel with its existing contents untouched, refreshing the
  /// retention timestamp so the content keeps living while the user interacts.
  private func showRetainedPanel() {
    markPanelContentActivity()
    floatingPanel.show(activating: true, repositioning: false)
  }

  /// Record that the panel is holding meaningful content right now.
  private func markPanelContentActivity() {
    lastPanelContentAt = Date()
  }

  private func preparePermissionSensitiveWorkflow() -> Bool {
    refreshAppIdentity()
    guard let blockingIssue = appIdentity.blockingIssue else {
      return true
    }

    showAppIdentityError(blockingIssue.message)
    return false
  }

  private func showAppIdentityError(_ message: String) {
    cancelTranslationWork()
    isExpanded = false
    panelSourceText = ""
    lastSelectionSource = .unavailable
    panelState = .error(message)
    floatingPanel.show(activating: false, repositioning: false)
    AppLog.app.error("Blocked permission-sensitive workflow: \(message, privacy: .public)")
  }

  private func showSelectionPermissionError() {
    cancelTranslationWork(cancelSelectionTask: false)
    isExpanded = false
    panelSourceText = ""
    lastSelectionSource = .unavailable
    panelState = .error(selectionUnavailableMessage(for: .accessibilityPermissionMissing))
    floatingPanel.show(activating: false, repositioning: false)
  }

  private func showBlankComposer() {
    cancelTranslationWork(cancelSelectionTask: false)
    isExpanded = false
    historyNavigationIndex = nil
    isRestoringHistorySource = true
    panelSourceText = ""
    isRestoringHistorySource = false
    lastSelectionSource = .unavailable
    panelState = .idle
    lastPanelContentAt = nil
    floatingPanel.show(activating: true, repositioning: false)
  }

  private func selectionUnavailableMessage(for reason: SelectionFailureReason?) -> String {
    if reason == .accessibilityPermissionMissing {
      permissionChecker.requestAccessibilityIfNeeded(prompt: true)
      return "Grant Accessibility permission to LexiRay, then select text and press \(settings.translateHotKey.displayString) again."
    }

    if reason == .copyFailed {
      return "No readable selection. Select text again, then check Accessibility, Input Monitoring, or Automation permissions if this keeps happening."
    }

    return "Select text, then press \(settings.translateHotKey.displayString)."
  }

  private func registerHotKeys() {
    registerHotKeys(translateHotKey: settings.translateHotKey, ocrHotKey: settings.ocrHotKey)
  }

  private func registerHotKeys(translateHotKey: HotKeyConfiguration, ocrHotKey: HotKeyConfiguration) {
    hotKeyService.registerDefaultHotKeys(
      translateHotKey: translateHotKey,
      ocrHotKey: ocrHotKey,
      translate: { [weak self] in
        self?.translateCurrentSelection()
      },
      ocr: { [weak self] in
        self?.translateOCRRegion()
      }
    )
  }

  private func observeSettings() {
    guard settingsCancellables.isEmpty else {
      return
    }

    settings.$translateHotKey
      .combineLatest(settings.$ocrHotKey)
      .dropFirst()
      .sink { [weak self] translateHotKey, ocrHotKey in
        self?.registerHotKeys(translateHotKey: translateHotKey, ocrHotKey: ocrHotKey)
      }
      .store(in: &settingsCancellables)

    settings.$showsMenuBarIcon
      .dropFirst()
      .sink { showsMenuBarIcon in
        AppWindowPresenter.refreshDockVisibilitySoon(showsMenuBarIcon: showsMenuBarIcon)
      }
      .store(in: &settingsCancellables)

    settings.$translationHistoryLimit
      .dropFirst()
      .sink { [weak self] limit in
        self?.pruneTranslationHistory(limit: limit)
      }
      .store(in: &settingsCancellables)

    permissionMonitor.refreshEvents
      .sink { [weak self] in
        self?.refreshAppIdentity()
      }
      .store(in: &settingsCancellables)
  }

  private func startBatchTranslation(text: String, source: SelectionSource, bypassCache: Bool) {
    cancelProviderTranslationTasks()
    recordedHistoryMetadataByBatchID.removeAll(keepingCapacity: true)

    do {
      let batch = try pipeline.makeBatch(text: text, selectionSource: source)
      panelSourceText = batch.request.text
      activeBatchID = batch.id
      panelState = .batch(batch)
      markPanelContentActivity()
      floatingPanel.show(activating: false, repositioning: false)

      let batchID = batch.id
      let request = batch.request
      recordHistoryIfNeeded(for: batch)
      for entry in batch.entries where entry.isTranslatable {
        startProviderTranslation(entry, batchID: batchID, request: request, bypassCache: bypassCache)
      }
    } catch {
      activeBatchID = nil
      panelState = .error(error.localizedDescription)
      floatingPanel.show(activating: false, repositioning: false)
      AppLog.translation.error("Translation failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func startProviderTranslation(
    _ entry: ProviderTranslationEntry,
    batchID: UUID,
    request: TranslationRequest,
    bypassCache: Bool = false
  ) {
    providerTranslationTasks.start(configurationID: entry.providerConfigurationID) { [weak self] in
      guard let self else {
        return
      }

      let updatedEntry = await pipeline.stream(entry, request: request, bypassCache: bypassCache) { partialEntry in
        guard !Task.isCancelled, self.activeBatchID == batchID else {
          return
        }

        self.updateBatchEntry(batchID: batchID, entry: partialEntry)
        self.floatingPanel.refreshContentLayout()
      }

      guard !Task.isCancelled, activeBatchID == batchID else {
        return
      }

      updateBatchEntry(batchID: batchID, entry: updatedEntry)
      floatingPanel.refreshContentLayout()

      if case let .success(result) = updatedEntry.status {
        AppLog.translation.info("Translation completed with \(result.providerName, privacy: .public)")
      } else if case let .failure(message) = updatedEntry.status {
        AppLog.translation.error("Translation failed with \(updatedEntry.providerName, privacy: .public): \(message, privacy: .public)")
      }
    }
  }

  private func disableProvider(_ configurationID: String) {
    if currentResults.contains(where: { $0.providerConfigurationID == configurationID && $0.id == speakingResultID }) {
      stopSpeaking()
    }

    guard var configuration = settings.configuration(for: configurationID) else {
      return
    }
    configuration.isEnabled = false
    settings.updateConfiguration(configuration)
    providerTranslationTasks.cancel(configurationID)

    guard let activeBatchID,
          case let .batch(batch) = panelState,
          let entry = batch.entries.first(where: { $0.providerConfigurationID == configurationID })
    else {
      return
    }

    updateBatchEntry(batchID: activeBatchID, entry: entry.updating(status: .disabled))
    floatingPanel.refreshContentLayout()
  }

  private func enableProvider(_ configurationID: String) {
    guard let configuration = settings.configuration(for: configurationID) else {
      return
    }
    guard !configuration.providerID.needsAPIKey || settings.hasAPIKey(forConfigurationID: configurationID) else {
      updateProviderFailure(configurationID, message: TranslationError.missingAPIKey.localizedDescription)
      return
    }

    var enabledConfiguration = configuration
    enabledConfiguration.isEnabled = true
    settings.updateConfiguration(enabledConfiguration)

    guard let activeBatchID,
          case let .batch(batch) = panelState,
          batch.entries.contains(where: { $0.providerConfigurationID == configurationID })
    else {
      return
    }

    let entry = ProviderTranslationEntry(
      providerConfigurationID: configurationID,
      providerID: enabledConfiguration.providerID,
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

  private func updateProviderFailure(_ configurationID: String, message: String) {
    guard let activeBatchID,
          case let .batch(batch) = panelState,
          let entry = batch.entries.first(where: { $0.providerConfigurationID == configurationID })
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
    recordHistoryIfNeeded(for: batch)
    autoCopyFirstProviderResultIfNeeded(in: batch)
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

  private func cancelTranslationWork(cancelSelectionTask: Bool = true) {
    stopSpeaking()
    if cancelSelectionTask {
      translationTask?.cancel()
      translationTask = nil
    }
    cancelProviderTranslationTasks()
    activeBatchID = nil
  }

  private func cancelProviderTranslationTasks() {
    providerTranslationTasks.cancelAll()
  }

  private func recordHistoryIfNeeded(for batch: TranslationBatch) {
    let metadata = recordedHistoryMetadataByBatchID[batch.id] ?? RecordedHistoryMetadata(
      itemID: UUID(),
      createdAt: Date()
    )
    guard let item = TranslationHistoryItem(
      recordableBatch: batch,
      id: metadata.itemID,
      createdAt: metadata.createdAt
    )
    else {
      return
    }

    let hasRecordedBatch = recordedHistoryMetadataByBatchID[batch.id] != nil
    if hasRecordedBatch,
       translationHistory.first(where: { $0.id == item.id }) == item
    {
      return
    }

    if hasRecordedBatch {
      translationHistory = historyStore.upsert(item, to: translationHistory, limit: settings.translationHistoryLimit)
    } else {
      translationHistory = historyStore.append(item, to: translationHistory, limit: settings.translationHistoryLimit)
    }
    recordedHistoryMetadataByBatchID[batch.id] = metadata
    historyNavigationIndex = nil
  }

  private func autoCopyFirstProviderResultIfNeeded(in batch: TranslationBatch) {
    guard settings.autoCopyMode == .firstProviderSuccess,
          activeBatchID == batch.id,
          !autoCopiedBatchIDs.contains(batch.id),
          let result = firstProviderOrderedAutoCopyResult(in: batch)
    else {
      return
    }

    TranslationPasteboardWriter.write(result: result, format: settings.defaultCopyFormat)
    autoCopiedBatchIDs.insert(batch.id)
    showCopyToast(surface: .floatingPanel)
  }

  private func firstProviderOrderedAutoCopyResult(in batch: TranslationBatch) -> TranslationResult? {
    for entry in batch.entries {
      switch entry.status {
      case .disabled, .failure:
        continue
      case .translating, .streaming:
        return nil
      case let .success(result):
        return result
      }
    }

    return nil
  }

  private func restoreHistory(at index: Int) {
    guard translationHistory.indices.contains(index) else {
      return
    }

    cancelTranslationWork()
    historyNavigationIndex = index
    let item = translationHistory[index]
    isRestoringHistorySource = true
    panelSourceText = item.request.text
    isRestoringHistorySource = false
    lastSelectionSource = item.request.selectionSource
    panelState = .batch(item.restoredBatch())
    markPanelContentActivity()
    floatingPanel.refreshContentLayout()
  }

  private func restoreBlankComposerAfterHistory() {
    cancelTranslationWork()
    historyNavigationIndex = nil
    isRestoringHistorySource = true
    panelSourceText = ""
    isRestoringHistorySource = false
    lastSelectionSource = .unavailable
    panelState = .idle
    floatingPanel.refreshContentLayout()
  }

  private var currentPresentedHistoryIndex: Int? {
    guard let presentedRequestText,
          presentedRequestText == panelSourceText,
          !isActiveBatchInFlight
    else {
      return nil
    }

    return translationHistory.lastIndex { item in
      item.request.text == presentedRequestText
    }
  }

  private var isActiveBatchInFlight: Bool {
    guard let activeBatchID,
          case let .batch(batch) = panelState,
          batch.id == activeBatchID
    else {
      return false
    }

    return batch.entries.contains { $0.status.isInFlight }
  }

  private var presentedRequestText: String? {
    switch panelState {
    case let .batch(batch):
      batch.request.text
    case let .result(result):
      result.request.text
    case .idle, .loading, .error:
      nil
    }
  }

  private func pruneTranslationHistory(limit: Int) {
    translationHistory = historyStore.prune(translationHistory, limit: limit)
    guard let historyNavigationIndex else {
      return
    }

    if translationHistory.indices.contains(historyNavigationIndex) {
      return
    }

    self.historyNavigationIndex = translationHistory.isEmpty ? nil : translationHistory.count - 1
  }

  private func updateHistoryNavigationForSourceChange() {
    guard !isRestoringHistorySource,
          let historyNavigationIndex,
          translationHistory.indices.contains(historyNavigationIndex),
          panelSourceText != translationHistory[historyNavigationIndex].request.text
    else {
      return
    }

    self.historyNavigationIndex = nil
  }

  private func updateActiveHistoryPositionText() {
    guard let historyNavigationIndex,
          translationHistory.indices.contains(historyNavigationIndex)
    else {
      activeHistoryPositionText = nil
      return
    }

    activeHistoryPositionText = "History \(historyNavigationIndex + 1)/\(translationHistory.count)"
  }

  private func showCopyToast(surface: CopyToastSurface) {
    copyToastTask?.cancel()
    copyToast = CopyToast(message: "Copied", surface: surface)
    copyToastTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 1_300_000_000)
      guard !Task.isCancelled else {
        return
      }
      self?.copyToast = nil
    }
  }
}

private extension ProviderTranslationStatus {
  var isInFlight: Bool {
    switch self {
    case .translating, .streaming:
      true
    case .disabled, .success, .failure:
      false
    }
  }
}
