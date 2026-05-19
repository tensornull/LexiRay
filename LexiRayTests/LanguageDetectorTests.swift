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

  func testAutoSwitchesEnglishToChinese() {
    XCTAssertEqual(
      LanguageDetector.targetLanguage(for: "en", language1: "en", language2: "zh-Hans", autoSwitch: true),
      "zh-Hans"
    )
  }

  func testAutoSwitchesChineseVariantsToEnglish() {
    XCTAssertEqual(
      LanguageDetector.targetLanguage(for: "zh-Hant", language1: "en", language2: "zh-Hans", autoSwitch: true),
      "en"
    )
  }

  func testUnknownLanguageFallsBackToLanguage2() {
    XCTAssertEqual(
      LanguageDetector.targetLanguage(for: nil, language1: "en", language2: "zh-Hans", autoSwitch: true),
      "zh-Hans"
    )
  }

  func testDisabledAutoSwitchAlwaysUsesLanguage2() {
    XCTAssertEqual(
      LanguageDetector.targetLanguage(for: "zh-Hans", language1: "en", language2: "ja", autoSwitch: false),
      "ja"
    )
  }
}
