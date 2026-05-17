import Foundation

struct TranslationRequest: Equatable, Hashable {
  let text: String
  let sourceLanguage: String?
  let targetLanguage: String
  let selectionSource: SelectionSource
}

struct TranslationResult: Equatable, Identifiable {
  let id = UUID()
  let request: TranslationRequest
  let providerID: ProviderID
  let providerName: String
  let translatedText: String
  let detectedLanguage: String?
  let createdAt: Date

  init(
    request: TranslationRequest,
    providerID: ProviderID,
    providerName: String,
    translatedText: String,
    detectedLanguage: String? = nil,
    createdAt: Date = Date()
  ) {
    self.request = request
    self.providerID = providerID
    self.providerName = providerName
    self.translatedText = translatedText
    self.detectedLanguage = detectedLanguage
    self.createdAt = createdAt
  }
}

enum TranslationError: LocalizedError, Equatable {
  case emptyInput
  case missingAPIKey
  case providerUnavailable(String)
  case invalidResponse
  case network(String)

  var errorDescription: String? {
    switch self {
    case .emptyInput:
      "No selected text"
    case .missingAPIKey:
      "OpenAI-compatible provider needs an API key"
    case let .providerUnavailable(message):
      message
    case .invalidResponse:
      "The provider returned an invalid response"
    case let .network(message):
      message
    }
  }
}

enum PanelState: Equatable {
  case idle
  case loading(String)
  case result(TranslationResult)
  case error(String)
}
