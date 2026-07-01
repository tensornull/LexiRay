@testable import LexiRay
import XCTest

@MainActor
final class TranslationPipelineTests: XCTestCase {
  func testMockProviderReturnsTranslationResult() async throws {
    let defaults = makeScratchDefaults()
    let settings = SettingsStore(defaults: defaults, providerFileStore: makeProviderFileStore(), allowsMockProvider: true)
    enableOnly([.mock], in: settings)
    settings.language1 = "en"
    settings.language2 = "zh-Hans"
    let pipeline = TranslationPipeline(settings: settings)

    let result = try await pipeline.translate(text: "hello", selectionSource: .manual)

    XCTAssertEqual(result.providerID, .mock)
    XCTAssertTrue(result.translatedText.contains("hello"))
    XCTAssertEqual(result.request.selectionSource, .manual)
    XCTAssertEqual(result.request.targetLanguage, "zh-Hans")
  }

  func testPipelineAutoSwitchesChineseToLanguage1() async throws {
    let defaults = makeScratchDefaults()
    let settings = SettingsStore(defaults: defaults, providerFileStore: makeProviderFileStore(), allowsMockProvider: true)
    enableOnly([.mock], in: settings)
    settings.language1 = "en"
    settings.language2 = "zh-Hans"
    let pipeline = TranslationPipeline(settings: settings)

    let result = try await pipeline.translate(text: "你好，这是一个翻译测试。", selectionSource: .manual)

    XCTAssertEqual(result.request.targetLanguage, "en")
  }

  func testPipelineRoutesMixedChineseWithEnglishQuoteToEnglish() throws {
    let defaults = makeScratchDefaults()
    let settings = SettingsStore(defaults: defaults, providerFileStore: makeProviderFileStore(), allowsMockProvider: true)
    settings.language1 = "en"
    settings.language2 = "zh-Hans"
    let pipeline = TranslationPipeline(settings: settings)
    let text = "对此我们非常抱歉。昨晚凌晨出现的类似 \"Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits.\" 的提示，主要是受到 Claude 官方资源波动的影响。"

    let batch = try pipeline.makeBatch(text: text, selectionSource: .manual)

    XCTAssertEqual(batch.request.sourceLanguage, "zh-Hans")
    XCTAssertEqual(batch.request.targetLanguage, "en")
  }

  func testMakeBatchUsesDirectionOverride() throws {
    let defaults = makeScratchDefaults()
    let settings = SettingsStore(defaults: defaults, providerFileStore: makeProviderFileStore(), allowsMockProvider: true)
    settings.language1 = "en"
    settings.language2 = "zh-Hans"
    let pipeline = TranslationPipeline(settings: settings)

    // "你好" auto-detects as Chinese, but the override forces the opposite direction.
    let batch = try pipeline.makeBatch(
      text: "你好",
      selectionSource: .manual,
      directionOverride: PanelDirectionOverride(source: "zh-Hans", target: "zh-Hant")
    )

    XCTAssertEqual(batch.request.sourceLanguage, "zh-Hans")
    XCTAssertEqual(batch.request.targetLanguage, "zh-Hant")
  }

  func testPipelineTreatsShortEnglishTextAsEnglishSource() throws {
    let defaults = makeScratchDefaults()
    let settings = SettingsStore(defaults: defaults, providerFileStore: makeProviderFileStore(), allowsMockProvider: true)
    settings.language1 = "en"
    settings.language2 = "zh-Hans"
    let pipeline = TranslationPipeline(settings: settings)

    let batch = try pipeline.makeBatch(text: "hi", selectionSource: .manual)

    XCTAssertEqual(batch.request.sourceLanguage, "en")
    XCTAssertEqual(batch.request.targetLanguage, "zh-Hans")
  }

  func testBatchKeepsOriginalTextAndAddsPreparedLLMInput() throws {
    let defaults = makeScratchDefaults()
    let settings = SettingsStore(defaults: defaults, providerFileStore: makeProviderFileStore(), allowsMockProvider: true)
    let pipeline = TranslationPipeline(settings: settings)
    let source = #"{"type":"error","message":"failed"}"#

    let batch = try pipeline.makeBatch(text: source, selectionSource: .manual)

    XCTAssertEqual(batch.request.text, source)
    XCTAssertTrue(batch.request.llmInputText.hasPrefix("```json\n"))
    XCTAssertTrue(batch.request.llmInputText.contains(source))
  }

