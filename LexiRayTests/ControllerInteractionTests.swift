import AppKit
import Carbon
@testable import LexiRay
import XCTest

@MainActor
final class ControllerInteractionTests: XCTestCase {
  func testTranslateSelectionReadsBeforeShowingPanel() async {
    let selectionReader = BlockingSelectionReader()
    let panel = MockFloatingPanelPresenter()
    let controller = makeController(selectionReader: selectionReader, panel: panel)

    controller.translateCurrentSelection()

    await waitUntil { selectionReader.didStart }
    XCTAssertTrue(panel.events.isEmpty)

    selectionReader.resume(with: SelectionReadResult(text: "hello", source: .simulatedCopy))

    await waitUntil { !panel.events.isEmpty }
    XCTAssertEqual(panel.events.first, .show(activating: false, repositioning: true))
    XCTAssertEqual(controller.lastSelectionSource, .simulatedCopy)
    XCTAssertEqual(controller.panelSourceText, "hello")
  }

  func testUnavailableSelectionPromptsForAccessibilityWhenNeeded() async {
    let panel = MockFloatingPanelPresenter()
    let permissions = MockPermissionChecker(isAccessibilityTrusted: false)
    let controller = makeController(
      selectionReader: ImmediateSelectionReader(result: .unavailable),
      panel: panel,
      permissions: permissions
    )

    controller.translateCurrentSelection()

    await waitUntil { !panel.events.isEmpty }

    guard case let .error(message) = controller.panelState else {
      return XCTFail("Expected error state")
    }

    XCTAssertTrue(message.contains("Grant Accessibility permission"))
    XCTAssertEqual(permissions.promptRequests, [true])
    XCTAssertEqual(panel.events.first, .show(activating: false, repositioning: true))
  }

  func testPinnedAndCloseActionsReachPanelPresenter() {
    let panel = MockFloatingPanelPresenter()
    let controller = makeController(selectionReader: ImmediateSelectionReader(result: .unavailable), panel: panel)

    controller.togglePinned()
    controller.hideFloatingPanelIfNeeded()
    controller.hideFloatingPanel()
    controller.togglePinned()

    XCTAssertEqual(panel.pinnedStates, [true, false])
    XCTAssertEqual(panel.hideIfNeededCount, 1)
    XCTAssertEqual(panel.hideCount, 1)
  }

  func testExpandedActionUpdatesPanelLayout() {
    let panel = MockFloatingPanelPresenter()
    let controller = makeController(selectionReader: ImmediateSelectionReader(result: .unavailable), panel: panel)

    controller.toggleExpanded()

    XCTAssertEqual(panel.updateLayoutCount, 1)
  }

  func testShortResultUsesCompactFloatingPanelHeight() {
    let panel = MockFloatingPanelPresenter()
    let controller = makeController(selectionReader: ImmediateSelectionReader(result: .unavailable), panel: panel)
    controller.panelState = .result(makeTranslationResult(text: "你好"))

    let size = FloatingPanelController.contentSize(for: controller)

    XCTAssertEqual(size.width, 660)
    XCTAssertLessThanOrEqual(size.height, 410)
  }

  func testLongResultUsesTallerFloatingPanelHeight() {
    let panel = MockFloatingPanelPresenter()
    let controller = makeController(selectionReader: ImmediateSelectionReader(result: .unavailable), panel: panel)
    controller.panelState = .result(makeTranslationResult(text: String(repeating: "这是一段较长的翻译结果，用于验证悬浮窗会按内容增加高度。\n", count: 10)))

    let shortHeight = FloatingPanelController.contentSize(for: makeController(selectionReader: ImmediateSelectionReader(result: .unavailable), panel: MockFloatingPanelPresenter())).height
    let longHeight = FloatingPanelController.contentSize(for: controller).height

    XCTAssertGreaterThan(longHeight, shortHeight)
    XCTAssertLessThanOrEqual(longHeight, FloatingPanelController.maximumContentHeight(isExpanded: false))
  }

