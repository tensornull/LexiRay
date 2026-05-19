import Foundation

struct ProviderConfiguration: Codable, Equatable, Identifiable {
  let providerID: ProviderID
  var displayName: String
  var baseURL: String
  var model: String
  var isEnabled: Bool

  var id: ProviderID {
    providerID
  }

  var effectiveDisplayName: String {
    displayName.nonEmptyTrimmed ?? providerID.displayName
  }

  var normalizedBaseURL: String {
    Self.normalizeBaseURL(baseURL)
  }

  init(
    providerID: ProviderID,
    displayName: String = "",
    baseURL: String,
    model: String,
    isEnabled: Bool
  ) {
    self.providerID = providerID
    self.displayName = displayName
    self.baseURL = baseURL
    self.model = model
    self.isEnabled = isEnabled
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    providerID = try container.decode(ProviderID.self, forKey: .providerID)
    displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
    baseURL = try container.decode(String.self, forKey: .baseURL)
    model = try container.decode(String.self, forKey: .model)
    isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
  }

  static func normalizeBaseURL(_ value: String) -> String {
    var trimmed = value.trimmedForQuery
    while trimmed.hasSuffix("/") {
      trimmed.removeLast()
    }
    return trimmed
  }

  static func defaults(for providerID: ProviderID) -> ProviderConfiguration {
    switch providerID {
    case .mock:
      ProviderConfiguration(providerID: providerID, baseURL: "", model: "", isEnabled: false)
    case .systemDictionary:
      ProviderConfiguration(providerID: providerID, baseURL: "", model: "", isEnabled: false)
    case .openAIChatCompletions:
      ProviderConfiguration(
        providerID: providerID,
        baseURL: "https://api.cometapi.com/v1",
        model: "gpt-5.5",
        isEnabled: false
      )
    case .openAIResponses:
      ProviderConfiguration(
        providerID: providerID,
        baseURL: "https://api.cometapi.com/v1",
        model: "gpt-5.5",
        isEnabled: true
      )
    case .anthropicMessages:
      ProviderConfiguration(
        providerID: providerID,
        baseURL: "https://api.cometapi.com",
        model: "claude-sonnet-4-6",
        isEnabled: false
      )
    case .geminiGenerateContent:
      ProviderConfiguration(
        providerID: providerID,
        baseURL: "https://api.cometapi.com/v1beta",
        model: "gemini-3-flash-preview",
        isEnabled: false
      )
    }
  }
}
