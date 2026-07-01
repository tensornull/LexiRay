@testable import LexiRay
import XCTest

final class LanguageDetectorTests: XCTestCase {
  func testDominantLanguageDetectsEnglish() {
    XCTAssertEqual(LanguageDetector.dominantLanguageCode(for: "A clean translation app for macOS"), "en")
  }

  func testMixedChineseWithLongEnglishQuoteDetectsChinese() {
    let text = "对此我们非常抱歉。昨晚凌晨出现的类似 \"Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits.\" 的提示，主要是受到 Claude 官方资源波动的影响。"
    XCTAssertEqual(
      LanguageDetector.sourceLanguageCode(for: text, language1: "en", language2: "zh-Hans"),
      "zh-Hans"
    )
  }

  func testMixedChineseQuoteRoutesToEnglishTarget() {
    let text = "对此我们非常抱歉，类似 \"Your credit balance is too low to access the Anthropic API.\" 的提示，受到 Claude 资源波动影响。"
    let source = LanguageDetector.sourceLanguageCode(for: text, language1: "en", language2: "zh-Hans")
    XCTAssertEqual(
      LanguageDetector.targetLanguage(for: source, language1: "en", language2: "zh-Hans", autoSwitch: true),
      "en"
    )
  }

  func testCJKOverrideHonorsConfiguredTraditionalVariant() {
    let text = "對此我們非常抱歉，類似 \"too low to access the Anthropic API\" 的提示。"
    XCTAssertEqual(
      LanguageDetector.sourceLanguageCode(for: text, language1: "en", language2: "zh-Hant"),
      "zh-Hant"
    )
  }

  func testCodeHeavyTextWithFewChineseCommentsStaysEnglish() {
    let text = "let user = fetchCurrentUser() // 获取用户 and return the active session token immediately to the caller"
    XCTAssertEqual(
      LanguageDetector.sourceLanguageCode(for: text, language1: "en", language2: "zh-Hans"),
      LanguageDetector.dominantLanguageCode(for: text)
    )
  }

  func testSingleChineseCharacterDefersToNaturalLanguage() {
    XCTAssertEqual(
      LanguageDetector.sourceLanguageCode(for: "好", language1: "en", language2: "zh-Hans"),
      LanguageDetector.dominantLanguageCode(for: "好")
    )
  }

  func testAccentedLatinTextDoesNotTriggerCJKOverride() {
    let text = "Café résumé naïve coördinate jalapeño"
    XCTAssertEqual(
      LanguageDetector.sourceLanguageCode(for: text, language1: "en", language2: "zh-Hans"),
      LanguageDetector.dominantLanguageCode(for: text)
    )
  }

  func testJapaneseWithEmbeddedEnglishDetectsJapanese() {
    let text = "申し訳ございません。\"Your credit balance is too low\" というエラーが表示されました。"
    XCTAssertEqual(
      LanguageDetector.sourceLanguageCode(for: text, language1: "en", language2: "zh-Hans"),
      "ja"
    )
  }

  func testKoreanWithEmbeddedEnglishDetectsKorean() {
    let text = "죄송합니다. \"Your credit balance is too low\" 오류가 표시되었습니다."
    XCTAssertEqual(
      LanguageDetector.sourceLanguageCode(for: text, language1: "en", language2: "zh-Hans"),
      "ko"
    )
  }

  func testOtherLanguageReturnsOppositePairMember() {
    XCTAssertEqual(LanguageDetector.otherLanguage(of: "zh-Hans", language1: "en", language2: "zh-Hans"), "en")
    XCTAssertEqual(LanguageDetector.otherLanguage(of: "en", language1: "en", language2: "zh-Hans"), "zh-Hans")
    // Chinese variants are treated as the same side of the pair.
    XCTAssertEqual(LanguageDetector.otherLanguage(of: "zh-Hant", language1: "en", language2: "zh-Hans"), "en")
    // Unknown language falls back to language1.
    XCTAssertEqual(LanguageDetector.otherLanguage(of: "fr", language1: "en", language2: "zh-Hans"), "en")
  }

  func testShortEnglishSourceLanguageUsesConfiguredEnglish() {
    for text in ["hi", "Hi", "hi!", "ok", "hi2"] {
      XCTAssertEqual(
        LanguageDetector.sourceLanguageCode(for: text, language1: "en", language2: "zh-Hans"),
        "en"
      )
    }
  }

  func testLongerTextStillUsesNaturalLanguageDetection() {
    XCTAssertEqual(
      LanguageDetector.sourceLanguageCode(
        for: "A clean translation app for macOS",
        language1: "en",
        language2: "zh-Hans"
      ),
      "en"
    )
  }

  func testShortTextEnglishOverrideRequiresEnglishLanguage1() {
    XCTAssertEqual(
      LanguageDetector.sourceLanguageCode(for: "hi", language1: "fr", language2: "zh-Hans"),
      LanguageDetector.dominantLanguageCode(for: "hi")
    )
  }

  func testShortTextEnglishOverrideIgnoresNumericOnlyText() {
    XCTAssertEqual(
      LanguageDetector.sourceLanguageCode(for: "123", language1: "en", language2: "zh-Hans"),
      LanguageDetector.dominantLanguageCode(for: "123")
    )
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
