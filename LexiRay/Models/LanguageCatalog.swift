import Foundation

/// Whether a language pick applies only to the current translation ("Once") or
/// becomes the persistent default ("Always"), mirroring HapiGo's mode switch.
enum LanguageSelectionMode: Hashable {
  case once
  case always
}

struct LanguageOption: Identifiable, Hashable {
  let code: String
  var id: String {
    code
  }

  var displayName: String {
    LanguageCatalog.displayName(for: code)
  }
}

/// Curated language list and display names for the panel's source/target
/// pickers. There is no existing language catalog in the app, so this is the
/// single source of truth.
enum LanguageCatalog {
  /// Shortlist shown directly in the menu (mirrors HapiGo's common languages).
  static let common: [LanguageOption] = [
    "en", "zh-Hans", "zh-Hant", "fr", "es", "ru", "de", "ja", "ko"
  ].map { LanguageOption(code: $0) }

  /// Long tail tucked under an "Others" submenu.
  static let others: [LanguageOption] = [
    "it", "pt", "nl", "pl", "tr", "ar", "hi", "th",
    "vi", "id", "sv", "uk", "cs", "el", "he", "ro",
    "hu", "fi", "da", "nb"
  ].map { LanguageOption(code: $0) }

  /// English names keep the picker consistent with the app's English chrome and
  /// match HapiGo's wording; the long tail falls back to the system's English
  /// localization.
  private static let displayNameOverrides: [String: String] = [
    "en": "English",
    "zh-Hans": "Simplified Chinese",
    "zh-Hant": "Traditional Chinese",
    "fr": "French",
    "es": "Spanish",
    "ru": "Russian",
    "de": "German",
    "ja": "Japanese",
    "ko": "Korean"
  ]

  private static let englishLocale = Locale(identifier: "en_US")

  static func displayName(for code: String) -> String {
    if let override = displayNameOverrides[code] {
      return override
    }
    return englishLocale.localizedString(forIdentifier: code) ?? code
  }
}
