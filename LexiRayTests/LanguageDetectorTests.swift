@testable import LexiRay
import XCTest

final class LanguageDetectorTests: XCTestCase {
  func testDominantLanguageDetectsEnglish() {
    XCTAssertEqual(LanguageDetector.dominantLanguageCode(for: "A clean translation app for macOS"), "en")
  }

  func testDefaultTargetLanguageUsesEnglishForChineseSource() {
    XCTAssertEqual(
      LanguageDetector.defaultTargetLanguage(for: "zh-Hans", locale: Locale(identifier: "zh_CN")),
      "en"
    )
  }

  func testDefaultTargetLanguageUsesChineseForChineseUserLocale() {
    XCTAssertEqual(
      LanguageDetector.defaultTargetLanguage(for: "en", locale: Locale(identifier: "zh_CN")),
      "zh-Hans"
    )
  }
}