  func testBatchHeightGrowsWithProviderContent() {
    let panel = MockFloatingPanelPresenter()
    let controller = makeController(selectionReader: ImmediateSelectionReader(result: .unavailable), panel: panel)
    let request = TranslationRequest(text: "hello", sourceLanguage: "en", targetLanguage: "zh-Hans", selectionSource: .manual)
    let shortBatch = TranslationBatch(
      request: request,
      entries: [
        ProviderTranslationEntry(providerConfigurationID: "short", providerID: .mock, providerName: "Short", status: .success(makeTranslationResult(text: "短句")))
      ]
    )
    let longBatch = TranslationBatch(
      request: request,
      entries: [
        ProviderTranslationEntry(providerConfigurationID: "short", providerID: .mock, providerName: "Short", status: .success(makeTranslationResult(text: "短句"))),
        ProviderTranslationEntry(providerConfigurationID: "long", providerID: .systemDictionary, providerName: "Long", status: .success(makeTranslationResult(text: String(repeating: "Long translated content wraps across multiple visible lines. ", count: 18))))
      ]
    )

    controller.panelState = .batch(shortBatch)
    let shortHeight = FloatingPanelController.contentSize(for: controller).height
    controller.panelState = .batch(longBatch)
    let longHeight = FloatingPanelController.contentSize(for: controller).height

    XCTAssertGreaterThan(longHeight, shortHeight)
    XCTAssertLessThanOrEqual(longHeight, FloatingPanelController.maximumContentHeight(isExpanded: false))
  }

  func testEmptyPanelSourceSubmitDoesNotStartTranslation() {
    let panel = MockFloatingPanelPresenter()
    let controller = makeController(selectionReader: ImmediateSelectionReader(result: .unavailable), panel: panel)

    controller.panelSourceText = "   "
    controller.submitPanelSourceText()

    XCTAssertTrue(panel.events.isEmpty)
    XCTAssertEqual(controller.panelState, .idle)
  }

  func testSubmitPanelSourceTextRetranslatesEditedTextAsManual() async {
    let panel = MockFloatingPanelPresenter()
    let controller = makeController(selectionReader: ImmediateSelectionReader(result: .unavailable), panel: panel)

    controller.panelSourceText = " edited source "
    controller.submitPanelSourceText()

    await waitUntil {
      guard case let .batch(batch) = controller.panelState else {
        return false
      }
      return batch.successfulResults.count == 1
    }

    guard case let .batch(batch) = controller.panelState else {
      return XCTFail("Expected batch state")
    }

    XCTAssertEqual(batch.request.text, "edited source")
    XCTAssertEqual(batch.request.selectionSource, .manual)
    XCTAssertEqual(controller.panelSourceText, "edited source")
  }

  func testManualTranslationUpdatesBatchResult() async {
    let panel = MockFloatingPanelPresenter()
    let controller = makeController(selectionReader: ImmediateSelectionReader(result: .unavailable), panel: panel)

    controller.translateManualText("hello")

    await waitUntil {
      guard case let .batch(batch) = controller.panelState else {
        return false
      }
      return batch.successfulResults.count == 1
    }

    guard case let .batch(batch) = controller.panelState else {
      return XCTFail("Expected batch state")
    }

    XCTAssertEqual(batch.entries.map(\.providerID), [.mock, .openAIResponses, .openAIChatCompletions, .anthropicMessages, .geminiGenerateContent, .systemDictionary])
    XCTAssertEqual(batch.successfulResults.first?.providerName, "Mock")
    XCTAssertTrue(batch.entries.dropFirst().allSatisfy(\.status.isDisabled))
    XCTAssertEqual(controller.panelSourceText, "hello")
  }

