import Foundation

enum ProviderID: String, CaseIterable, Codable, Identifiable {
  case mock
  case systemDictionary
  case openAIChatCompletions
  case openAIResponses
  case anthropicMessages
  case geminiGenerateContent

  static let productDefault: ProviderID = .openAIResponses

  static var productCases: [ProviderID] {
    [
      .openAIResponses,
      .openAIChatCompletions,
      .anthropicMessages,
      .geminiGenerateContent,
      .systemDictionary
    ]
  }

  static var addableCases: [ProviderID] {
    [
      .openAIResponses,
      .openAIChatCompletions,
      .anthropicMessages,
      .geminiGenerateContent,
      .systemDictionary
    ]
  }

  var id: String {
    rawValue
  }

  var displayName: String {
    switch self {
    case .mock:
      "Mock"
    case .systemDictionary:
      "System Dictionary"
    case .openAIChatCompletions:
      "OpenAI Chat Completions"
    case .openAIResponses:
      "OpenAI Responses"
    case .anthropicMessages:
      "Anthropic Messages"
    case .geminiGenerateContent:
      "Gemini GenerateContent"
    }
  }

  var systemImage: String {
    switch self {
    case .mock:
      "hammer"
    case .systemDictionary:
      "book"
    case .openAIChatCompletions:
      "bubble.left.and.bubble.right"
    case .openAIResponses:
      "sparkles"
    case .anthropicMessages:
      "text.bubble"
    case .geminiGenerateContent:
      "diamond"
    }
  }

  var needsAPIKey: Bool {
    switch self {
    case .mock, .systemDictionary:
      false
    case .openAIChatCompletions, .openAIResponses, .anthropicMessages, .geminiGenerateContent:
      true
    }
  }

  var isLLMProvider: Bool {
    needsAPIKey
  }

  var isProductVisible: Bool {
    Self.productCases.contains(self)
  }

  static func migrated(from rawValue: String?) -> ProviderID? {
    guard let rawValue else {
      return nil
    }

    if rawValue == "openAICompatible" {
      return .openAIChatCompletions
    }

    return ProviderID(rawValue: rawValue)
  }

  func isDefaultDisplayNameEquivalent(_ displayName: String) -> Bool {
    Self.displayNameKey(displayName) == Self.displayNameKey(self.displayName)
  }

  private static func displayNameKey(_ displayName: String) -> String {
    displayName
      .filter { !$0.isWhitespace }
      .lowercased()
  }
}
