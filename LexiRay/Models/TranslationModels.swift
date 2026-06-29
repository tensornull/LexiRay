import Foundation

/// Explicit translation direction that overrides automatic source detection,
/// e.g. when the user taps the panel direction badge to swap languages.
struct PanelDirectionOverride: Equatable {
  let source: String?
  let target: String
}

struct TranslationRequest: Equatable, Hashable {
  let text: String
  let llmInputText: String
  let sourceLanguage: String?
  let targetLanguage: String
  let selectionSource: SelectionSource

  init(
    text: String,
    llmInputText: String? = nil,
    sourceLanguage: String?,
    targetLanguage: String,
    selectionSource: SelectionSource
  ) {
    self.text = text
    self.llmInputText = llmInputText ?? text
    self.sourceLanguage = sourceLanguage
    self.targetLanguage = targetLanguage
    self.selectionSource = selectionSource
  }
}

struct TranslationResult: Equatable, Identifiable {
  let id = UUID()
  let request: TranslationRequest
  let providerConfigurationID: String
  let providerID: ProviderID
  let providerName: String
  let translatedText: String
  let detectedLanguage: String?
  let createdAt: Date

  init(
    request: TranslationRequest,
    providerConfigurationID: String? = nil,
    providerID: ProviderID,
    providerName: String,
    translatedText: String,
    detectedLanguage: String? = nil,
    createdAt: Date = Date()
  ) {
    self.request = request
    self.providerConfigurationID = providerConfigurationID ?? providerID.rawValue
    self.providerID = providerID
    self.providerName = providerName
    self.translatedText = translatedText
    self.detectedLanguage = detectedLanguage
    self.createdAt = createdAt
  }

  func withProviderName(_ providerName: String) -> TranslationResult {
    withProviderIdentity(providerConfigurationID: providerConfigurationID, providerName: providerName)
  }

  func withProviderIdentity(providerConfigurationID: String, providerName: String) -> TranslationResult {
    TranslationResult(
      request: request,
      providerConfigurationID: providerConfigurationID,
      providerID: providerID,
      providerName: providerName,
      translatedText: translatedText,
      detectedLanguage: detectedLanguage,
      createdAt: createdAt
    )
  }
}

enum TranslationError: LocalizedError, Equatable {
  case emptyInput
  case missingAPIKey
  case providerUnavailable(String)
  case invalidResponse
  case network(String)
  case ocrUnavailable(String)

  var errorDescription: String? {
    switch self {
    case .emptyInput:
      "No selected text"
    case .missingAPIKey:
      "Add an API key in LexiRay Settings, then translate again."
    case let .providerUnavailable(message):
      message
    case .invalidResponse:
      "The provider returned an invalid response"
    case let .network(message):
      message
    case let .ocrUnavailable(message):
      message
    }
  }
}

struct PanelLoadingState: Equatable {
  let title: String
  let preview: String?
}

struct TranslationBatch: Equatable, Identifiable {
  let id = UUID()
  let request: TranslationRequest
  var entries: [ProviderTranslationEntry]

  var successfulResults: [TranslationResult] {
    entries.compactMap(\.result)
  }

  mutating func update(_ entry: ProviderTranslationEntry) {
    guard let index = entries.firstIndex(where: { $0.providerConfigurationID == entry.providerConfigurationID }) else {
      return
    }
    entries[index] = entry
  }
}

struct ProviderTranslationEntry: Equatable, Identifiable {
  let providerConfigurationID: String
  let providerID: ProviderID
  let providerName: String
  var status: ProviderTranslationStatus

  var id: String {
    providerConfigurationID
  }

  var result: TranslationResult? {
    if case let .success(result) = status {
      return result
    }
    return nil
  }

  var isTranslatable: Bool {
    if case .translating = status {
      return true
    }
    return false
  }

  func updating(status: ProviderTranslationStatus) -> ProviderTranslationEntry {
    ProviderTranslationEntry(
      providerConfigurationID: providerConfigurationID,
      providerID: providerID,
      providerName: providerName,
      status: status
    )
  }
}

enum ProviderTranslationStatus: Equatable {
  case disabled
  case translating
  case streaming(String)
  case success(TranslationResult)
  case failure(String)

  var isDisabled: Bool {
    if case .disabled = self {
      return true
    }
    return false
  }
}

enum TranslationStreamUpdate: Equatable {
  case partial(String)
  case completed(TranslationResult)
}

enum PanelState: Equatable {
  case idle
  case loading(PanelLoadingState)
  case batch(TranslationBatch)
  case result(TranslationResult)
  case error(String)
}
