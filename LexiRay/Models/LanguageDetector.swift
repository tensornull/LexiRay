import Foundation
import NaturalLanguage

enum LanguageDetector {
  static let defaultLanguage1 = "en"
  static let defaultLanguage2 = "zh-Hans"

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

  private static func normalizedConfiguredLanguage(_ language: String, fallback: String) -> String {
    language.nonEmptyTrimmed ?? fallback
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

  private static func isChinese(_ language: String) -> Bool {
    language == "zh" || language.hasPrefix("zh-")
  }
}
