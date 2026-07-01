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
    XCTAssertEqual(panel.events.first, .show(activating: false, repositioning: false))
    XCTAssertEqual(controller.lastSelectionSource, .simulatedCopy)
    XCTAssertEqual(controller.panelSourceText, "hello")
  }

  func testUnavailableSelectionPromptsForAccessibilityWhenNeeded() async {
    let panel = MockFloatingPanelPresenter()
    let permissions = MockPermissionChecker(isAccessibilityTrusted: false)
    let controller = makeController(
      selectionReader: ImmediateSelectionReader(
        result: SelectionReadResult(
          text: nil,
          source: .unavailable,
          failureReason: .accessibilityPermissionMissing
        )
      ),
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
    XCTAssertEqual(panel.events.first, .show(activating: false, repositioning: false))
  }

  func testUnavailableSelectionWithoutPermissionReasonShowsBlankComposer() async {
    let selectionReader = BlockingSelectionReader()
    let panel = MockFloatingPanelPresenter()
    let permissions = MockPermissionChecker(isAccessibilityTrusted: true)
    let controller = makeController(
      selectionReader: selectionReader,
      panel: panel,
      permissions: permissions
    )

    controller.translateCurrentSelection()
    await waitUntil { selectionReader.didStart }
    selectionReader.resume(with: SelectionReadResult(text: nil, source: .unavailable, failureReason: .copyFailed))
    await waitUntil { !panel.events.isEmpty }

    XCTAssertEqual(controller.panelState, .idle)
    XCTAssertEqual(controller.panelSourceText, "")
    XCTAssertEqual(controller.lastSelectionSource, .unavailable)
    XCTAssertEqual(panel.events.first, .show(activating: true, repositioning: false))
    XCTAssertTrue(permissions.promptRequests.isEmpty)
  }

  func testReSummonWithoutSelectionRestoresRecentPanelContent() async {
    let selectionReader = SequencedSelectionReader(results: [
      SelectionReadResult(text: "你好世界", source: .accessibility, failureReason: nil),
      SelectionReadResult(text: nil, source: .unavailable, failureReason: .copyFailed)
    ])
    let panel = MockFloatingPanelPresenter()
    let controller = makeController(selectionReader: selectionReader, panel: panel)

    // First summon: real selection produces a batch with content.
    controller.translateCurrentSelection()
    await waitUntil {
      if case .batch = controller.panelState { return true }
      return false
    }
    XCTAssertEqual(controller.panelSourceText, "你好世界")

    let eventsBefore = panel.events.count

    // Second summon: no selection. Recent content should be restored, not wiped.
    controller.translateCurrentSelection()
    await waitUntil { panel.events.count > eventsBefore }

    XCTAssertEqual(controller.panelSourceText, "你好世界")
    if case .batch = controller.panelState {} else {
      XCTFail("Expected retained batch content, got \(controller.panelState)")
    }
    XCTAssertEqual(panel.events.last, .show(activating: true, repositioning: false))
  }

  func testReSummonWithoutSelectionAfterRetentionWindowShowsBlankComposer() async {
    let selectionReader = SequencedSelectionReader(results: [
      SelectionReadResult(text: "你好世界", source: .accessibility, failureReason: nil),
      SelectionReadResult(text: nil, source: .unavailable, failureReason: .copyFailed)
    ])
    let panel = MockFloatingPanelPresenter()
    let controller = makeController(selectionReader: selectionReader, panel: panel)

    controller.translateCurrentSelection()
    await waitUntil {
      if case .batch = controller.panelState { return true }
      return false
    }

    // Simulate the retention window having elapsed.
    controller.expirePanelContentRetentionForTesting()

    let eventsBefore = panel.events.count
    controller.translateCurrentSelection()
    await waitUntil { panel.events.count > eventsBefore }

    XCTAssertEqual(controller.panelState, .idle)
    XCTAssertEqual(controller.panelSourceText, "")
  }

  func testReSummonAfterClearingInputShowsBlankComposer() async {
    let selectionReader = SequencedSelectionReader(results: [
      SelectionReadResult(text: "你好世界", source: .accessibility, failureReason: nil),
      SelectionReadResult(text: nil, source: .unavailable, failureReason: .copyFailed)
    ])
    let panel = MockFloatingPanelPresenter()
    let controller = makeController(selectionReader: selectionReader, panel: panel)

    // First summon: translate "你好世界"
    controller.translateCurrentSelection()
    await waitUntil {
      if case .batch = controller.panelState { return true }
      return false
    }
    XCTAssertEqual(controller.panelSourceText, "你好世界")

    // User clears the input box before dismissing (simulates backspace to empty).
    controller.panelSourceText = ""

    let eventsBefore = panel.events.count

    // Second summon: no selection, and the input was cleared. Should open blank,
    // not restore the previous batch — retention follows the dismissal state
    // (input empty → no content to restore).
    controller.translateCurrentSelection()
    await waitUntil { panel.events.count > eventsBefore }

    XCTAssertEqual(controller.panelState, .idle)
    XCTAssertEqual(controller.panelSourceText, "")
    XCTAssertEqual(panel.events.last, .show(activating: true, repositioning: false))
  }

  func testSwapPanelDirectionFlipsTargetAndRetranslates() async {
    let selectionReader = ImmediateSelectionReader(
      result: SelectionReadResult(text: "你好世界", source: .accessibility, failureReason: nil)
    )
    let panel = MockFloatingPanelPresenter()
    let controller = makeController(selectionReader: selectionReader, panel: panel)

    // Chinese source auto-detects as zh-Hans -> en.
    controller.translateCurrentSelection()
    await waitUntil {
      if case let .batch(batch) = controller.panelState {
        return batch.request.targetLanguage == "en"
      }
      return false
    }
    XCTAssertNil(controller.panelDirectionOverride)

    // Tapping the direction badge swaps to the opposite direction and retranslates.
    controller.swapPanelDirection()
    await waitUntil {
      if case let .batch(batch) = controller.panelState {
        return batch.request.sourceLanguage == "en" && batch.request.targetLanguage == "zh-Hans"
      }
      return false
    }
    XCTAssertEqual(controller.panelDirectionOverride?.source, "en")
    XCTAssertEqual(controller.panelDirectionOverride?.target, "zh-Hans")
  }

  func testSwapPanelDirectionResetsToAutomaticOnFreshTranslation() async {
    let selectionReader = SequencedSelectionReader(results: [
      SelectionReadResult(text: "你好世界", source: .accessibility, failureReason: nil),
      SelectionReadResult(text: "你好世界", source: .accessibility, failureReason: nil)
    ])
    let panel = MockFloatingPanelPresenter()
    let controller = makeController(selectionReader: selectionReader, panel: panel)

    controller.translateCurrentSelection()
    await waitUntil {
      if case .batch = controller.panelState { return true }
      return false
    }
    controller.swapPanelDirection()
    await waitUntil { controller.panelDirectionOverride != nil }

    // A brand-new translation must clear the manual override and re-detect.
    controller.translateCurrentSelection()
    await waitUntil {
      if case let .batch(batch) = controller.panelState {
        return batch.request.targetLanguage == "en"
      }
      return false
    }
    XCTAssertNil(controller.panelDirectionOverride)
  }

  func testUnstableAppIdentityBlocksSelectionBeforeReadingText() async {
    let selectionReader = BlockingSelectionReader()
    let panel = MockFloatingPanelPresenter()
    let permissions = MockPermissionChecker(isAccessibilityTrusted: true)
    let controller = makeController(
      selectionReader: selectionReader,
      panel: panel,
      permissions: permissions,
      appIdentityChecker: MockAppIdentityChecker(snapshot: unstableAppIdentity())
    )

    controller.translateCurrentSelection()
    await Task.yield()

    XCTAssertFalse(selectionReader.didStart)
    XCTAssertTrue(permissions.promptRequests.isEmpty)
    XCTAssertEqual(panel.events.first, .show(activating: false, repositioning: false))
    guard case let .error(message) = controller.panelState else {
      return XCTFail("Expected error state")
    }
    XCTAssertTrue(message.contains("unstable app identity"))
  }

  func testOCRSelectionRecognizesAndTranslatesRegion() async {
    let panel = MockFloatingPanelPresenter()
    let ocrService = MockOCRService(result: .success("screen text"))
    let overlay = MockOCRSelectionOverlay()
    let controller = makeController(
      selectionReader: ImmediateSelectionReader(result: .unavailable),
      panel: panel,
      ocrService: ocrService,
      ocrSelectionOverlay: overlay
    )
    let rect = CGRect(x: 10, y: 20, width: 120, height: 40)

    controller.translateOCRRegion()
    XCTAssertTrue(panel.events.isEmpty)
    overlay.complete(with: rect)
    XCTAssertTrue(panel.events.isEmpty)

    await waitUntil {
      guard case let .batch(batch) = controller.panelState else {
        return false
      }
      return batch.request.text == "screen text" && batch.request.selectionSource == .ocr
    }

    XCTAssertEqual(panel.hideCount, 1)
    XCTAssertEqual(overlay.beginCount, 1)
    XCTAssertEqual(ocrService.capturedRects, [rect])
    XCTAssertEqual(controller.lastSelectionSource, .ocr)
    XCTAssertEqual(controller.panelSourceText, "screen text")
    XCTAssertEqual(panel.events.last, .show(activating: false, repositioning: false))
  }

  func testOCRSelectionCancelHidesPanel() {
    let panel = MockFloatingPanelPresenter()
    let overlay = MockOCRSelectionOverlay()
    let controller = makeController(
      selectionReader: ImmediateSelectionReader(result: .unavailable),
      panel: panel,
      ocrSelectionOverlay: overlay
    )

    controller.translateOCRRegion()
    overlay.complete(with: nil)

    XCTAssertEqual(controller.panelState, .idle)
    XCTAssertEqual(panel.hideCount, 1)
    XCTAssertEqual(panel.hideIfNeededCount, 1)
    XCTAssertTrue(panel.events.isEmpty)
  }

  func testOCRFailureShowsError() async {
    let panel = MockFloatingPanelPresenter()
    let ocrService = MockOCRService(result: .failure(TranslationError.ocrUnavailable("No text was recognized")))
    let overlay = MockOCRSelectionOverlay()
    let controller = makeController(
      selectionReader: ImmediateSelectionReader(result: .unavailable),
      panel: panel,
      ocrService: ocrService,
      ocrSelectionOverlay: overlay
    )

    controller.translateOCRRegion()
    XCTAssertTrue(panel.events.isEmpty)
    overlay.complete(with: CGRect(x: 10, y: 20, width: 120, height: 40))
    XCTAssertTrue(panel.events.isEmpty)

    await waitUntil {
      guard case let .error(message) = controller.panelState else {
        return false
      }
      return message.contains("No text was recognized")
    }

    XCTAssertEqual(panel.hideCount, 1)
    XCTAssertEqual(panel.events.last, .show(activating: false, repositioning: false))
  }

  func testDuplicateAppIdentityBlocksOCRBeforeOverlayStarts() {
    let panel = MockFloatingPanelPresenter()
    let overlay = MockOCRSelectionOverlay()
    let controller = makeController(
      selectionReader: ImmediateSelectionReader(result: .unavailable),
      panel: panel,
      appIdentityChecker: MockAppIdentityChecker(
        snapshot: .stableForTesting(duplicateExecutablePaths: ["/Applications/LexiRay.app/Contents/MacOS/LexiRay"])
      ),
      ocrSelectionOverlay: overlay
    )

    controller.translateOCRRegion()

    XCTAssertEqual(overlay.beginCount, 0)
    XCTAssertEqual(panel.hideCount, 0)
    XCTAssertEqual(panel.events.first, .show(activating: false, repositioning: false))
    guard case let .error(message) = controller.panelState else {
      return XCTFail("Expected error state")
    }
    XCTAssertTrue(message.contains("Multiple LexiRay copies"))
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

  func testShortResultMatchesIdleBaselineHeight() {
    let panel = MockFloatingPanelPresenter()
    let controller = makeController(selectionReader: ImmediateSelectionReader(result: .unavailable), panel: panel)

    let idleHeight = FloatingPanelController.contentSize(for: controller).height

    controller.panelState = .result(makeTranslationResult(text: "你好"))
    let resultSize = FloatingPanelController.contentSize(for: controller)

    XCTAssertEqual(resultSize.width, 660)
    // A short translation keeps the idle footprint instead of shrinking below it,
    // so the panel stays consistent before / during / after a translation.
    XCTAssertEqual(resultSize.height, idleHeight)
    XCTAssertLessThanOrEqual(resultSize.height, 460)
  }

  func testIdlePanelUsesCompactProviderPreviewHeight() {
    let panel = MockFloatingPanelPresenter()
    let controller = makeController(selectionReader: ImmediateSelectionReader(result: .unavailable), panel: panel)

    let size = FloatingPanelController.contentSize(for: controller)

    XCTAssertLessThanOrEqual(size.width, 680)
    XCTAssertGreaterThanOrEqual(size.height, 360)
    XCTAssertLessThanOrEqual(size.height, 460)
  }

  func testSavedFloatingPanelSizeUsesWidthButIgnoresHeight() {
    let panel = MockFloatingPanelPresenter()
    let controller = makeController(selectionReader: ImmediateSelectionReader(result: .unavailable), panel: panel)
    controller.panelState = .result(makeTranslationResult(text: "你好"))

    controller.settings.recordFloatingPanelSize(width: 760, height: 520)

    let size = FloatingPanelController.contentSize(for: controller)

    XCTAssertEqual(size.width, 760)
    XCTAssertLessThan(size.height, 520)
  }

  func testOversizedSavedFloatingPanelWidthIsIgnoredForIdlePanel() {
    let panel = MockFloatingPanelPresenter()
    let controller = makeController(selectionReader: ImmediateSelectionReader(result: .unavailable), panel: panel)

    controller.settings.recordFloatingPanelSize(width: 900, height: 700)

    let size = FloatingPanelController.contentSize(for: controller)

    XCTAssertLessThanOrEqual(size.width, 680)
    XCTAssertLessThanOrEqual(size.height, 460)
  }

  func testSavedFloatingPanelSizeIsClampedToSupportedWidth() {
    let panel = MockFloatingPanelPresenter()
    let controller = makeController(selectionReader: ImmediateSelectionReader(result: .unavailable), panel: panel)

    controller.settings.recordFloatingPanelSize(width: 120, height: 520)

    let size = FloatingPanelController.contentSize(for: controller)

    XCTAssertGreaterThanOrEqual(size.width, FloatingPanelController.minimumContentSize.width)
    XCTAssertLessThan(size.height, 520)
  }

  func testManualContentSizeOverridePreventsAutomaticShrink() {
    let size = FloatingPanelController.contentSize(
      NSSize(width: 660, height: 360),
      respectingUserOverride: NSSize(width: 900, height: 620),
      maximum: NSSize(width: 980, height: 680)
    )

    XCTAssertEqual(size.width, 900)
    XCTAssertEqual(size.height, 620)
  }

  func testManualContentSizeOverrideAllowsAutomaticGrowthAndClampsToMaximum() {
    let size = FloatingPanelController.contentSize(
      NSSize(width: 1100, height: 720),
      respectingUserOverride: NSSize(width: 900, height: 620),
      maximum: NSSize(width: 980, height: 680)
    )

    XCTAssertEqual(size.width, 980)
    XCTAssertEqual(size.height, 680)
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

  func testFloatingPanelWidthStaysFixedAsContentGrows() {
    let shortController = makeController(selectionReader: ImmediateSelectionReader(result: .unavailable), panel: MockFloatingPanelPresenter())
    shortController.panelState = .result(makeTranslationResult(text: "你好"))

    let longController = makeController(selectionReader: ImmediateSelectionReader(result: .unavailable), panel: MockFloatingPanelPresenter())
    longController.panelState = .result(makeTranslationResult(text: String(repeating: "This is a very long single line of translated content that previously widened the panel.\n", count: 20)))

    let shortSize = FloatingPanelController.contentSize(for: shortController)
    let longSize = FloatingPanelController.contentSize(for: longController)

    // Width is fixed across content length; only height grows (vertical-only growth).
    XCTAssertEqual(shortSize.width, 660)
    XCTAssertEqual(longSize.width, 660)
    XCTAssertGreaterThan(longSize.height, shortSize.height)
  }

  func testManualNarrowWidthIsPreservedAcrossContentChanges() {
    let controller = makeController(selectionReader: ImmediateSelectionReader(result: .unavailable), panel: MockFloatingPanelPresenter())
    // Simulate a manual drag-resize to 560 (the minimum allowed width).
    controller.settings.setFloatingPanelLastSizeForTesting(FloatingPanelSavedSize(width: 560, height: 400))

    controller.panelState = .result(makeTranslationResult(text: "你好"))
    let size1 = FloatingPanelController.contentSize(for: controller)

    // Change content: many lines to push height above the idle baseline.
    controller.panelState = .result(makeTranslationResult(text: String(repeating: "longer line of content\n", count: 25)))
    let size2 = FloatingPanelController.contentSize(for: controller)

    // The manual width (560) must stay exactly as-is, not snap back to the
    // default 660. Only height adjusts to fit the content.
    XCTAssertEqual(size1.width, 560)
    XCTAssertEqual(size2.width, 560)
    XCTAssertGreaterThan(size2.height, size1.height)
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

  func testBlankManualTranslationDoesNotStartTranslation() {
    let panel = MockFloatingPanelPresenter()
    let controller = makeController(selectionReader: ImmediateSelectionReader(result: .unavailable), panel: panel)

    controller.translateManualText("   ")

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
    XCTAssertFalse(panel.events.contains(where: \.isRepositioningShow))
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

  func testHistoryNavigationRestoresSavedBatchWithoutProviderCall() async {
    let panel = MockFloatingPanelPresenter()
    let defaults = makeScratchDefaults()
    let settings = SettingsStore(
      defaults: defaults,
      providerFileStore: makeProviderFileStore(),
      allowsMockProvider: true
    )
    enableOnly([.mock], in: settings)
    let counter = ControllerProviderCallCounter()
    let pipeline = TranslationPipeline(settings: settings, providerFactory: { _ in
      ControllerCountingTranslationProvider(counter: counter)
    })
    let historyStore = makeHistoryStore()
    let controller = LexiRayController(
      settings: settings,
      selectionService: ImmediateSelectionReader(result: .unavailable),
      permissionChecker: MockPermissionChecker(isAccessibilityTrusted: true),
      floatingPanelFactory: { _ in panel },
      pipeline: pipeline,
      historyStore: historyStore
    )

    controller.translateManualText("hello")
    await waitUntil {
      guard case let .batch(batch) = controller.panelState else {
        return false
      }
      return batch.successfulResults.first?.translatedText == "call 1"
    }

    XCTAssertEqual(historyStore.load(limit: 100).map(\.request.text), ["hello"])
    XCTAssertTrue(controller.canNavigateTranslationHistory)
    XCTAssertTrue(controller.showPreviousHistory())
    XCTAssertEqual(controller.panelSourceText, "hello")
    controller.panelSourceText = "draft"
    XCTAssertFalse(controller.canNavigateTranslationHistory)
    XCTAssertFalse(controller.showPreviousHistory())

    controller.clearPanelSourceText()
    XCTAssertTrue(controller.showPreviousHistory())

    guard case let .batch(historyBatch) = controller.panelState else {
      return XCTFail("Expected restored history batch")
    }

    XCTAssertEqual(historyBatch.request.text, "hello")
    XCTAssertEqual(historyBatch.successfulResults.first?.translatedText, "call 1")
    XCTAssertEqual(controller.panelSourceText, "hello")
    XCTAssertEqual(counter.callCount, 1)

    XCTAssertTrue(controller.showNextHistory())
    XCTAssertEqual(controller.panelState, .idle)
    XCTAssertEqual(controller.panelSourceText, "")
  }

  func testHistoryPositionTextIsOnlyShownWhileBrowsingHistory() async {
    let panel = MockFloatingPanelPresenter()
    let defaults = makeScratchDefaults()
    let settings = SettingsStore(
      defaults: defaults,
      providerFileStore: makeProviderFileStore(),
      allowsMockProvider: true
    )
    enableOnly([.mock], in: settings)
    let counter = ControllerProviderCallCounter()
    let pipeline = TranslationPipeline(settings: settings, providerFactory: { _ in
      ControllerCountingTranslationProvider(counter: counter)
    })
    let controller = LexiRayController(
      settings: settings,
      selectionService: ImmediateSelectionReader(result: .unavailable),
      permissionChecker: MockPermissionChecker(isAccessibilityTrusted: true),
      floatingPanelFactory: { _ in panel },
      pipeline: pipeline,
      historyStore: makeHistoryStore()
    )

    XCTAssertFalse(controller.hasTranslationHistory)
    XCTAssertNil(controller.activeHistoryPositionText)

    controller.translateManualText("hello")
    await waitUntil {
      guard case let .batch(batch) = controller.panelState else {
        return false
      }
      return batch.successfulResults.first?.translatedText == "call 1"
    }

    XCTAssertTrue(controller.hasTranslationHistory)
    XCTAssertNil(controller.activeHistoryPositionText)
  }

  func testHistoryPositionTextTracksArrowBrowsingFromBlankComposer() async {
    let panel = MockFloatingPanelPresenter()
    let defaults = makeScratchDefaults()
    let settings = SettingsStore(
      defaults: defaults,
      providerFileStore: makeProviderFileStore(),
      allowsMockProvider: true
    )
    enableOnly([.mock], in: settings)
    let counter = ControllerProviderCallCounter()
    let pipeline = TranslationPipeline(settings: settings, providerFactory: { _ in
      ControllerCountingTranslationProvider(counter: counter)
    })
    let controller = LexiRayController(
      settings: settings,
      selectionService: ImmediateSelectionReader(result: .unavailable),
      permissionChecker: MockPermissionChecker(isAccessibilityTrusted: true),
      floatingPanelFactory: { _ in panel },
      pipeline: pipeline,
      historyStore: makeHistoryStore()
    )

    controller.translateManualText("one")
    await waitUntil {
      guard case let .batch(batch) = controller.panelState else {
        return false
      }
      return batch.request.text == "one" && batch.successfulResults.first?.translatedText == "call 1"
    }

    controller.translateManualText("two")
    await waitUntil {
      guard case let .batch(batch) = controller.panelState else {
        return false
      }
      return batch.request.text == "two" && batch.successfulResults.first?.translatedText == "call 2"
    }

    XCTAssertNil(controller.activeHistoryPositionText)

    controller.clearPanelSourceText()
    XCTAssertTrue(controller.showPreviousHistory())
    XCTAssertEqual(controller.panelSourceText, "two")
    XCTAssertEqual(controller.activeHistoryPositionText, "History 2/2")

    XCTAssertTrue(controller.showPreviousHistory())
    XCTAssertEqual(controller.panelSourceText, "one")
    XCTAssertEqual(controller.activeHistoryPositionText, "History 1/2")

    XCTAssertTrue(controller.showNextHistory())
    XCTAssertEqual(controller.panelSourceText, "two")
    XCTAssertEqual(controller.activeHistoryPositionText, "History 2/2")

    XCTAssertTrue(controller.showNextHistory())
    XCTAssertEqual(controller.panelState, .idle)
    XCTAssertEqual(controller.panelSourceText, "")
    XCTAssertNil(controller.activeHistoryPositionText)
  }

  func testLatestHistoryIsBrowsableAfterFirstProviderSuccess() async {
    let panel = MockFloatingPanelPresenter()
    let defaults = makeScratchDefaults()
    let settings = SettingsStore(
      defaults: defaults,
      providerFileStore: makeProviderFileStore(),
      allowsMockProvider: true
    )
    enableOnly([.mock, .systemDictionary], in: settings)
    let pipeline = TranslationPipeline(settings: settings, providerFactory: { configuration in
      switch configuration.providerID {
      case .mock:
        DelayedAutoCopyProvider(providerID: .mock, delay: 0, translatedText: "hi from first")
      case .systemDictionary:
        DelayedAutoCopyProvider(providerID: .systemDictionary, delay: 150_000_000, translatedText: "hi from second")
      default:
        DelayedAutoCopyProvider(providerID: configuration.providerID, delay: 0, translatedText: "unused")
      }
    })
    let historyStore = makeHistoryStore()
    let controller = LexiRayController(
      settings: settings,
      selectionService: ImmediateSelectionReader(result: .unavailable),
      permissionChecker: MockPermissionChecker(isAccessibilityTrusted: true),
      floatingPanelFactory: { _ in panel },
      pipeline: pipeline,
      historyStore: historyStore
    )

    controller.translateManualText("hi")
    await waitUntil {
      guard case let .batch(batch) = controller.panelState else {
        return false
      }
      let firstEntry = batch.entries.first(where: { $0.providerID == .mock })
      let secondEntry = batch.entries.first(where: { $0.providerID == .systemDictionary })
      return firstEntry?.result?.translatedText == "hi from first" && secondEntry?.result == nil
    }

    let historyLimit = settings.translationHistoryLimit
    XCTAssertEqual(historyStore.load(limit: historyLimit).map(\.request.text), ["hi"])

    controller.clearPanelSourceText()
    XCTAssertTrue(controller.showPreviousHistory())
    XCTAssertEqual(controller.panelSourceText, "hi")
    XCTAssertEqual(controller.activeHistoryPositionText, "History 1/1")
  }

  func testHistoryNavigationDoesNotCancelInFlightBatchAfterFirstProviderSuccess() async {
    let panel = MockFloatingPanelPresenter()
    let defaults = makeScratchDefaults()
    let settings = SettingsStore(
      defaults: defaults,
      providerFileStore: makeProviderFileStore(),
      allowsMockProvider: true
    )
    enableOnly([.mock, .systemDictionary], in: settings)
    let pipeline = TranslationPipeline(settings: settings, providerFactory: { configuration in
      switch configuration.providerID {
      case .mock:
        DelayedAutoCopyProvider(providerID: .mock, delay: 0, translatedText: "hi from first")
      case .systemDictionary:
        DelayedAutoCopyProvider(providerID: .systemDictionary, delay: 150_000_000, translatedText: "hi from second")
      default:
        DelayedAutoCopyProvider(providerID: configuration.providerID, delay: 0, translatedText: "unused")
      }
    })
    let historyStore = makeHistoryStore()
    let controller = LexiRayController(
      settings: settings,
      selectionService: ImmediateSelectionReader(result: .unavailable),
      permissionChecker: MockPermissionChecker(isAccessibilityTrusted: true),
      floatingPanelFactory: { _ in panel },
      pipeline: pipeline,
      historyStore: historyStore
    )

    controller.translateManualText("hi")
    await waitUntil {
      guard case let .batch(batch) = controller.panelState else {
        return false
      }
      let firstEntry = batch.entries.first(where: { $0.providerID == .mock })
      let secondEntry = batch.entries.first(where: { $0.providerID == .systemDictionary })
      return firstEntry?.result?.translatedText == "hi from first" && secondEntry?.result == nil
    }

    let historyLimit = settings.translationHistoryLimit
    XCTAssertEqual(historyStore.load(limit: historyLimit).map(\.request.text), ["hi"])
    XCTAssertFalse(controller.canNavigateTranslationHistory)
    XCTAssertFalse(controller.showPreviousHistory())
    XCTAssertEqual(controller.panelSourceText, "hi")
    XCTAssertNil(controller.activeHistoryPositionText)

    await waitUntil {
      guard case let .batch(batch) = controller.panelState else {
        return false
      }
      let secondEntry = batch.entries.first(where: { $0.providerID == .systemDictionary })
      return secondEntry?.result?.translatedText == "hi from second"
    }

    let savedSecondEntry = historyStore.load(limit: historyLimit).first?.entries.first {
      $0.providerID == .systemDictionary
    }
    if case let .success(result) = savedSecondEntry?.status {
      XCTAssertEqual(result.translatedText, "hi from second")
    } else {
      XCTFail("Expected completed second provider result in history")
    }
    XCTAssertTrue(controller.canNavigateTranslationHistory)
  }

  func testHistoryNavigationFromCurrentSavedResultMovesToPreviousEntry() async {
    let panel = MockFloatingPanelPresenter()
    let defaults = makeScratchDefaults()
    let settings = SettingsStore(
      defaults: defaults,
      providerFileStore: makeProviderFileStore(),
      allowsMockProvider: true
    )
    enableOnly([.mock], in: settings)
    let counter = ControllerProviderCallCounter()
    let pipeline = TranslationPipeline(settings: settings, providerFactory: { _ in
      ControllerCountingTranslationProvider(counter: counter)
    })
    let controller = LexiRayController(
      settings: settings,
      selectionService: ImmediateSelectionReader(result: .unavailable),
      permissionChecker: MockPermissionChecker(isAccessibilityTrusted: true),
      floatingPanelFactory: { _ in panel },
      pipeline: pipeline,
      historyStore: makeHistoryStore()
    )

    controller.translateManualText("hi")
    await waitUntil {
      guard case let .batch(batch) = controller.panelState else {
        return false
      }
      return batch.request.text == "hi" && batch.successfulResults.first?.translatedText == "call 1"
    }

    controller.translateManualText("ok")
    await waitUntil {
      guard case let .batch(batch) = controller.panelState else {
        return false
      }
      return batch.request.text == "ok" && batch.successfulResults.first?.translatedText == "call 2"
    }

    XCTAssertEqual(controller.panelSourceText, "ok")
    XCTAssertTrue(controller.canNavigateTranslationHistory)
    XCTAssertTrue(controller.showPreviousHistory())
    XCTAssertEqual(controller.panelSourceText, "hi")

    guard case let .batch(historyBatch) = controller.panelState else {
      return XCTFail("Expected restored history batch")
    }
    XCTAssertEqual(historyBatch.request.text, "hi")
    XCTAssertEqual(historyBatch.successfulResults.first?.translatedText, "call 1")
    XCTAssertEqual(counter.callCount, 2)

    XCTAssertTrue(controller.showNextHistory())
    XCTAssertEqual(controller.panelSourceText, "ok")
    XCTAssertTrue(controller.showNextHistory())
    XCTAssertEqual(controller.panelState, .idle)
    XCTAssertEqual(controller.panelSourceText, "")
  }

  func testHistoryLimitReductionPrunesPersistedHistory() async {
    let panel = MockFloatingPanelPresenter()
    let defaults = makeScratchDefaults()
    let settings = SettingsStore(
      defaults: defaults,
      providerFileStore: makeProviderFileStore(),
      allowsMockProvider: true
    )
    enableOnly([.mock], in: settings)
    let counter = ControllerProviderCallCounter()
    let pipeline = TranslationPipeline(settings: settings, providerFactory: { _ in
      ControllerCountingTranslationProvider(counter: counter)
    })
    let historyStore = makeHistoryStore()
    let controller = LexiRayController(
      settings: settings,
      selectionService: ImmediateSelectionReader(result: .unavailable),
      permissionChecker: MockPermissionChecker(isAccessibilityTrusted: true),
      floatingPanelFactory: { _ in panel },
      pipeline: pipeline,
      historyStore: historyStore
    )

    controller.startForTesting()
    controller.translateManualText("one")
    await waitUntil {
      guard case let .batch(batch) = controller.panelState else {
        return false
      }
      return batch.successfulResults.first?.translatedText == "call 1"
    }

    controller.translateManualText("two")
    await waitUntil {
      guard case let .batch(batch) = controller.panelState else {
        return false
      }
      return batch.successfulResults.first?.translatedText == "call 2"
    }

    XCTAssertEqual(historyStore.load(limit: 100).map(\.request.text), ["one", "two"])

    settings.translationHistoryLimit = 1

    await waitUntil {
      historyStore.load(limit: 100).map(\.request.text) == ["two"]
    }
  }

  func testManualRetranslateBypassesCacheForSameText() async {
    let panel = MockFloatingPanelPresenter()
    let defaults = makeScratchDefaults()
    let settings = SettingsStore(
      defaults: defaults,
      providerFileStore: makeProviderFileStore(),
      allowsMockProvider: true
    )
    enableOnly([.mock], in: settings)
    let counter = ControllerProviderCallCounter()
    let pipeline = TranslationPipeline(settings: settings, providerFactory: { _ in
      ControllerCountingTranslationProvider(counter: counter)
    })
    let controller = LexiRayController(
      settings: settings,
      selectionService: ImmediateSelectionReader(result: .unavailable),
      permissionChecker: MockPermissionChecker(isAccessibilityTrusted: true),
      floatingPanelFactory: { _ in panel },
      pipeline: pipeline,
      historyStore: makeHistoryStore()
    )

    controller.translateManualText("hello")
    await waitUntil {
      guard case let .batch(batch) = controller.panelState else {
        return false
      }
      return batch.successfulResults.first?.translatedText == "call 1"
    }

    controller.translateManualText("hello")
    await waitUntil {
      guard case let .batch(batch) = controller.panelState else {
        return false
      }
      return batch.successfulResults.first?.translatedText == "call 2"
    }

    XCTAssertEqual(counter.callCount, 2)
    XCTAssertFalse(panel.events.contains(where: \.isRepositioningShow))
  }

  func testTranslateCurrentSelectionBypassesCacheForSameText() async {
    let panel = MockFloatingPanelPresenter()
    let defaults = makeScratchDefaults()
    let settings = SettingsStore(
      defaults: defaults,
      providerFileStore: makeProviderFileStore(),
      allowsMockProvider: true
    )
    enableOnly([.mock], in: settings)
    let counter = ControllerProviderCallCounter()
    let pipeline = TranslationPipeline(settings: settings, providerFactory: { _ in
      ControllerCountingTranslationProvider(counter: counter)
    })
    let controller = LexiRayController(
      settings: settings,
      selectionService: ImmediateSelectionReader(result: SelectionReadResult(text: "hello", source: .simulatedCopy)),
      permissionChecker: MockPermissionChecker(isAccessibilityTrusted: true),
      floatingPanelFactory: { _ in panel },
      pipeline: pipeline,
      historyStore: makeHistoryStore()
    )

    controller.translateCurrentSelection()
    await waitUntil {
      guard case let .batch(batch) = controller.panelState else {
        return false
      }
      return batch.successfulResults.first?.translatedText == "call 1"
    }

    controller.translateCurrentSelection()
    await waitUntil {
      guard case let .batch(batch) = controller.panelState else {
        return false
      }
      return batch.successfulResults.first?.translatedText == "call 2"
    }

    XCTAssertEqual(counter.callCount, 2)
    XCTAssertFalse(panel.events.contains(where: \.isRepositioningShow))
  }

  func testStreamingPartialRefreshesPanelWithoutRepositioningShow() async {
    let panel = MockFloatingPanelPresenter()
    let defaults = makeScratchDefaults()
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
      pipeline: pipeline,
      historyStore: makeHistoryStore()
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

    XCTAssertEqual(panel.events.filter(\.isRepositioningShow).count, 0)
    XCTAssertGreaterThanOrEqual(panel.refreshContentLayoutCount, 1)

    await waitUntil {
      guard case let .batch(batch) = controller.panelState else {
        return false
      }
      return batch.successfulResults.first?.translatedText == "complete"
    }

    XCTAssertEqual(panel.events.filter(\.isRepositioningShow).count, 0)
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

    controller.copyResultToClipboard(second, surface: .mainWindow)

    XCTAssertEqual(NSPasteboard.general.string(forType: .string), "two")
    XCTAssertEqual(controller.copyToast?.message, "Copied")
    XCTAssertEqual(controller.copyToast?.surface, .mainWindow)
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

    controller.copyResultToClipboard(result, format: .html, surface: .floatingPanel)

    XCTAssertEqual(controller.settings.defaultCopyFormat, .html)
    XCTAssertEqual(controller.copyToast?.message, "Copied")
    XCTAssertEqual(controller.copyToast?.surface, .floatingPanel)
    XCTAssertTrue(NSPasteboard.general.string(forType: .html)?.contains("Hello") == true)
    XCTAssertTrue(NSPasteboard.general.string(forType: .string)?.contains("Hello world") == true)
  }

  func testAutoCopyOffDoesNotWriteClipboard() async {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString("sentinel", forType: .string)
    let panel = MockFloatingPanelPresenter()
    let controller = makeController(selectionReader: ImmediateSelectionReader(result: .unavailable), panel: panel)

    controller.translateManualText("hello")
    await waitUntil {
      guard case let .batch(batch) = controller.panelState else {
        return false
      }
      return !batch.successfulResults.isEmpty
    }

    XCTAssertEqual(pasteboard.string(forType: .string), "sentinel")
    XCTAssertNil(controller.copyToast)
  }

  func testAutoCopyWaitsForFirstProviderInOrder() async {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString("sentinel", forType: .string)
    let panel = MockFloatingPanelPresenter()
    let defaults = makeScratchDefaults()
    let settings = SettingsStore(
      defaults: defaults,
      providerFileStore: makeProviderFileStore(),
      allowsMockProvider: true
    )
    enableOnly([.mock, .systemDictionary], in: settings)
    settings.autoCopyMode = .firstProviderSuccess
    let pipeline = TranslationPipeline(settings: settings, providerFactory: { configuration in
      switch configuration.providerID {
      case .mock:
        DelayedAutoCopyProvider(providerID: .mock, delay: 120_000_000, translatedText: "first")
      case .systemDictionary:
        DelayedAutoCopyProvider(providerID: .systemDictionary, delay: 0, translatedText: "second")
      default:
        DelayedAutoCopyProvider(providerID: configuration.providerID, delay: 0, translatedText: "unused")
      }
    })
    let controller = LexiRayController(
      settings: settings,
      selectionService: ImmediateSelectionReader(result: .unavailable),
      permissionChecker: MockPermissionChecker(isAccessibilityTrusted: true),
      floatingPanelFactory: { _ in panel },
      pipeline: pipeline,
      historyStore: makeHistoryStore()
    )

    controller.translateManualText("hello")
    await waitUntil {
      guard case let .batch(batch) = controller.panelState else {
        return false
      }
      let secondEntry = batch.entries.first(where: { $0.providerID == .systemDictionary })
      let firstEntry = batch.entries.first(where: { $0.providerID == .mock })
      return secondEntry?.result?.translatedText == "second" && firstEntry?.result == nil
    }

    XCTAssertEqual(pasteboard.string(forType: .string), "sentinel")
    XCTAssertNil(controller.copyToast)

    await waitUntil {
      pasteboard.string(forType: .string) == "first"
    }

    XCTAssertEqual(controller.copyToast?.surface, .floatingPanel)
  }

  func testAutoCopyDoesNotOverwriteWithLaterProviderSuccess() async {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    let panel = MockFloatingPanelPresenter()
    let defaults = makeScratchDefaults()
    let settings = SettingsStore(
      defaults: defaults,
      providerFileStore: makeProviderFileStore(),
      allowsMockProvider: true
    )
    enableOnly([.mock, .systemDictionary], in: settings)
    settings.autoCopyMode = .firstProviderSuccess
    let pipeline = TranslationPipeline(settings: settings, providerFactory: { configuration in
      switch configuration.providerID {
      case .mock:
        DelayedAutoCopyProvider(providerID: .mock, delay: 0, translatedText: "first")
      case .systemDictionary:
        DelayedAutoCopyProvider(providerID: .systemDictionary, delay: 120_000_000, translatedText: "second")
      default:
        DelayedAutoCopyProvider(providerID: configuration.providerID, delay: 0, translatedText: "unused")
      }
    })
    let controller = LexiRayController(
      settings: settings,
      selectionService: ImmediateSelectionReader(result: .unavailable),
      permissionChecker: MockPermissionChecker(isAccessibilityTrusted: true),
      floatingPanelFactory: { _ in panel },
      pipeline: pipeline,
      historyStore: makeHistoryStore()
    )

    controller.translateManualText("hello")
    await waitUntil {
      pasteboard.string(forType: .string) == "first"
    }
    await waitUntil {
      guard case let .batch(batch) = controller.panelState else {
        return false
      }
      return batch.successfulResults.count == 2
    }

    XCTAssertEqual(pasteboard.string(forType: .string), "first")
    XCTAssertEqual(controller.copyToast?.surface, .floatingPanel)
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

  func testProviderToggleDisablesStreamingProvider() async {
    let panel = MockFloatingPanelPresenter()
    let defaults = makeScratchDefaults()
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
      pipeline: pipeline,
      historyStore: makeHistoryStore()
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

  func testProviderToggleEnablesDisabledProviderForCurrentRequest() async {
    let panel = MockFloatingPanelPresenter()
    let defaults = makeScratchDefaults()
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
      pipeline: pipeline,
      historyStore: makeHistoryStore()
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

  func testProviderToggleMissingAPIKeyDoesNotPersistEnabled() async {
    let panel = MockFloatingPanelPresenter()
    let defaults = makeScratchDefaults()
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
      floatingPanelFactory: { _ in panel },
      historyStore: makeHistoryStore()
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
    XCTAssertTrue(style.contains(.resizable))
    XCTAssertFalse(style.contains(.titled))
    XCTAssertFalse(style.contains(.fullSizeContentView))
  }

  func testFloatingPanelLevelOnlyFloatsWhenPinned() {
    XCTAssertEqual(FloatingPanelController.panelLevel(isPinned: false), .normal)
    XCTAssertEqual(FloatingPanelController.panelLevel(isPinned: true), .floating)
  }

  func testFloatingPanelRoutesHistoryKeysWhenVisibleWithoutEventWindow() {
    XCTAssertTrue(
      FloatingPanelController.shouldRoutePanelKeyEvent(
        eventWindowNumber: nil,
        panelWindowNumber: 42,
        panelIsVisible: true
      )
    )
    XCTAssertTrue(
      FloatingPanelController.shouldRoutePanelKeyEvent(
        eventWindowNumber: 42,
        panelWindowNumber: 42,
        panelIsVisible: false
      )
    )
    XCTAssertFalse(
      FloatingPanelController.shouldRoutePanelKeyEvent(
        eventWindowNumber: nil,
        panelWindowNumber: 42,
        panelIsVisible: false
      )
    )
    XCTAssertFalse(
      FloatingPanelController.shouldRoutePanelKeyEvent(
        eventWindowNumber: 7,
        panelWindowNumber: 42,
        panelIsVisible: true
      )
    )
  }

  func testFloatingPanelRecognizesEscapeKey() {
    XCTAssertTrue(FloatingPanelController.isEscapeKey(keyCode: UInt16(kVK_Escape)))
    XCTAssertFalse(FloatingPanelController.isEscapeKey(keyCode: UInt16(kVK_UpArrow)))
  }

  func testFloatingPanelRoutesEscapeKeyOnlyForPanelEvents() {
    XCTAssertTrue(
      FloatingPanelController.shouldRouteEscapeKeyEvent(
        keyCode: UInt16(kVK_Escape),
        eventWindowNumber: 42,
        panelWindowNumber: 42,
        panelIsVisible: false
      )
    )
    XCTAssertTrue(
      FloatingPanelController.shouldRouteEscapeKeyEvent(
        keyCode: UInt16(kVK_Escape),
        eventWindowNumber: nil,
        panelWindowNumber: 42,
        panelIsVisible: true
      )
    )
    XCTAssertFalse(
      FloatingPanelController.shouldRouteEscapeKeyEvent(
        keyCode: UInt16(kVK_Escape),
        eventWindowNumber: 7,
        panelWindowNumber: 42,
        panelIsVisible: true
      )
    )
    XCTAssertFalse(
      FloatingPanelController.shouldRouteEscapeKeyEvent(
        keyCode: UInt16(kVK_UpArrow),
        eventWindowNumber: 42,
        panelWindowNumber: 42,
        panelIsVisible: true
      )
    )
  }

  func testFloatingPanelCloseActionHidesPinnedPanelDirectly() {
    let panel = MockFloatingPanelPresenter()
    let controller = makeController(selectionReader: ImmediateSelectionReader(result: .unavailable), panel: panel)
    controller.isPanelPinned = true

    controller.hideFloatingPanel()

    XCTAssertEqual(panel.hideCount, 1)
    XCTAssertEqual(panel.hideIfNeededCount, 0)
  }

  func testSourceTextEditorUsesSharedTextInsets() {
    XCTAssertEqual(SourceTextEditor.textInset.width, 11)
    XCTAssertEqual(SourceTextEditor.textInset.height, 9)
    XCTAssertEqual(SourceTextEditor.lineFragmentPadding, 0)
    XCTAssertTrue(SourceTextEditor.textColor.isEqual(NSColor.labelColor))
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

  func testDockPolicyDependsOnlyOnMenuBarIcon() {
    // With the menu bar icon available the app stays an accessory (out of the
    // Dock) regardless of whether a regular window is on screen.
    XCTAssertEqual(
      AppWindowPresenter.activationPolicy(hasVisibleRegularWindows: true),
      .accessory
    )
    XCTAssertEqual(
      AppWindowPresenter.activationPolicy(hasVisibleRegularWindows: false),
      .accessory
    )
    // When the menu bar icon is hidden the Dock icon is the only entry point.
    XCTAssertEqual(
      AppWindowPresenter.activationPolicy(hasVisibleRegularWindows: false, showsMenuBarIcon: false),
      .regular
    )
    XCTAssertEqual(
      AppWindowPresenter.activationPolicy(hasVisibleRegularWindows: true, showsMenuBarIcon: false),
      .regular
    )
  }

  func testDockHideDecisionPreservesVisibleAppSurfaces() {
    XCTAssertFalse(
      AppWindowPresenter.shouldHideApplication(
        desiredPolicy: .accessory,
        hasVisibleAppSurface: true
      )
    )
    XCTAssertTrue(
      AppWindowPresenter.shouldHideApplication(
        desiredPolicy: .accessory,
        hasVisibleAppSurface: false
      )
    )
    XCTAssertFalse(
      AppWindowPresenter.shouldHideApplication(
        desiredPolicy: .regular,
        hasVisibleAppSurface: false
      )
    )
  }

  func testVisibleAppSurfaceIncludesFloatingPanelLevelWindows() {
    let floatingPanel = AppWindowPresenter.WindowSnapshot(
      isVisible: true,
      identifier: "",
      title: "LexiRay",
      isNormalWindowLevel: false
    )
    let closingMainWindow = AppWindowPresenter.WindowSnapshot(
      isVisible: true,
      identifier: "main",
      title: "LexiRay",
      isClosing: true
    )

    XCTAssertTrue(AppWindowPresenter.hasVisibleAppSurface(in: [floatingPanel]))
    XCTAssertFalse(AppWindowPresenter.hasVisibleAppSurface(in: [closingMainWindow]))
  }

  func testPendingMainWindowPresentationCancelsWhenAppResigns() async {
    defer {
      AppWindowPresenter.cancelPendingMainWindowPresentation()
    }

    AppWindowPresenter.requestMainWindowPresentation()

    XCTAssertTrue(AppWindowPresenter.isMainWindowPresentationPending)

    NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)

    await waitUntil {
      !AppWindowPresenter.isMainWindowPresentationPending
    }
    XCTAssertFalse(AppWindowPresenter.isMainWindowPresentationPending)
  }

  func testPendingMainWindowPresentationCanBeCancelled() {
    AppWindowPresenter.requestMainWindowPresentation()

    XCTAssertTrue(AppWindowPresenter.isMainWindowPresentationPending)

    AppWindowPresenter.cancelPendingMainWindowPresentation()

    XCTAssertFalse(AppWindowPresenter.isMainWindowPresentationPending)
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

  func testPermissionMonitorActivationEventRefreshesAppIdentity() async {
    let applicationCenter = NotificationCenter()
    let monitor = PermissionStatusMonitor(
      permissionChecker: MockPermissionChecker(isAccessibilityTrusted: true),
      distributedCenter: NotificationCenter(),
      applicationCenter: applicationCenter,
      fallbackPollInterval: .seconds(3600),
      notificationRecheckDelay: .seconds(3600)
    )
    defer { monitor.stop() }
    let identityChecker = MutableAppIdentityChecker(snapshot: .stableForTesting())
    let controller = makeController(
      selectionReader: BlockingSelectionReader(),
      panel: MockFloatingPanelPresenter(),
      appIdentityChecker: identityChecker,
      permissionMonitor: monitor
    )
    controller.startForTesting()
    monitor.start()
    XCTAssertEqual(controller.appIdentity.signatureState, .stable)

    identityChecker.snapshot = unstableAppIdentity()
    applicationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)

    await waitUntil { controller.appIdentity.signatureState == .unstable }
  }

  private func makeController(
    selectionReader: TextSelectionReading,
    panel: MockFloatingPanelPresenter,
    permissions: PermissionChecking = MockPermissionChecker(isAccessibilityTrusted: true),
    hotKeyService: HotKeyRegistering = MockHotKeyService(),
    appIdentityChecker: AppIdentityChecking = StaticAppIdentityChecker(snapshot: .stableForTesting()),
    pipeline: TranslationPipeline? = nil,
    ocrService: OCRRecognizing? = nil,
    ocrSelectionOverlay: OCRRegionSelecting? = nil,
    historyStore: TranslationHistoryStore? = nil,
    speechService: SpeechControlling? = nil,
    permissionMonitor: PermissionStatusMonitor? = nil
  ) -> LexiRayController {
    let defaults = makeScratchDefaults()
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
      appIdentityChecker: appIdentityChecker,
      floatingPanelFactory: { _ in panel },
      pipeline: pipeline,
      ocrService: ocrService,
      ocrSelectionOverlay: ocrSelectionOverlay,
      historyStore: historyStore ?? makeHistoryStore(),
      speechService: speechService,
      permissionMonitor: permissionMonitor
    )
  }

  private func makeProviderFileStore() -> ProviderSettingsFileStore {
    let fileURL = makeScratchDirectory().appendingPathComponent("providers.json", isDirectory: false)
    return ProviderSettingsFileStore(fileURL: fileURL)
  }

  private func makeHistoryStore() -> TranslationHistoryStore {
    let fileURL = makeScratchDirectory().appendingPathComponent("history.json", isDirectory: false)
    return TranslationHistoryStore(fileURL: fileURL)
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

  private func unstableAppIdentity() -> AppIdentitySnapshot {
    AppIdentitySnapshot(
      bundleIdentifier: AppConstants.bundleID,
      bundlePath: "/tmp/LexiRay.app",
      executablePath: "/tmp/LexiRay.app/Contents/MacOS/LexiRay",
      signatureState: .unstable,
      signatureSummary: "unsigned or ad hoc signature",
      certificateAuthority: nil,
      duplicateExecutablePaths: []
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
private final class SequencedSelectionReader: TextSelectionReading {
  private var results: [SelectionReadResult]
  private let last: SelectionReadResult

  init(results: [SelectionReadResult]) {
    precondition(!results.isEmpty)
    self.results = results
    last = results[results.count - 1]
  }

  func readSelectedText() async -> SelectionReadResult {
    if results.isEmpty {
      return last
    }
    return results.removeFirst()
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
  let isScreenCaptureTrusted: Bool
  private(set) var promptRequests: [Bool] = []

  init(isAccessibilityTrusted: Bool, isScreenCaptureTrusted: Bool = false) {
    self.isAccessibilityTrusted = isAccessibilityTrusted
    self.isScreenCaptureTrusted = isScreenCaptureTrusted
  }

  func requestAccessibilityIfNeeded(prompt: Bool) -> Bool {
    promptRequests.append(prompt)
    return isAccessibilityTrusted
  }
}

private final class MutableAppIdentityChecker: AppIdentityChecking {
  var snapshot: AppIdentitySnapshot

  init(snapshot: AppIdentitySnapshot) {
    self.snapshot = snapshot
  }

  var currentSnapshot: AppIdentitySnapshot {
    snapshot
  }
}

private struct MockAppIdentityChecker: AppIdentityChecking {
  let snapshot: AppIdentitySnapshot

  var currentSnapshot: AppIdentitySnapshot {
    snapshot
  }
}

@MainActor
private final class MockOCRService: OCRRecognizing {
  private let result: Result<String, Error>
  private(set) var capturedRects: [CGRect] = []

  init(result: Result<String, Error>) {
    self.result = result
  }

  func captureAndRecognizeText(in rect: CGRect) async throws -> String {
    capturedRects.append(rect)
    return try result.get()
  }
}

@MainActor
private final class MockOCRSelectionOverlay: OCRRegionSelecting {
  private(set) var beginCount = 0
  private(set) var closeCount = 0
  private var completion: ((CGRect?) -> Void)?

  func beginSelection(onComplete: @escaping (CGRect?) -> Void) {
    beginCount += 1
    completion = onComplete
  }

  func close() {
    closeCount += 1
  }

  func complete(with rect: CGRect?) {
    completion?(rect)
    completion = nil
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

@MainActor
private final class ControllerProviderCallCounter {
  var callCount = 0
}

@MainActor
private struct ControllerCountingTranslationProvider: TranslationProvider {
  let id: ProviderID = .mock
  let name = "Counting Mock"
  let counter: ControllerProviderCallCounter

  func translate(_ request: TranslationRequest) async throws -> TranslationResult {
    counter.callCount += 1
    return TranslationResult(
      request: request,
      providerID: id,
      providerName: name,
      translatedText: "call \(counter.callCount)",
      detectedLanguage: request.sourceLanguage
    )
  }
}

private struct DelayedAutoCopyProvider: TranslationProvider {
  let id: ProviderID
  let name: String
  let delay: UInt64
  let translatedText: String

  init(providerID: ProviderID, delay: UInt64, translatedText: String) {
    id = providerID
    name = providerID.displayName
    self.delay = delay
    self.translatedText = translatedText
  }

  func translate(_ request: TranslationRequest) async throws -> TranslationResult {
    if delay > 0 {
      try await Task.sleep(nanoseconds: delay)
    }

    return TranslationResult(
      request: request,
      providerID: id,
      providerName: name,
      translatedText: translatedText,
      detectedLanguage: request.sourceLanguage
    )
  }
}
