@testable import LexiRay
import XCTest

@MainActor
final class TranslationPipelineTests: XCTestCase {
  func testMockProviderReturnsTranslationResult() async throws {
    let defaults = try XCTUnwrap(UserDefaults(suiteName: "LexiRayPipelineTests-\(UUID().uuidString)"))
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
    let defaults = try XCTUnwrap(UserDefaults(suiteName: "LexiRayPipelineTests-\(UUID().uuidString)"))
    let settings = SettingsStore(defaults: defaults, providerFileStore: makeProviderFileStore(), allowsMockProvider: true)
    enableOnly([.mock], in: settings)
    settings.language1 = "en"
    settings.language2 = "zh-Hans"
    let pipeline = TranslationPipeline(settings: settings)

    let result = try await pipeline.translate(text: "你好，这是一个翻译测试。", selectionSource: .manual)

    XCTAssertEqual(result.request.targetLanguage, "en")
  }

  func testPipelineRejectsEmptyInput() async throws {
    let defaults = try XCTUnwrap(UserDefaults(suiteName: "LexiRayPipelineTests-\(UUID().uuidString)"))
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
    let defaults = try XCTUnwrap(UserDefaults(suiteName: "LexiRayPipelineTests-\(UUID().uuidString)"))
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
    let defaults = try XCTUnwrap(UserDefaults(suiteName: "LexiRayPipelineTests-\(UUID().uuidString)"))
    let settings = SettingsStore(defaults: defaults, providerFileStore: makeProviderFileStore(), allowsMockProvider: true)
    enableOnly([.mock], in: settings)
    var mock = settings.configuration(for: .mock)
    mock.displayName = "Local Mock"
    settings.updateConfiguration(mock)
    let pipeline = TranslationPipeline(settings: settings)

    let batch = try await pipeline.translateBatch(text: "hello", selectionSource: .manual)

    XCTAssertEqual(batch.successfulResults.first?.providerName, "Local Mock")
  }

  func testBatchTranslationShowsDisabledRowsWhenNoProviderEnabled() async throws {
    let defaults = try XCTUnwrap(UserDefaults(suiteName: "LexiRayPipelineTests-\(UUID().uuidString)"))
    let settings = SettingsStore(defaults: defaults, providerFileStore: makeProviderFileStore(), allowsMockProvider: true)
    enableOnly([], in: settings)
    let pipeline = TranslationPipeline(settings: settings)

    let batch = try await pipeline.translateBatch(text: "hello", selectionSource: .manual)

    XCTAssertEqual(batch.entries.map(\.providerID), [.mock, .openAIResponses, .openAIChatCompletions, .anthropicMessages, .geminiGenerateContent, .systemDictionary])
    XCTAssertTrue(batch.entries.allSatisfy(\.status.isDisabled))
  }

  func testSingleResultTranslationRejectsNoEnabledProvider() async throws {
    let defaults = try XCTUnwrap(UserDefaults(suiteName: "LexiRayPipelineTests-\(UUID().uuidString)"))
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

  private func makeProviderFileStore() -> ProviderSettingsFileStore {
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("LexiRayPipelineTests-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("providers.json", isDirectory: false)
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