  func testStreamingPartialRefreshesPanelWithoutRepositioningShow() async throws {
    let panel = MockFloatingPanelPresenter()
    let defaults = try XCTUnwrap(UserDefaults(suiteName: "LexiRayControllerTests-\(UUID().uuidString)"))
    let settings = SettingsStore(
      defaults: defaults,
      providerFileStore: makeProviderFileStore(),
      allowsMockProvider: true
    )
    enableOnly([.mock], in: settings)
    let pipeline = TranslationPipeline(settings: settings, providerFactory: { _ in
      StreamingTestProvider()
    })
    let controller = LexiRayController(
      settings: settings,
      selectionService: ImmediateSelectionReader(result: .unavailable),
      permissionChecker: MockPermissionChecker(isAccessibilityTrusted: true),
      floatingPanelFactory: { _ in panel },
      pipeline: pipeline
    )

    controller.translateManualText("hello")

    await waitUntil {
      guard case let .batch(batch) = controller.panelState,
            case let .streaming(text) = batch.entries.first?.status
      else {
        return false
      }
      return text == "partial"
    }

    XCTAssertEqual(panel.events.filter(\.isRepositioningShow).count, 1)
    XCTAssertGreaterThanOrEqual(panel.refreshContentLayoutCount, 1)

    await waitUntil {
      guard case let .batch(batch) = controller.panelState else {
        return false
      }
      return batch.successfulResults.first?.translatedText == "complete"
    }

    XCTAssertEqual(panel.events.filter(\.isRepositioningShow).count, 1)
  }

  func testCopySpecificBatchResult() {
    let panel = MockFloatingPanelPresenter()
    let controller = makeController(selectionReader: ImmediateSelectionReader(result: .unavailable), panel: panel)
    let request = TranslationRequest(
      text: "hello",
      sourceLanguage: "en",
      targetLanguage: "zh-Hans",
      selectionSource: .manual
    )
    let first = TranslationResult(
      request: request,
      providerID: .mock,
      providerName: "First",
      translatedText: "one"
    )
    let second = TranslationResult(
      request: request,
      providerID: .systemDictionary,
      providerName: "Second",
      translatedText: "two"
    )

    controller.panelState = .batch(
      TranslationBatch(
        request: request,
        entries: [
          ProviderTranslationEntry(providerConfigurationID: ProviderID.mock.rawValue, providerID: .mock, providerName: "First", status: .success(first)),
          ProviderTranslationEntry(providerConfigurationID: ProviderID.systemDictionary.rawValue, providerID: .systemDictionary, providerName: "Second", status: .success(second))
        ]
      )
    )

    controller.copyResultToClipboard(second)

    XCTAssertEqual(NSPasteboard.general.string(forType: .string), "two")
  }

  func testCopySpecificFormatUpdatesDefaultCopyFormat() {
    let panel = MockFloatingPanelPresenter()
    let controller = makeController(selectionReader: ImmediateSelectionReader(result: .unavailable), panel: panel)
    let result = TranslationResult(
      request: TranslationRequest(
        text: "hello",
        sourceLanguage: "en",
        targetLanguage: "zh-Hans",
        selectionSource: .manual
      ),
      providerID: .mock,
      providerName: "Mock",
      translatedText: "<p>Hello <strong>world</strong></p>"
    )

    controller.copyResultToClipboard(result, format: .html)

    XCTAssertEqual(controller.settings.defaultCopyFormat, .html)
    XCTAssertTrue(NSPasteboard.general.string(forType: .html)?.contains("Hello") == true)
    XCTAssertTrue(NSPasteboard.general.string(forType: .string)?.contains("Hello world") == true)
  }

