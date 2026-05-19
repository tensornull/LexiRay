import Foundation

struct TranslationCacheKey: Hashable {
  let providerConfigurationID: String
  let providerID: ProviderID
  let text: String
  let sourceLanguage: String?
  let targetLanguage: String
}

actor TranslationCache {
  private var values: [TranslationCacheKey: TranslationResult] = [:]

  func value(for key: TranslationCacheKey) -> TranslationResult? {
    values[key]
  }

  func insert(_ result: TranslationResult, for key: TranslationCacheKey) {
    values[key] = result
  }

  func removeAll() {
    values.removeAll()
  }
}
