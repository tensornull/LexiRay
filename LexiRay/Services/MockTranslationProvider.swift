import Foundation

struct MockTranslationProvider: TranslationProvider {
  let id: ProviderID = .mock
  let name = "Mock"

  func translate(_ request: TranslationRequest) async throws -> TranslationResult {
    guard let text = request.text.nonEmptyTrimmed else {
      throw TranslationError.emptyInput
    }

    let translatedText = "LexiRay mock translation:\n\(text)"

    return TranslationResult(
      request: request,
      providerID: id,
      providerName: name,
      translatedText: translatedText,
      detectedLanguage: request.sourceLanguage
    )
  }
}
