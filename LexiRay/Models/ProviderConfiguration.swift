import Foundation

struct ProviderConfiguration: Codable, Equatable, Identifiable {
  var id: String
  var providerID: ProviderID
  var displayName: String
  var baseURL: String
  var model: String
  var isEnabled: Bool
  var advancedParameters: ProviderAdvancedParameters

  enum CodingKeys: String, CodingKey {
    case id
    case providerID
    case displayName
    case baseURL
    case model
    case isEnabled
    case advancedParameters
  }

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
    isEnabled: Bool,
    advancedParameters: ProviderAdvancedParameters = ProviderAdvancedParameters()
  ) {
    self.id = id ?? providerID.rawValue
    self.providerID = providerID
    self.displayName = displayName
    self.baseURL = baseURL
    self.model = model
    self.isEnabled = isEnabled
    self.advancedParameters = advancedParameters
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    providerID = try container.decode(ProviderID.self, forKey: .providerID)
    id = try container.decodeIfPresent(String.self, forKey: .id) ?? providerID.rawValue
    displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
    baseURL = try container.decode(String.self, forKey: .baseURL)
    model = try container.decode(String.self, forKey: .model)
    isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
    advancedParameters = try container.decodeIfPresent(ProviderAdvancedParameters.self, forKey: .advancedParameters) ?? ProviderAdvancedParameters()
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(providerID, forKey: .providerID)
    try container.encode(displayName, forKey: .displayName)
    try container.encode(baseURL, forKey: .baseURL)
    try container.encode(model, forKey: .model)
    try container.encode(isEnabled, forKey: .isEnabled)
    if !advancedParameters.isEmpty {
      try container.encode(advancedParameters, forKey: .advancedParameters)
    }
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

struct ProviderAdvancedParameters: Codable, Equatable {
  var temperature: Double?
  var maxOutputTokens: Int?
  var reasoningEffort: OpenAIReasoningEffort?
  var reasoningSummary: OpenAIReasoningSummary?
  var textVerbosity: OpenAITextVerbosity?

  var isEmpty: Bool {
    temperature == nil
      && maxOutputTokens == nil
      && reasoningEffort == nil
      && reasoningSummary == nil
      && textVerbosity == nil
  }

  init(
    temperature: Double? = nil,
    maxOutputTokens: Int? = nil,
    reasoningEffort: OpenAIReasoningEffort? = nil,
    reasoningSummary: OpenAIReasoningSummary? = nil,
    textVerbosity: OpenAITextVerbosity? = nil
  ) {
    self.temperature = temperature
    self.maxOutputTokens = maxOutputTokens
    self.reasoningEffort = reasoningEffort
    self.reasoningSummary = reasoningSummary
    self.textVerbosity = textVerbosity
  }
}

enum OpenAIReasoningEffort: String, Codable, CaseIterable, Identifiable {
  case none
  case minimal
  case low
  case medium
  case high
  case xhigh

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .none:
      "None"
    case .minimal:
      "Minimal"
    case .low:
      "Low"
    case .medium:
      "Medium"
    case .high:
      "High"
    case .xhigh:
      "XHigh"
    }
  }
}

enum OpenAIReasoningSummary: String, Codable, CaseIterable, Identifiable {
  case auto
  case concise
  case detailed

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .auto:
      "Auto"
    case .concise:
      "Concise"
    case .detailed:
      "Detailed"
    }
  }
}

enum OpenAITextVerbosity: String, Codable, CaseIterable, Identifiable {
  case low
  case medium
  case high

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .low:
      "Low"
    case .medium:
      "Medium"
    case .high:
      "High"
    }
  }
}