  func testToggleSpeakTracksCurrentResultAndStops() {
    let panel = MockFloatingPanelPresenter()
    let speech = MockSpeechService()
    let controller = makeController(
      selectionReader: ImmediateSelectionReader(result: .unavailable),
      panel: panel,
      speechService: speech
    )
    let result = TranslationResult(
      request: TranslationRequest(
        text: "hello",
        sourceLanguage: "en",
        targetLanguage: "zh-Hans",
        selectionSource: .manual
      ),
      providerID: .mock,
      providerName: "Mock",
      translatedText: "你好"
    )

    controller.toggleSpeak(result)

    XCTAssertTrue(controller.isSpeaking(result))
    XCTAssertEqual(speech.speakRequests.first?.text, "你好")
    XCTAssertEqual(speech.speakRequests.first?.languageCode, "zh-Hans")

    controller.toggleSpeak(result)

    XCTAssertFalse(controller.isSpeaking(result))
    XCTAssertEqual(speech.stopCount, 1)
  }

  func testSwitchingSpeechStopsPreviousResult() {
    let panel = MockFloatingPanelPresenter()
    let speech = MockSpeechService()
    let controller = makeController(
      selectionReader: ImmediateSelectionReader(result: .unavailable),
      panel: panel,
      speechService: speech
    )
    let request = TranslationRequest(text: "hello", sourceLanguage: "en", targetLanguage: "zh-Hans", selectionSource: .manual)
    let first = TranslationResult(request: request, providerID: .mock, providerName: "First", translatedText: "one")
    let second = TranslationResult(request: request, providerID: .systemDictionary, providerName: "Second", translatedText: "two")

    controller.toggleSpeak(first)
    controller.toggleSpeak(second)

    XCTAssertFalse(controller.isSpeaking(first))
    XCTAssertTrue(controller.isSpeaking(second))
    XCTAssertEqual(speech.stopCount, 1)
    XCTAssertEqual(speech.speakRequests.map(\.text), ["one", "two"])
  }

  func testEmptySpeechDoesNotStart() {
    let panel = MockFloatingPanelPresenter()
    let speech = MockSpeechService()
    let controller = makeController(
      selectionReader: ImmediateSelectionReader(result: .unavailable),
      panel: panel,
      speechService: speech
    )
    let result = TranslationResult(
      request: TranslationRequest(text: "hello", sourceLanguage: "en", targetLanguage: "zh-Hans", selectionSource: .manual),
      providerID: .mock,
      providerName: "Mock",
      translatedText: "   "
    )

    controller.toggleSpeak(result)

    XCTAssertFalse(controller.isSpeaking(result))
    XCTAssertTrue(speech.speakRequests.isEmpty)
  }

  func testProviderToggleDisablesStreamingProvider() async throws {
    let panel = MockFloatingPanelPresenter()
    let defaults = try XCTUnwrap(UserDefaults(suiteName: "LexiRayControllerTests-\(UUID().uuidString)"))
    let settings = SettingsStore(
      defaults: defaults,
      providerFileStore: makeProviderFileStore(),
      allowsMockProvider: true
    )
    enableOnly([.mock], in: settings)
    let pipeline = TranslationPipeline(settings: settings, providerFactory: { _ in
      StreamingTestProvider()
    })
    let controller = LexiRayController(
      settings: settings,
      selectionService: ImmediateSelectionReader(result: .unavailable),
      permissionChecker: MockPermissionChecker(isAccessibilityTrusted: true),
      floatingPanelFactory: { _ in panel },
      pipeline: pipeline
    )

    controller.translateManualText("hello")
    await waitUntil {
      guard case let .batch(batch) = controller.panelState,
            case .streaming = batch.entries.first(where: { $0.providerID == .mock })?.status
      else {
        return false
      }
      return true
    }

    controller.toggleProviderEnabled(ProviderID.mock.rawValue)

    guard case let .batch(batch) = controller.panelState,
          let entry = batch.entries.first(where: { $0.providerID == .mock })
    else {
      return XCTFail("Expected batch state")
    }

    XCTAssertFalse(settings.configuration(for: .mock).isEnabled)
    XCTAssertTrue(entry.status.isDisabled)
  }

