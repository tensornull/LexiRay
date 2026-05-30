import Foundation

protocol TranslationProvider: Sendable {
  var id: ProviderID { get }
  var name: String { get }

  func translate(_ request: TranslationRequest) async throws -> TranslationResult
  func streamTranslation(_ request: TranslationRequest) async throws -> AsyncThrowingStream<TranslationStreamUpdate, Error>
}

extension TranslationProvider {
  func streamTranslation(_ request: TranslationRequest) async throws -> AsyncThrowingStream<TranslationStreamUpdate, Error> {
    let result = try await translate(request)
    return AsyncThrowingStream { continuation in
      continuation.yield(.completed(result))
      continuation.finish()
    }
  }
}
