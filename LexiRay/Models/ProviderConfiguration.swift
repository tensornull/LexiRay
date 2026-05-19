import Foundation

struct ProviderConfiguration: Codable, Equatable, Identifiable {
  var id: String
  var providerID: ProviderID
  var displayName: String
  var baseURL: String
  var model: String
  var isEnabled: Bool

  var isBuiltIn: Bool {
    id == providerID.rawValue
  }

  var effectiveDisplayName: String {
    displayName.nonEmptyTrimmed ?? providerID.displayName
  }

  var normalizedBaseURL: String {
    Self.normalizeBaseURL(baseURL)
  }

  init(
    id: String? = nil,
    providerID: ProviderID,
    displayName: String = "",
    baseURL: String,
    model: String,
    isEnabled: Bool
  ) {
    self.id = id ?? providerID.rawValue
    self.providerID = providerID
    self.displayName = displayName
    self.baseURL = baseURL
    self.model = model
    self.isEnabled = isEnabled
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    providerID = try container.decode(ProviderID.self, forKey: .providerID)
    id = try container.decodeIfPresent(String.self, forKey: .id) ?? providerID.rawValue
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

  static func custom(providerID: ProviderID) -> ProviderConfiguration {
    var configuration = defaults(for: providerID)
    configuration.id = "\(providerID.rawValue)-\(UUID().uuidString)"
    configuration.displayName = ""
    configuration.isEnabled = false
    return configuration
  }
}