  func testProviderToggleEnablesDisabledProviderForCurrentRequest() async throws {
    let panel = MockFloatingPanelPresenter()
    let defaults = try XCTUnwrap(UserDefaults(suiteName: "LexiRayControllerTests-\(UUID().uuidString)"))
    let settings = SettingsStore(
      defaults: defaults,
      providerFileStore: makeProviderFileStore(),
      allowsMockProvider: true
    )
    enableOnly([], in: settings)
    let pipeline = TranslationPipeline(settings: settings, providerFactory: { _ in
      StreamingTestProvider()
    })
    let controller = LexiRayController(
      settings: settings,
      selectionService: ImmediateSelectionReader(result: .unavailable),
      permissionChecker: MockPermissionChecker(isAccessibilityTrusted: true),
      floatingPanelFactory: { _ in panel },
      pipeline: pipeline
    )

    controller.translateManualText("hello")
    await waitUntil {
      guard case let .batch(batch) = controller.panelState else {
        return false
      }
      return batch.entries.allSatisfy(\.status.isDisabled)
    }

    controller.toggleProviderEnabled(ProviderID.mock.rawValue)

    await waitUntil {
      guard case let .batch(batch) = controller.panelState else {
        return false
      }
      return batch.successfulResults.first?.providerID == .mock
    }

    XCTAssertTrue(settings.configuration(for: .mock).isEnabled)
  }

  func testProviderToggleMissingAPIKeyDoesNotPersistEnabled() async throws {
    let panel = MockFloatingPanelPresenter()
    let defaults = try XCTUnwrap(UserDefaults(suiteName: "LexiRayControllerTests-\(UUID().uuidString)"))
    let settings = SettingsStore(
      defaults: defaults,
      providerFileStore: makeProviderFileStore(),
      allowsMockProvider: true
    )
    enableOnly([], in: settings)
    let controller = LexiRayController(
      settings: settings,
      selectionService: ImmediateSelectionReader(result: .unavailable),
      permissionChecker: MockPermissionChecker(isAccessibilityTrusted: true),
      floatingPanelFactory: { _ in panel }
    )

    controller.translateManualText("hello")
    await waitUntil {
      guard case .batch = controller.panelState else {
        return false
      }
      return true
    }

    controller.toggleProviderEnabled(ProviderID.openAIResponses.rawValue)

    guard case let .batch(batch) = controller.panelState,
          let entry = batch.entries.first(where: { $0.providerID == .openAIResponses }),
          case let .failure(message) = entry.status
    else {
      return XCTFail("Expected provider failure")
    }

    XCTAssertFalse(settings.configuration(for: .openAIResponses).isEnabled)
    XCTAssertTrue(message.contains("API key"))
  }

  func testFloatingPanelStyleDoesNotUseSystemTitlebar() {
    let style = FloatingPanelController.panelStyleMask

    XCTAssertTrue(style.contains(.nonactivatingPanel))
    XCTAssertFalse(style.contains(.titled))
    XCTAssertFalse(style.contains(.fullSizeContentView))
  }

  func testFloatingPanelSettingsActionSelectsSettingsAndHidesIfNeeded() {
    let panel = MockFloatingPanelPresenter()
    let controller = makeController(selectionReader: ImmediateSelectionReader(result: .unavailable), panel: panel)

    controller.openSettingsFromFloatingPanel()

    XCTAssertEqual(controller.selectedMainSection, .settings)
    XCTAssertEqual(panel.hideIfNeededCount, 1)
  }

