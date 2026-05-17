import Foundation
import NaturalLanguage

enum LanguageDetector {
  static func dominantLanguageCode(for text: String) -> String? {
    guard text.trimmedForQuery.count >= 2 else {
      return nil
    }

    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    return recognizer.dominantLanguage?.rawValue
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
}
