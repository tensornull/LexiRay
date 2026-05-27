import Foundation

@MainActor
final class TranslationPipeline {
  private let settings: SettingsStore
  private let cache: TranslationCache
  private let providerFactory: ((ProviderConfiguration) throws -> TranslationProvider)?

  init(
    settings: SettingsStore,
    cache: TranslationCache = TranslationCache(),
    providerFactory: ((ProviderConfiguration) throws -> TranslationProvider)? = nil
  ) {
    self.settings = settings
    self.cache = cache
    self.providerFactory = providerFactory
  }

  func translate(text rawText: String, selectionSource: SelectionSource, bypassCache: Bool = false) async throws -> TranslationResult {
    let batch = try await translateBatch(text: rawText, selectionSource: selectionSource, bypassCache: bypassCache)
    if let result = batch.successfulResults.first {
      return result
    }

    let message = batch.entries.allSatisfy(\.status.isDisabled) ? "Enable at least one provider in LexiRay Settings." : batch.entries.compactMap { entry -> String? in
      if case let .failure(message) = entry.status {
        return message
      }
      return nil
    }.first ?? "No provider returned a translation"
    throw TranslationError.providerUnavailable(message)
  }

  func makeBatch(text rawText: String, selectionSource: SelectionSource) throws -> TranslationBatch {
    guard let text = rawText.nonEmptyTrimmed else {
      throw TranslationError.emptyInput
    }

    let sourceLanguage = LanguageDetector.dominantLanguageCode(for: text)
    let targetLanguage = settings.resolvedTargetLanguage(for: sourceLanguage)
    let llmInputText = SourceMarkdownPreparer.prepare(text)

    let request = TranslationRequest(
      text: text,
      llmInputText: llmInputText,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      selectionSource: selectionSource
    )

    let configurations = settings.visibleProviderConfigurations()

    return TranslationBatch(
      request: request,
      entries: configurations.map { configuration in
        ProviderTranslationEntry(
          providerConfigurationID: configuration.id,
          providerID: configuration.providerID,
          providerName: configuration.effectiveDisplayName,
          status: configuration.isEnabled ? .translating : .disabled
        )
      }
    )
  }

  func translateBatch(
    text rawText: String,
    selectionSource: SelectionSource,
    bypassCache: Bool = false,
    onUpdate: (@MainActor (TranslationBatch) -> Void)? = nil
  ) async throws -> TranslationBatch {
    var batch = try makeBatch(text: rawText, selectionSource: selectionSource)
    let request = batch.request
    let tasks = batch.entries.filter(\.isTranslatable).map { entry in
      Task { @MainActor in
        await self.translate(entry, request: request, bypassCache: bypassCache)
      }
    }

    for task in tasks {
      let entry = await task.value
      batch.update(entry)
      onUpdate?(batch)
    }

    return batch
  }

  func translate(
    _ entry: ProviderTranslationEntry,
    request: TranslationRequest,
    bypassCache: Bool = false
  ) async -> ProviderTranslationEntry {
    await stream(entry, request: request, bypassCache: bypassCache, onUpdate: nil)
  }

  func stream(
    _ entry: ProviderTranslationEntry,
    request: TranslationRequest,
    bypassCache: Bool = false,
    onUpdate: (@MainActor (ProviderTranslationEntry) -> Void)?
  ) async -> ProviderTranslationEntry {
    do {
      let result = try await translate(
        request: request,
        providerConfigurationID: entry.providerConfigurationID,
        providerID: entry.providerID,
        providerName: entry.providerName,
        bypassCache: bypassCache,
        onPartial: { partialText in
          onUpdate?(entry.updating(status: .streaming(partialText)))
        }
      )
      return entry.updating(status: .success(result))
    } catch {
      return entry.updating(status: .failure(error.localizedDescription))
    }
  }

  private func translate(
    request: TranslationRequest,
    providerConfigurationID: String,
    providerID _: ProviderID,
    providerName: String,
    bypassCache: Bool = false,
    onPartial: (@MainActor (String) -> Void)? = nil
  ) async throws -> TranslationResult {
    let provider = try makeProvider(forConfigurationID: providerConfigurationID)
    let text = request.text
    let cacheKey = TranslationCacheKey(
      providerConfigurationID: providerConfigurationID,
      providerID: provider.id,
      text: text,
      sourceLanguage: request.sourceLanguage,
      targetLanguage: request.targetLanguage
    )

    if !bypassCache, let cached = await cache.value(for: cacheKey) {
      AppLog.translation.debug("Using cached result for provider \(provider.name, privacy: .public)")
      return cached.withProviderIdentity(providerConfigurationID: providerConfigurationID, providerName: providerName)
    }

    let stream = try await provider.streamTranslation(request)
    var finalResult: TranslationResult?

    for try await update in stream {
      switch update {
      case let .partial(partialText):
        if !partialText.isEmpty {
          onPartial?(partialText)
        }
      case let .completed(result):
        finalResult = result.withProviderIdentity(providerConfigurationID: providerConfigurationID, providerName: providerName)
      }
    }

    guard let result = finalResult else {
      throw TranslationError.invalidResponse
    }

    await cache.insert(result, for: cacheKey)
    return result
  }

  private func makeProvider(forConfigurationID configurationID: String) throws -> TranslationProvider {
    guard let providerConfiguration = settings.configuration(for: configurationID) else {
      throw TranslationError.providerUnavailable("Provider configuration was removed")
    }
    let id = providerConfiguration.providerID
    guard providerConfiguration.isEnabled else {
      throw TranslationError.providerUnavailable("\(id.displayName) is disabled")
    }

    if id.needsAPIKey, settings.apiKey(forConfigurationID: configurationID).trimmedForQuery.isEmpty {
      throw TranslationError.missingAPIKey
    }

    if let provider = try providerFactory?(providerConfiguration) {
      return provider
    }

    switch id {
    case .mock:
      return MockTranslationProvider()
    case .systemDictionary:
      return SystemDictionaryProvider()
    case .openAIChatCompletions:
      return OpenAIChatCompletionsProvider(
        configuration: makeLLMConfiguration(for: providerConfiguration)
      )
    case .openAIResponses:
      return OpenAIResponsesProvider(
        configuration: makeLLMConfiguration(for: providerConfiguration)
      )
    case .anthropicMessages:
      return AnthropicMessagesProvider(
        configuration: makeLLMConfiguration(for: providerConfiguration)
      )
    case .geminiGenerateContent:
      return GeminiGenerateContentProvider(
        configuration: makeLLMConfiguration(for: providerConfiguration)
      )
    }
  }

  private func makeLLMConfiguration(for configuration: ProviderConfiguration) -> LLMProviderConfiguration {
    LLMProviderConfiguration(
      provider: configuration.providerID,
      baseURL: configuration.baseURL,
      apiKey: settings.apiKey(forConfigurationID: configuration.id),
      model: configuration.model,
      advancedParameters: configuration.advancedParameters
    )
  }
}
