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

  let settings: SettingsStore

  private let selectionService: TextSelectionReading
  private let pipeline: TranslationPipeline
  private let hotKeyService = GlobalHotKeyService()
  private let speechService = SpeechService()
  private lazy var floatingPanel = FloatingPanelController(controller: self)
  private var translationTask: Task<Void, Never>?

  init(
    settings: SettingsStore = SettingsStore(),
    selectionService: TextSelectionReading = TextSelectionService()
  ) {
    self.settings = settings
    self.selectionService = selectionService
    pipeline = TranslationPipeline(settings: settings)
  }

  func start() {
    PermissionService.requestAccessibilityIfNeeded(prompt: false)
    hotKeyService.registerDefaultHotKey { [weak self] in
      self?.translateCurrentSelection()
    }
    AppLog.app.info("LexiRay started")
  }

  func translateCurrentSelection() {
    translationTask?.cancel()
    panelState = .loading("Reading selection...")
    floatingPanel.show()

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
        panelState = .error("Select text, then press \(AppConstants.defaultHotKeyDescription).")
        floatingPanel.show()
        return
      }

      panelState = .loading(text)
      floatingPanel.show()

      do {
        let result = try await pipeline.translate(text: text, selectionSource: selection.source)
        guard !Task.isCancelled else {
          return
        }

        panelState = .result(result)
        floatingPanel.show()
        AppLog.translation.info("Translation completed with \(result.providerName, privacy: .public)")
      } catch {
        panelState = .error(error.localizedDescription)
        floatingPanel.show()
        AppLog.translation.error("Translation failed: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  func translateManualText(_ text: String) {
    translationTask?.cancel()
    panelState = .loading(text)
    lastSelectionSource = .manual
    floatingPanel.show()

    translationTask = Task { @MainActor [weak self] in
      guard let self else {
        return
      }

      do {
        let result = try await pipeline.translate(text: text, selectionSource: .manual)
        panelState = .result(result)
        floatingPanel.show()
      } catch {
        panelState = .error(error.localizedDescription)
        floatingPanel.show()
      }
    }
  }

  func copyResultToClipboard() {
    guard case let .result(result) = panelState else {
      return
    }

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(result.translatedText, forType: .string)
  }

  func speakResult() {
    guard case let .result(result) = panelState else {
      return
    }

    speechService.speak(result.translatedText)
  }

  func togglePinned() {
    isPanelPinned.toggle()
  }

  func toggleExpanded() {
    isExpanded.toggle()
  }

  func hideFloatingPanelIfNeeded() {
    floatingPanel.hideIfNeeded()
  }
}
