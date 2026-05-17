import CoreServices
import Foundation

struct SystemDictionaryProvider: TranslationProvider {
  let id: ProviderID = .systemDictionary
  let name = "System Dictionary"

  func translate(_ request: TranslationRequest) async throws -> TranslationResult {
    guard let text = request.text.nonEmptyTrimmed else {
      throw TranslationError.emptyInput
    }

    let nsText = text as NSString
    let range = CFRange(location: 0, length: nsText.length)
    let definition = DCSCopyTextDefinition(nil, text as CFString, range)?
      .takeRetainedValue() as String?

    guard let definition, !definition.trimmedForQuery.isEmpty else {
      throw TranslationError.providerUnavailable("System Dictionary has no entry for this selection")
    }

    return TranslationResult(
      request: request,
      providerID: id,
      providerName: name,
      translatedText: definition.trimmedForQuery,
      detectedLanguage: request.sourceLanguage
    )
  }
}
