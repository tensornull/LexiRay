import Foundation

@MainActor
protocol TranslationProvider {
  var id: ProviderID { get }
  var name: String { get }

  func translate(_ request: TranslationRequest) async throws -> TranslationResult
}
