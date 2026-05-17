import Foundation

@MainActor
final class TranslationPipeline {
  private let settings: SettingsStore
  private let cache: TranslationCache

  init(settings: SettingsStore, cache: TranslationCache = TranslationCache()) {
    self.settings = settings
    self.cache = cache
  }

  func translate(text rawText: String, selectionSource: SelectionSource) async throws -> TranslationResult {
    guard let text = rawText.nonEmptyTrimmed else {
      throw TranslationError.emptyInput
    }

    let sourceLanguage = LanguageDetector.dominantLanguageCode(for: text)
    let targetLanguage = settings.targetLanguage.nonEmptyTrimmed
      ?? LanguageDetector.defaultTargetLanguage(for: sourceLanguage)

    let request = TranslationRequest(
      text: text,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      selectionSource: selectionSource
    )

    let provider = makeProvider(for: settings.preferredProvider)
    let cacheKey = TranslationCacheKey(
      providerID: provider.id,
      text: text,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage
    )

    if let cached = await cache.value(for: cacheKey) {
      AppLog.translation.debug("Using cached result for provider \(provider.name, privacy: .public)")
      return cached
    }

    let result = try await provider.translate(request)
    await cache.insert(result, for: cacheKey)
    return result
  }

  private func makeProvider(for id: ProviderID) -> TranslationProvider {
    switch id {
    case .mock:
      MockTranslationProvider()
    case .systemDictionary:
      SystemDictionaryProvider()
    case .openAICompatible:
      OpenAICompatibleProvider(
        configuration: OpenAICompatibleConfiguration(
          baseURL: settings.openAIBaseURL,
          apiKey: settings.openAIAPIKey,
          model: settings.openAIModel
        )
      )
    }
  }
}
