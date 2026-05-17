import Foundation

enum ProviderID: String, CaseIterable, Codable, Identifiable {
  case mock
  case systemDictionary
  case openAICompatible

  var id: String {
    rawValue
  }

  var displayName: String {
    switch self {
    case .mock:
      "Mock"
    case .systemDictionary:
      "System Dictionary"
    case .openAICompatible:
      "OpenAI Compatible"
    }
  }
}