  func testHotKeyChangeReregistersHotKeys() {
    let panel = MockFloatingPanelPresenter()
    let hotKeys = MockHotKeyService()
    let controller = makeController(
      selectionReader: ImmediateSelectionReader(result: .unavailable),
      panel: panel,
      hotKeyService: hotKeys
    )
    let customHotKey = HotKeyConfiguration(
      keyCode: UInt32(kVK_ANSI_T),
      modifiers: UInt32(controlKey) | UInt32(optionKey),
      keyEquivalent: "T"
    )

    controller.startForTesting()
    controller.settings.translateHotKey = customHotKey

    XCTAssertEqual(hotKeys.registrations.count, 2)
    XCTAssertEqual(hotKeys.registrations.last?.translateHotKey, customHotKey)
    XCTAssertEqual(hotKeys.registrations.last?.ocrHotKey, .defaultOCR)
  }

  func testAppRuntimeDetectsXCTest() {
    XCTAssertTrue(AppRuntime.isRunningTests)
  }

  func testDockPolicyUsesAccessoryWhenNoRegularWindowsAreVisible() {
    XCTAssertEqual(
      AppWindowPresenter.activationPolicy(hasVisibleRegularWindows: true),
      .regular
    )
    XCTAssertEqual(
      AppWindowPresenter.activationPolicy(hasVisibleRegularWindows: false),
      .accessory
    )
    XCTAssertEqual(
      AppWindowPresenter.activationPolicy(hasVisibleRegularWindows: false, showsMenuBarIcon: false),
      .regular
    )
  }

  func testWindowPresentationCanTargetHiddenMainWindowWithoutCompletingRequest() {
    let windows = [
      AppWindowPresenter.WindowSnapshot(isVisible: true, identifier: "settings", title: "LexiRay Settings"),
      AppWindowPresenter.WindowSnapshot(isVisible: false, identifier: "main", title: "LexiRay")
    ]

    XCTAssertEqual(AppWindowPresenter.presentationCandidateIndex(in: windows, kind: .main), 1)
    XCTAssertFalse(AppWindowPresenter.presentationSucceeded(windows[1], kind: .main))
  }

  func testWindowPresentationCompletesOnlyForVisibleKeyableMainWindow() {
    let hidden = AppWindowPresenter.WindowSnapshot(isVisible: false, identifier: "main", title: "LexiRay")
    let miniaturized = AppWindowPresenter.WindowSnapshot(isVisible: true, identifier: "main", title: "LexiRay", isMiniaturized: true)
    let nonKeyable = AppWindowPresenter.WindowSnapshot(isVisible: true, identifier: "main", title: "LexiRay", canBecomeKey: false)
    let visible = AppWindowPresenter.WindowSnapshot(isVisible: true, identifier: "main", title: "LexiRay")

    XCTAssertFalse(AppWindowPresenter.presentationSucceeded(hidden, kind: .main))
    XCTAssertFalse(AppWindowPresenter.presentationSucceeded(miniaturized, kind: .main))
    XCTAssertFalse(AppWindowPresenter.presentationSucceeded(nonKeyable, kind: .main))
    XCTAssertTrue(AppWindowPresenter.presentationSucceeded(visible, kind: .main))
  }

  func testWindowPresentationIgnoresClosingMainWindow() {
    let windows = [
      AppWindowPresenter.WindowSnapshot(isVisible: false, identifier: "main", title: "LexiRay", isClosing: true)
    ]

    XCTAssertNil(AppWindowPresenter.presentationCandidateIndex(in: windows, kind: .main))
    XCTAssertFalse(AppWindowPresenter.presentationSucceeded(windows[0], kind: .main))
  }

  func testWindowPresentationIgnoresFloatingPanelWithAppTitle() {
    let windows = [
      AppWindowPresenter.WindowSnapshot(isVisible: true, identifier: "", title: "LexiRay", isNormalWindowLevel: false)
    ]

    XCTAssertNil(AppWindowPresenter.presentationCandidateIndex(in: windows, kind: .main))
    XCTAssertFalse(AppWindowPresenter.presentationSucceeded(windows[0], kind: .main))
  }

