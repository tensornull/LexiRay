import Foundation
import NaturalLanguage

enum LanguageDetector {
  static let defaultLanguage1 = "en"
  static let defaultLanguage2 = "zh-Hans"

  static func sourceLanguageCode(
    for text: String,
    language1 rawLanguage1: String = defaultLanguage1,
    language2 rawLanguage2: String = defaultLanguage2
  ) -> String? {
    let language1 = normalizedConfiguredLanguage(rawLanguage1, fallback: defaultLanguage1)
    let language2 = normalizedConfiguredLanguage(rawLanguage2, fallback: defaultLanguage2)
    if let shortEnglishLanguage = shortEnglishSourceLanguage(for: text, language1: language1) {
      return shortEnglishLanguage
    }

    if let cjkLanguage = cjkScriptSourceLanguage(for: text, language1: language1, language2: language2) {
      return cjkLanguage
    }

    return dominantLanguageCode(for: text)
  }

  static func dominantLanguageCode(for text: String) -> String? {
    guard text.trimmedForQuery.count >= 2 else {
      return nil
    }

    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    return recognizer.dominantLanguage?.rawValue
  }

  static func targetLanguage(
    for sourceLanguage: String?,
    language1 rawLanguage1: String,
    language2 rawLanguage2: String,
    autoSwitch: Bool
  ) -> String {
    let language1 = normalizedConfiguredLanguage(rawLanguage1, fallback: defaultLanguage1)
    let language2 = normalizedConfiguredLanguage(rawLanguage2, fallback: defaultLanguage2)

    guard autoSwitch else {
      return language2
    }

    if languageMatches(sourceLanguage, configuredLanguage: language1) {
      return language2
    }

    if languageMatches(sourceLanguage, configuredLanguage: language2) {
      return language1
    }

    return language2
  }

  static func defaultTargetLanguage(for sourceLanguage: String?, locale: Locale = .current) -> String {
    let preferredLanguage = locale.language.languageCode?.identifier ?? "en"

    if sourceLanguage == "zh-Hans" || sourceLanguage == "zh-Hant" || sourceLanguage == "zh" {
      return "en"
    }

    if preferredLanguage.hasPrefix("zh") {
      return "zh-Hans"
    }

    return preferredLanguage
  }

  static func directionLabel(sourceLanguage: String?, targetLanguage: String) -> String {
    "\(sourceLanguage?.nonEmptyTrimmed ?? "auto") -> \(targetLanguage)"
  }

  /// Returns the configured language-pair member that is not `language`.
  /// Falls back to `language1` when `language` matches neither side, so a manual
  /// direction swap always lands on a valid target.
  static func otherLanguage(of language: String, language1 rawLanguage1: String, language2 rawLanguage2: String) -> String {
    let language1 = normalizedConfiguredLanguage(rawLanguage1, fallback: defaultLanguage1)
    let language2 = normalizedConfiguredLanguage(rawLanguage2, fallback: defaultLanguage2)

    if languageMatches(language, configuredLanguage: language1) {
      return language2
    }
    if languageMatches(language, configuredLanguage: language2) {
      return language1
    }
    return language1
  }

  private static func normalizedConfiguredLanguage(_ language: String, fallback: String) -> String {
    language.nonEmptyTrimmed ?? fallback
  }

  private static func shortEnglishSourceLanguage(for text: String, language1: String) -> String? {
    guard languageBase(language1) == "en",
          let token = shortASCIILatinToken(from: text),
          (1 ... 6).contains(token.count)
    else {
      return nil
    }

    return language1
  }

  private static func shortASCIILatinToken(from text: String) -> String? {
    var candidate = text.trimmedForQuery
    while let lastScalar = candidate.unicodeScalars.last,
          shortTextTrailingPunctuation.contains(lastScalar)
    {
      candidate.removeLast()
    }

    guard !candidate.isEmpty,
          candidate.unicodeScalars.allSatisfy(isASCIIAlphanumeric),
          candidate.unicodeScalars.contains(where: isASCIIAlphabetic)
    else {
      return nil
    }

    return candidate
  }

  private static var shortTextTrailingPunctuation: CharacterSet {
    CharacterSet(charactersIn: ".!?,")
  }

  private static func isASCIIAlphabetic(_ scalar: UnicodeScalar) -> Bool {
    (65 ... 90).contains(Int(scalar.value)) || (97 ... 122).contains(Int(scalar.value))
  }

  private static func isASCIIAlphanumeric(_ scalar: UnicodeScalar) -> Bool {
    isASCIIAlphabetic(scalar) || (48 ... 57).contains(Int(scalar.value))
  }

  /// CJK characters are information-dense: one CJK character ≈ one word ≈ ~4 Latin letters.
  /// When the CJK character count (in word-equivalents) is at least the Latin letter count,
  /// treat the source as a CJK language. This resists NLLanguageRecognizer mis-classifying a
  /// predominantly-Chinese message as English just because it embeds a long Latin-script quote.
  private static func cjkScriptSourceLanguage(for text: String, language1: String, language2: String) -> String? {
    var han = 0, kana = 0, hangul = 0, latin = 0
    for scalar in text.unicodeScalars {
      let value = Int(scalar.value)
      if isHanScalar(value) {
        han += 1
      } else if isKanaScalar(value) {
        kana += 1
      } else if isHangulScalar(value) {
        hangul += 1
      } else if isASCIIAlphabetic(scalar) {
        latin += 1
      }
    }

    let cjk = han + kana + hangul
    guard cjk >= 2, Double(cjk) >= Double(latin) / cjkLatinWordEquivalent else {
      return nil
    }

    if kana > hangul {
      return "ja"
    }
    if hangul >= han {
      return "ko"
    }
    return configuredChineseVariant(language1: language1, language2: language2)
  }

  private static func configuredChineseVariant(language1: String, language2: String) -> String {
    if isChinese(language1) {
      return language1
    }
    if isChinese(language2) {
      return language2
    }
    return defaultLanguage2
  }

  private static var cjkLatinWordEquivalent: Double {
    4.0
  }

  private static func isHanScalar(_ value: Int) -> Bool {
    (0x4E00 ... 0x9FFF).contains(value) // CJK Unified Ideographs
      || (0x3400 ... 0x4DBF).contains(value) // CJK Extension A
      || (0xF900 ... 0xFAFF).contains(value) // CJK Compatibility Ideographs
  }

  private static func isKanaScalar(_ value: Int) -> Bool {
    (0x3040 ... 0x30FF).contains(value) // Hiragana + Katakana
  }

  private static func isHangulScalar(_ value: Int) -> Bool {
    (0xAC00 ... 0xD7A3).contains(value) // Hangul Syllables
  }

  private static func languageMatches(_ sourceLanguage: String?, configuredLanguage: String) -> Bool {
    guard let sourceLanguage = sourceLanguage?.nonEmptyTrimmed else {
      return false
    }

    if sourceLanguage == configuredLanguage {
      return true
    }

    if isChinese(sourceLanguage), isChinese(configuredLanguage) {
      return true
    }

    return sourceLanguage.split(separator: "-").first == configuredLanguage.split(separator: "-").first
  }

  private static func languageBase(_ language: String) -> String {
    String(language.split(separator: "-").first ?? "").lowercased()
  }

  private static func isChinese(_ language: String) -> Bool {
    language == "zh" || language.hasPrefix("zh-")
  }
}
