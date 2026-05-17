@testable import LexiRay
import XCTest

final class TranslationCacheTests: XCTestCase {
  func testCacheStoresResult() async {
    let cache = TranslationCache()
    let request = TranslationRequest(
      text: "hello",
      sourceLanguage: "en",
      targetLanguage: "zh-Hans",
      selectionSource: .manual
    )
    let result = TranslationResult(
      request: request,
      providerID: .mock,
      providerName: "Mock",
      translatedText: "hello"
    )
    let key = TranslationCacheKey(
      providerID: .mock,
      text: "hello",
      sourceLanguage: "en",
      targetLanguage: "zh-Hans"
    )

    await cache.insert(result, for: key)
    let cached = await cache.value(for: key)

    XCTAssertEqual(cached?.translatedText, "hello")
  }
}