  func testWindowMatchingDoesNotFallbackToUnrelatedVisibleWindow() {
    let windows = [
      AppWindowPresenter.WindowSnapshot(isVisible: true, identifier: "settings", title: "LexiRay Settings")
    ]

    XCTAssertNil(AppWindowPresenter.matchingWindowIndex(in: windows, kind: .main))
  }

  func testFloatingPanelPositionResolverUsesScreenCenter() {
    let origin = FloatingPanelPositionResolver.origin(
      placement: .screenCenter,
      panelSize: NSSize(width: 200, height: 100),
      visibleFrame: NSRect(x: 0, y: 0, width: 1000, height: 800),
      mouseLocation: NSPoint(x: 20, y: 20),
      lastOrigin: nil
    )

    XCTAssertEqual(origin.x, 400)
    XCTAssertEqual(origin.y, 350)
  }

  func testFloatingPanelPositionResolverClampsLastPosition() {
    let origin = FloatingPanelPositionResolver.origin(
      placement: .lastPosition,
      panelSize: NSSize(width: 200, height: 100),
      visibleFrame: NSRect(x: 0, y: 0, width: 1000, height: 800),
      mouseLocation: NSPoint(x: 20, y: 20),
      lastOrigin: NSPoint(x: 950, y: -50)
    )

    XCTAssertEqual(origin.x, 788)
    XCTAssertEqual(origin.y, 12)
  }

  private func makeController(
    selectionReader: TextSelectionReading,
    panel: MockFloatingPanelPresenter,
    permissions: PermissionChecking = MockPermissionChecker(isAccessibilityTrusted: true),
    hotKeyService: HotKeyRegistering = MockHotKeyService(),
    pipeline: TranslationPipeline? = nil,
    speechService: SpeechControlling? = nil
  ) -> LexiRayController {
    let defaults = UserDefaults(suiteName: "LexiRayControllerTests-\(UUID().uuidString)")!
    let settings = SettingsStore(
      defaults: defaults,
      providerFileStore: makeProviderFileStore(),
      allowsMockProvider: true
    )
    enableOnly([.mock], in: settings)

    return LexiRayController(
      settings: settings,
      selectionService: selectionReader,
      permissionChecker: permissions,
      hotKeyService: hotKeyService,
      floatingPanelFactory: { _ in panel },
      pipeline: pipeline,
      speechService: speechService
    )
  }