  func testPipelineRejectsEmptyInput() async throws {
    let defaults = makeScratchDefaults()
    let settings = SettingsStore(defaults: defaults, providerFileStore: makeProviderFileStore())
    let pipeline = TranslationPipeline(settings: settings)

    do {
      _ = try await pipeline.translate(text: "   ", selectionSource: .manual)
      XCTFail("Expected empty input to throw")
    } catch let error as TranslationError {
      XCTAssertEqual(error, .emptyInput)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testBatchTranslationReturnsRowsForEnabledProviders() async throws {
    let defaults = makeScratchDefaults()
    let settings = SettingsStore(defaults: defaults, providerFileStore: makeProviderFileStore(), allowsMockProvider: true)
    enableOnly([.mock, .openAIResponses], in: settings)
    let pipeline = TranslationPipeline(settings: settings)

    let batch = try await pipeline.translateBatch(text: "hello", selectionSource: .manual)

    XCTAssertEqual(batch.entries.map(\.providerID), [.mock, .openAIResponses, .openAIChatCompletions, .anthropicMessages, .geminiGenerateContent, .systemDictionary])
    XCTAssertEqual(batch.successfulResults.map(\.providerID), [.mock])
    guard case .failure = batch.entries[1].status else {
      return XCTFail("Expected missing key failure for OpenAI Responses")
    }
    XCTAssertTrue(batch.entries[2...].allSatisfy(\.status.isDisabled))
  }

  func testBatchTranslationUsesCustomProviderName() async throws {
    let defaults = makeScratchDefaults()
    let settings = SettingsStore(defaults: defaults, providerFileStore: makeProviderFileStore(), allowsMockProvider: true)
    enableOnly([.mock], in: settings)
    var mock = settings.configuration(for: .mock)
    mock.displayName = "Local Mock"
    settings.updateConfiguration(mock)
    let pipeline = TranslationPipeline(settings: settings)

    let batch = try await pipeline.translateBatch(text: "hello", selectionSource: .manual)

    XCTAssertEqual(batch.successfulResults.first?.providerName, "Local Mock")
  }

  func testBatchTranslationIncludesCustomProviderInstance() async throws {
    let defaults = makeScratchDefaults()
    let settings = SettingsStore(defaults: defaults, providerFileStore: makeProviderFileStore(), allowsMockProvider: true)
    enableOnly([], in: settings)
    var custom = settings.addProvider(providerID: .openAIChatCompletions)
    custom.displayName = "Backup Chat"
    custom.isEnabled = true
    settings.updateConfiguration(custom)
    settings.setAPIKey("secret", forConfigurationID: custom.id)
    let pipeline = TranslationPipeline(settings: settings, providerFactory: { configuration in
      StaticTranslationProvider(providerID: configuration.providerID)
    })

    let batch = try await pipeline.translateBatch(text: "hello", selectionSource: .manual)

    let result = try XCTUnwrap(batch.successfulResults.first(where: { $0.providerConfigurationID == custom.id }))
    XCTAssertEqual(result.providerName, "Backup Chat")
    XCTAssertEqual(result.providerID, .openAIChatCompletions)
    XCTAssertTrue(batch.entries.contains(where: { $0.providerConfigurationID == custom.id }))
  }

  func testBatchTranslationCanBypassCacheForExplicitRetranslate() async throws {
    let defaults = makeScratchDefaults()
    let settings = SettingsStore(defaults: defaults, providerFileStore: makeProviderFileStore(), allowsMockProvider: true)
    enableOnly([.mock], in: settings)
    let counter = ProviderCallCounter()
    let pipeline = TranslationPipeline(settings: settings, providerFactory: { _ in
      CountingTranslationProvider(counter: counter)
    })

    let first = try await pipeline.translateBatch(text: "hello", selectionSource: .manual)
    let cached = try await pipeline.translateBatch(text: "hello", selectionSource: .manual)
    let refreshed = try await pipeline.translateBatch(text: "hello", selectionSource: .manual, bypassCache: true)

    XCTAssertEqual(counter.callCount, 2)
    XCTAssertEqual(first.successfulResults.first?.translatedText, "call 1")
    XCTAssertEqual(cached.successfulResults.first?.translatedText, "call 1")
    XCTAssertEqual(refreshed.successfulResults.first?.translatedText, "call 2")
  }

  func testBatchTranslationShowsDisabledRowsWhenNoProviderEnabled() async throws {
    let defaults = makeScratchDefaults()
    let settings = SettingsStore(defaults: defaults, providerFileStore: makeProviderFileStore(), allowsMockProvider: true)
    enableOnly([], in: settings)
    let pipeline = TranslationPipeline(settings: settings)

    let batch = try await pipeline.translateBatch(text: "hello", selectionSource: .manual)

    XCTAssertEqual(batch.entries.map(\.providerID), [.mock, .openAIResponses, .openAIChatCompletions, .anthropicMessages, .geminiGenerateContent, .systemDictionary])
    XCTAssertTrue(batch.entries.allSatisfy(\.status.isDisabled))
  }

  func testSingleResultTranslationRejectsNoEnabledProvider() async throws {
    let defaults = makeScratchDefaults()
    let settings = SettingsStore(defaults: defaults, providerFileStore: makeProviderFileStore(), allowsMockProvider: true)
    enableOnly([], in: settings)
    let pipeline = TranslationPipeline(settings: settings)

    do {
      _ = try await pipeline.translate(text: "hello", selectionSource: .manual)
      XCTFail("Expected no enabled provider to throw")
    } catch let error as TranslationError {
      XCTAssertEqual(error, .providerUnavailable("Enable at least one provider in LexiRay Settings."))
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testMakeBatchPinnedTargetOverridesAutoResolution() throws {
    let defaults = makeScratchDefaults()
    let settings = SettingsStore(defaults: defaults, providerFileStore: makeProviderFileStore(), allowsMockProvider: true)
    settings.language1 = "en"
    settings.language2 = "zh-Hans"
    // "Always: Japanese" target — auto would resolve English → zh-Hans.
    settings.pinnedTargetLanguage = "ja"
    let pipeline = TranslationPipeline(settings: settings)

    let batch = try pipeline.makeBatch(text: "hello", selectionSource: .manual)

    XCTAssertEqual(batch.request.sourceLanguage, "en")
    XCTAssertEqual(batch.request.targetLanguage, "ja")
  }

  func testMakeBatchPinnedSourceOverridesDetection() throws {
    let defaults = makeScratchDefaults()
    let settings = SettingsStore(defaults: defaults, providerFileStore: makeProviderFileStore(), allowsMockProvider: true)
    settings.language1 = "en"
    settings.language2 = "zh-Hans"
    // Force the source to French even though the text is English.
    settings.pinnedSourceLanguage = "fr"
    let pipeline = TranslationPipeline(settings: settings)

    let batch = try pipeline.makeBatch(text: "hello", selectionSource: .manual)

    XCTAssertEqual(batch.request.sourceLanguage, "fr")
  }

  func testMakeBatchOnceOverrideWinsOverPinned() throws {
    let defaults = makeScratchDefaults()
    let settings = SettingsStore(defaults: defaults, providerFileStore: makeProviderFileStore(), allowsMockProvider: true)
    settings.language1 = "en"
    settings.language2 = "zh-Hans"
    settings.pinnedTargetLanguage = "ja"
    let pipeline = TranslationPipeline(settings: settings)

    // Once override (target only) beats the pinned "ja"; nil source still
    // falls back to detection.
    let batch = try pipeline.makeBatch(
      text: "hello",
      selectionSource: .manual,
      directionOverride: PanelDirectionOverride.make(source: nil, target: "ko")
    )

    XCTAssertEqual(batch.request.sourceLanguage, "en")
    XCTAssertEqual(batch.request.targetLanguage, "ko")
  }

  func testMakeBatchOnceSourceOnlyFallsBackToPinnedTarget() throws {
    let defaults = makeScratchDefaults()
    let settings = SettingsStore(defaults: defaults, providerFileStore: makeProviderFileStore(), allowsMockProvider: true)
    settings.language1 = "en"
    settings.language2 = "zh-Hans"
    settings.pinnedTargetLanguage = "de"
    let pipeline = TranslationPipeline(settings: settings)

    // Once pins only the source; the target side falls through to pinned "de".
    let batch = try pipeline.makeBatch(
      text: "你好",
      selectionSource: .manual,
      directionOverride: PanelDirectionOverride.make(source: "ja", target: nil)
    )

    XCTAssertEqual(batch.request.sourceLanguage, "ja")
    XCTAssertEqual(batch.request.targetLanguage, "de")
  }

  func testResolvedDirectionChineseVariantPinnedTarget() {
    let defaults = makeScratchDefaults()
    let settings = SettingsStore(defaults: defaults, providerFileStore: makeProviderFileStore(), allowsMockProvider: true)
    settings.language1 = "en"
    settings.language2 = "zh-Hans"
    // Pin Traditional Chinese as the target for a Simplified Chinese source.
    settings.pinnedTargetLanguage = "zh-Hant"

    let direction = settings.resolvedDirection(for: "你好，今天天气不错。")

    XCTAssertEqual(direction.source, "zh-Hans")
    XCTAssertEqual(direction.target, "zh-Hant")
  }

  func testResolvedDirectionAutoMatchesLegacyBehavior() {
    let defaults = makeScratchDefaults()
    let settings = SettingsStore(defaults: defaults, providerFileStore: makeProviderFileStore(), allowsMockProvider: true)
    settings.language1 = "en"
    settings.language2 = "zh-Hans"

    // No pins, no override: identical to the old detect + pair resolution.
    let direction = settings.resolvedDirection(for: "hello")

    XCTAssertEqual(direction.source, "en")
    XCTAssertEqual(direction.target, "zh-Hans")
  }

  func testPinnedLanguagesPersistAcrossReload() {
    let defaults = makeScratchDefaults()
    let providerFileStore = makeProviderFileStore()
    let settings = SettingsStore(defaults: defaults, providerFileStore: providerFileStore, allowsMockProvider: true)
    settings.pinnedSourceLanguage = "fr"
    settings.pinnedTargetLanguage = "de"

    let reloaded = SettingsStore(defaults: defaults, providerFileStore: providerFileStore, allowsMockProvider: true)
    XCTAssertEqual(reloaded.pinnedSourceLanguage, "fr")
    XCTAssertEqual(reloaded.pinnedTargetLanguage, "de")

    // Clearing back to Auto removes the persisted value.
    reloaded.pinnedSourceLanguage = nil
    let recleared = SettingsStore(defaults: defaults, providerFileStore: providerFileStore, allowsMockProvider: true)
    XCTAssertNil(recleared.pinnedSourceLanguage)
    XCTAssertEqual(recleared.pinnedTargetLanguage, "de")
  }

  private func makeProviderFileStore() -> ProviderSettingsFileStore {
    let fileURL = makeScratchDirectory().appendingPathComponent("providers.json", isDirectory: false)
    return ProviderSettingsFileStore(fileURL: fileURL)
  }

  private func enableOnly(_ providers: Set<ProviderID>, in settings: SettingsStore) {
    for providerID in settings.visibleProviderIDs() {
      var configuration = settings.configuration(for: providerID)
      configuration.isEnabled = providers.contains(providerID)
      settings.updateConfiguration(configuration)
    }
  }
}

private struct StaticTranslationProvider: TranslationProvider {
  let id: ProviderID
  let name = "Static"

  init(providerID: ProviderID) {
    id = providerID
  }

  func translate(_ request: TranslationRequest) async throws -> TranslationResult {
    TranslationResult(
      request: request,
      providerID: id,
      providerName: name,
      translatedText: "translated \(request.text)",
      detectedLanguage: request.sourceLanguage
    )
  }
}

@MainActor
private final class ProviderCallCounter {
  var callCount = 0
}

@MainActor
private struct CountingTranslationProvider: TranslationProvider {
  let id: ProviderID = .mock
  let name = "Counting"
  let counter: ProviderCallCounter

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
