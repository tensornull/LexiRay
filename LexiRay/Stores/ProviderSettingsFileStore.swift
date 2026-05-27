import Foundation

struct ProviderSettingsFile: Codable, Equatable {
  var version: Int
  var preferredProvider: String
  var providerOrder: [String]
  var providers: [String: StoredProviderSettings]

  init(
    version: Int = 1,
    preferredProvider: String,
    providerOrder: [String] = [],
    providers: [String: StoredProviderSettings]
  ) {
    self.version = version
    self.preferredProvider = preferredProvider
    self.providerOrder = providerOrder
    self.providers = providers
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
    preferredProvider = try container.decode(String.self, forKey: .preferredProvider)
    providerOrder = try container.decodeIfPresent([String].self, forKey: .providerOrder) ?? []
    providers = try container.decode([String: StoredProviderSettings].self, forKey: .providers)
  }
}

struct StoredProviderSettings: Codable, Equatable {
  var providerID: ProviderID?
  var displayName: String
  var baseURL: String
  var model: String
  var isEnabled: Bool
  var apiKey: String
  var advancedParameters: ProviderAdvancedParameters

  enum CodingKeys: String, CodingKey {
    case providerID
    case displayName
    case baseURL
    case model
    case isEnabled
    case apiKey
    case advancedParameters
  }

  init(
    providerID: ProviderID? = nil,
    displayName: String = "",
    baseURL: String,
    model: String,
    isEnabled: Bool,
    apiKey: String,
    advancedParameters: ProviderAdvancedParameters = ProviderAdvancedParameters()
  ) {
    self.providerID = providerID
    self.displayName = displayName
    self.baseURL = baseURL
    self.model = model
    self.isEnabled = isEnabled
    self.apiKey = apiKey
    self.advancedParameters = advancedParameters
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    providerID = try container.decodeIfPresent(ProviderID.self, forKey: .providerID)
    displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
    baseURL = try container.decode(String.self, forKey: .baseURL)
    model = try container.decode(String.self, forKey: .model)
    isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
    apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
    advancedParameters = try container.decodeIfPresent(ProviderAdvancedParameters.self, forKey: .advancedParameters) ?? ProviderAdvancedParameters()
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(providerID, forKey: .providerID)
    try container.encode(displayName, forKey: .displayName)
    try container.encode(baseURL, forKey: .baseURL)
    try container.encode(model, forKey: .model)
    try container.encode(isEnabled, forKey: .isEnabled)
    try container.encode(apiKey, forKey: .apiKey)
    if !advancedParameters.isEmpty {
      try container.encode(advancedParameters, forKey: .advancedParameters)
    }
  }
}

final class ProviderSettingsFileStore {
  let fileURL: URL

  private let fileManager: FileManager

  init(
    fileURL: URL = ProviderSettingsFileStore.defaultFileURL(),
    fileManager: FileManager = .default
  ) {
    self.fileURL = fileURL
    self.fileManager = fileManager
  }

  static func defaultFileURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
    homeDirectory
      .appendingPathComponent(".lexiray", isDirectory: true)
      .appendingPathComponent("providers.json", isDirectory: false)
  }

  func load() -> ProviderSettingsFile? {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return nil
    }

    do {
      let data = try Data(contentsOf: fileURL)
      return try JSONDecoder().decode(ProviderSettingsFile.self, from: data)
    } catch {
      AppLog.settings.error("Failed to load provider settings file: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }

  func save(_ settings: ProviderSettingsFile) {
    do {
      let directoryURL = fileURL.deletingLastPathComponent()
      try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
      try setPermissions(0o700, at: directoryURL)

      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(settings)
      try data.write(to: fileURL, options: .atomic)
      try setPermissions(0o600, at: fileURL)
    } catch {
      AppLog.settings.error("Failed to save provider settings file: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func setPermissions(_ permissions: Int, at url: URL) throws {
    try fileManager.setAttributes(
      [.posixPermissions: NSNumber(value: permissions)],
      ofItemAtPath: url.path
    )
  }
}