  private func makeProviderFileStore() -> ProviderSettingsFileStore {
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("LexiRayControllerTests-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("providers.json", isDirectory: false)
    return ProviderSettingsFileStore(fileURL: fileURL)
  }

  private func makeTranslationResult(text: String) -> TranslationResult {
    TranslationResult(
      request: TranslationRequest(
        text: "hello",
        sourceLanguage: "en",
        targetLanguage: "zh-Hans",
        selectionSource: .manual
      ),
      providerID: .mock,
      providerName: "Mock",
      translatedText: text
    )
  }

  private func enableOnly(_ providers: Set<ProviderID>, in settings: SettingsStore) {
    for providerID in settings.visibleProviderIDs() {
      var configuration = settings.configuration(for: providerID)
      configuration.isEnabled = providers.contains(providerID)
      settings.updateConfiguration(configuration)
    }
  }

  private func waitUntil(
    _ condition: @escaping @MainActor () -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    for _ in 0 ..< 100 {
      if condition() {
        return
      }
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for condition", file: file, line: line)
  }
}

@MainActor
private final class BlockingSelectionReader: TextSelectionReading {
  private(set) var didStart = false
  private var continuation: CheckedContinuation<SelectionReadResult, Never>?

  func readSelectedText() async -> SelectionReadResult {
    didStart = true
    return await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func resume(with result: SelectionReadResult) {
    continuation?.resume(returning: result)
    continuation = nil
  }
}

@MainActor
private final class ImmediateSelectionReader: TextSelectionReading {
  private let result: SelectionReadResult

  init(result: SelectionReadResult) {
    self.result = result
  }

  func readSelectedText() async -> SelectionReadResult {
    result
  }
}

@MainActor
private final class MockFloatingPanelPresenter: FloatingPanelPresenting {
  private(set) var events: [Event] = []
  private(set) var pinnedStates: [Bool] = []
  private(set) var hideCount = 0
  private(set) var hideIfNeededCount = 0
  private(set) var updateLayoutCount = 0
  private(set) var refreshContentLayoutCount = 0

  func show(activating: Bool, repositioning: Bool) {
    events.append(.show(activating: activating, repositioning: repositioning))
  }

  func hide() {
    hideCount += 1
  }

  func hideIfNeeded() {
    hideIfNeededCount += 1
  }

  func updatePinnedState(isPinned: Bool) {
    pinnedStates.append(isPinned)
  }

  func refreshContentLayout() {
    refreshContentLayoutCount += 1
  }

  func updateLayout() {
    updateLayoutCount += 1
  }

  enum Event: Equatable {
    case show(activating: Bool, repositioning: Bool)

    var isRepositioningShow: Bool {
      if case let .show(_, repositioning) = self {
        return repositioning
      }
      return false
    }
  }
}

@MainActor
private final class MockHotKeyService: HotKeyRegistering {
  private(set) var registrations: [Registration] = []

  func registerDefaultHotKeys(
    translateHotKey: HotKeyConfiguration,
    ocrHotKey: HotKeyConfiguration,
    translate _: @escaping @MainActor () -> Void,
    ocr _: @escaping @MainActor () -> Void
  ) {
    registrations.append(Registration(translateHotKey: translateHotKey, ocrHotKey: ocrHotKey))
  }

  func unregister() {}

  struct Registration {
    let translateHotKey: HotKeyConfiguration
    let ocrHotKey: HotKeyConfiguration
  }
}

private final class MockPermissionChecker: PermissionChecking {
  let isAccessibilityTrusted: Bool
  private(set) var promptRequests: [Bool] = []

  init(isAccessibilityTrusted: Bool) {
    self.isAccessibilityTrusted = isAccessibilityTrusted
  }

  func requestAccessibilityIfNeeded(prompt: Bool) -> Bool {
    promptRequests.append(prompt)
    return isAccessibilityTrusted
  }
}

@MainActor
private final class MockSpeechService: SpeechControlling {
  private(set) var speakRequests: [(text: String, languageCode: String?)] = []
  private(set) var stopCount = 0
  var onStateChange: ((Bool) -> Void)?
  private(set) var isSpeaking = false

  func speak(_ text: String, languageCode: String?) -> Bool {
    guard !text.trimmedForQuery.isEmpty else {
      return false
    }

    speakRequests.append((text, languageCode))
    isSpeaking = true
    onStateChange?(true)
    return true
  }

  func stop() {
    guard isSpeaking else {
      return
    }
    stopCount += 1
    isSpeaking = false
    onStateChange?(false)
  }
}

@MainActor
private struct StreamingTestProvider: TranslationProvider {
  let id: ProviderID = .mock
  let name = "Streaming Mock"

  func translate(_ request: TranslationRequest) async throws -> TranslationResult {
    TranslationResult(
      request: request,
      providerID: id,
      providerName: name,
      translatedText: "complete",
      detectedLanguage: request.sourceLanguage
    )
  }

  func streamTranslation(_ request: TranslationRequest) async throws -> AsyncThrowingStream<TranslationStreamUpdate, Error> {
    AsyncThrowingStream { continuation in
      Task { @MainActor in
        continuation.yield(.partial("partial"))
        try? await Task.sleep(nanoseconds: 50_000_000)
        continuation.yield(
          .completed(
            TranslationResult(
              request: request,
              providerID: id,
              providerName: name,
              translatedText: "complete",
              detectedLanguage: request.sourceLanguage
            )
          )
        )
        continuation.finish()
      }
    }
  }
}
