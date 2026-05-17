@testable import LexiRay
import XCTest

@MainActor
final class TranslationPipelineTests: XCTestCase {
  func testMockProviderReturnsTranslationResult() async throws {
    let defaults = try XCTUnwrap(UserDefaults(suiteName: "LexiRayPipelineTests-\(UUID().uuidString)"))
    let settings = SettingsStore(defaults: defaults)
    settings.preferredProvider = .mock
    settings.targetLanguage = "zh-Hans"
    let pipeline = TranslationPipeline(settings: settings)

    let result = try await pipeline.translate(text: "hello", selectionSource: .manual)

    XCTAssertEqual(result.providerID, .mock)
    XCTAssertTrue(result.translatedText.contains("hello"))
    XCTAssertEqual(result.request.selectionSource, .manual)
  }

  func testPipelineRejectsEmptyInput() async throws {
    let defaults = try XCTUnwrap(UserDefaults(suiteName: "LexiRayPipelineTests-\(UUID().uuidString)"))
    let settings = SettingsStore(defaults: defaults)
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
}
