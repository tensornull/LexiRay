import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
  @Published var preferredProvider: ProviderID {
    didSet {
      let normalizedProvider = Self.normalizedProvider(
        preferredProvider,
        allowsMockProvider: allowsMockProvider
      )
      if normalizedProvider != preferredProvider {
        preferredProvider = normalizedProvider
      }
      persistProviderSettingsFile()
    }
  }

  @Published var targetLanguage: String {
    didSet {
      defaults.set(targetLanguage, forKey: Keys.targetLanguage)
      if language2 != targetLanguage {
        language2 = targetLanguage
      }
    }
  }

  @Published var language1: String {
    didSet { defaults.set(language1, forKey: Keys.language1) }
  }

  @Published var language2: String {
    didSet {
      defaults.set(language2, forKey: Keys.language2)
      if targetLanguage != language2 {
        targetLanguage = language2
      }
    }
  }

  @Published var autoSwitchLanguages: Bool {
    didSet { defaults.set(autoSwitchLanguages, forKey: Keys.autoSwitchLanguages) }
  }

  @Published var showsMenuBarIcon: Bool {
    didSet { defaults.set(showsMenuBarIcon, forKey: Keys.showsMenuBarIcon) }
  }

  @Published var defaultCopyFormat: CopyFormat {
    didSet { defaults.set(defaultCopyFormat.rawValue, forKey: Keys.defaultCopyFormat) }
  }

  @Published var providerConfigurations: [ProviderID: ProviderConfiguration] {
    didSet { persistProviderSettingsFile() }
  }

  @Published private(set) var apiKeyRevision = UUID()

  private let defaults: UserDefaults
  private let providerFileStore: ProviderSettingsFileStore
  private let allowsMockProvider: Bool
  private var providerAPIKeys: [ProviderID: String]

  init(
    defaults: UserDefaults = .standard,
    providerFileStore: ProviderSettingsFileStore = ProviderSettingsFileStore(),
    allowsMockProvider: Bool = false
  ) {
    self.defaults = defaults
    self.providerFileStore = providerFileStore
    self.allowsMockProvider = allowsMockProvider

    let fileSettings = providerFileStore.load()
    let providerState = Self.loadProviderState(fileSettings: fileSettings, defaults: defaults)

    preferredProvider = Self.normalizedProvider(
      providerState.preferredProvider,
      allowsMockProvider: allowsMockProvider
    )
    let initialLanguage2 = defaults.string(forKey: Keys.language2)
      ?? defaults.string(forKey: Keys.targetLanguage)
      ?? LanguageDetector.defaultLanguage2
    language1 = defaults.string(forKey: Keys.language1) ?? LanguageDetector.defaultLanguage1
    language2 = initialLanguage2
    targetLanguage = initialLanguage2
    autoSwitchLanguages = defaults.object(forKey: Keys.autoSwitchLanguages) as? Bool ?? true
    showsMenuBarIcon = defaults.object(forKey: Keys.showsMenuBarIcon) as? Bool ?? true
    defaultCopyFormat = CopyFormat(rawValue: defaults.string(forKey: Keys.defaultCopyFormat) ?? "") ?? .originalText
    providerConfigurations = providerState.configurations
    providerAPIKeys = providerState.apiKeys
    migrateLanguageSettingsIfNeeded()
    if fileSettings == nil {
      migrateOpenAICompatibleSettingsIfNeeded()
    }
    persistProviderSettingsFile()
  }

  func resetProviderSettings() {
    providerAPIKeys = [:]
    preferredProvider = ProviderID.productDefault
    language1 = LanguageDetector.defaultLanguage1
    language2 = LanguageDetector.defaultLanguage2
    targetLanguage = language2
    autoSwitchLanguages = true
    providerConfigurations = Self.defaultProviderConfigurations()
    apiKeyRevision = UUID()
    persistProviderSettingsFile()
  }

  func configuration(for providerID: ProviderID) -> ProviderConfiguration {
    providerConfigurations[providerID] ?? ProviderConfiguration.defaults(for: providerID)
  }

  func visibleProviderIDs() -> [ProviderID] {
    if allowsMockProvider {
      return [.mock] + ProviderID.productCases
    }

    return ProviderID.productCases
  }

  func enabledProviderConfigurations() -> [ProviderConfiguration] {
    visibleProviderIDs()
      .map { configuration(for: $0) }
      .filter(\.isEnabled)
  }

  func updateConfiguration(_ configuration: ProviderConfiguration) {
    providerConfigurations[configuration.providerID] = configuration
  }

  func setAPIKey(_ apiKey: String, for providerID: ProviderID) {
    let trimmed = apiKey.trimmedForQuery
    if trimmed.isEmpty {
      providerAPIKeys.removeValue(forKey: providerID)
    } else {
      providerAPIKeys[providerID] = trimmed
    }
    persistProviderSettingsFile()
    apiKeyRevision = UUID()
  }

  func apiKey(for providerID: ProviderID) -> String {
    providerAPIKeys[providerID] ?? ""
  }

  func hasAPIKey(for providerID: ProviderID) -> Bool {
    !apiKey(for: providerID).trimmedForQuery.isEmpty
  }

  func resolvedTargetLanguage(for sourceLanguage: String?) -> String {
    LanguageDetector.targetLanguage(
      for: sourceLanguage,
      language1: language1,
      language2: language2,
      autoSwitch: autoSwitchLanguages
    )
  }

  func languageDirectionLabel(sourceLanguage: String?, targetLanguage: String) -> String {
    LanguageDetector.directionLabel(sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
  }

  private func persistProviderSettingsFile() {
    let configurationsToStore = providerConfigurations.filter { providerID, _ in
      allowsMockProvider || providerID.isProductVisible
    }
    let providers = Dictionary(uniqueKeysWithValues: configurationsToStore.map { providerID, configuration in
      (
        providerID.rawValue,
        StoredProviderSettings(
          displayName: configuration.displayName,
          baseURL: configuration.baseURL,
          model: configuration.model,
          isEnabled: configuration.isEnabled,
          apiKey: providerAPIKeys[providerID] ?? ""
        )
      )
    })

    providerFileStore.save(
      ProviderSettingsFile(
        preferredProvider: Self.normalizedProvider(
          preferredProvider,
          allowsMockProvider: allowsMockProvider
        ).rawValue,
        providers: providers
      )
    )
  }

  private func migrateOpenAICompatibleSettingsIfNeeded() {
    let legacyBaseURL = defaults.string(forKey: Keys.openAIBaseURL)
    let legacyModel = defaults.string(forKey: Keys.openAIModel)
    let legacyAPIKey = defaults.string(forKey: Keys.openAIAPIKey)

    if defaults.object(forKey: Keys.providerConfigurations) == nil, legacyBaseURL != nil || legacyModel != nil {
      var configuration = configuration(for: .openAIChatCompletions)
      configuration.baseURL = legacyBaseURL ?? configuration.baseURL
      configuration.model = legacyModel ?? configuration.model
      updateConfiguration(configuration)
    }

    if let legacyAPIKey, !legacyAPIKey.trimmedForQuery.isEmpty {
      providerAPIKeys[.openAIChatCompletions] = legacyAPIKey.trimmedForQuery
      defaults.removeObject(forKey: Keys.openAIAPIKey)
    }
  }

  private func migrateLanguageSettingsIfNeeded() {
    if defaults.object(forKey: Keys.language1) == nil {
      defaults.set(language1, forKey: Keys.language1)
    }

    if defaults.object(forKey: Keys.language2) == nil {
      defaults.set(language2, forKey: Keys.language2)
    }

    if defaults.object(forKey: Keys.targetLanguage) == nil {
      defaults.set(language2, forKey: Keys.targetLanguage)
    }

    if defaults.object(forKey: Keys.autoSwitchLanguages) == nil {
      defaults.set(autoSwitchLanguages, forKey: Keys.autoSwitchLanguages)
    }

    if defaults.object(forKey: Keys.showsMenuBarIcon) == nil {
      defaults.set(showsMenuBarIcon, forKey: Keys.showsMenuBarIcon)
    }

    if defaults.object(forKey: Keys.defaultCopyFormat) == nil {
      defaults.set(defaultCopyFormat.rawValue, forKey: Keys.defaultCopyFormat)
    }
  }

  private static func loadProviderConfigurations(from defaults: UserDefaults) -> [ProviderID: ProviderConfiguration] {
    var configurations = defaultProviderConfigurations()
    guard
      let data = defaults.data(forKey: Keys.providerConfigurations)
    else {
      return configurations
    }

    let stored: [ProviderID: StoredProviderConfiguration]
    if let keyed = try? JSONDecoder().decode([String: StoredProviderConfiguration].self, from: data) {
      stored = Dictionary(uniqueKeysWithValues: keyed.compactMap { rawProviderID, value in
        guard let providerID = ProviderID.migrated(from: rawProviderID) else {
          return nil
        }
        return (providerID, value)
      })
    } else if let legacy = try? JSONDecoder().decode([ProviderID: StoredProviderConfiguration].self, from: data) {
      stored = legacy
    } else {
      return configurations
    }

    for (providerID, value) in stored {
      configurations[providerID] = ProviderConfiguration(
        providerID: providerID,
        displayName: value.displayName,
        baseURL: value.baseURL,
        model: value.model,
        isEnabled: value.isEnabled
      )
    }

    return configurations
  }

  private static func loadProviderState(
    fileSettings: ProviderSettingsFile?,
    defaults: UserDefaults
  ) -> ProviderState {
    var preferredProvider = ProviderID.migrated(from: defaults.string(forKey: Keys.preferredProvider)) ?? ProviderID.productDefault
    var configurations = loadProviderConfigurations(from: defaults)
    var apiKeys: [ProviderID: String] = [:]

    if let fileSettings {
      preferredProvider = ProviderID.migrated(from: fileSettings.preferredProvider) ?? preferredProvider
      configurations = defaultProviderConfigurations()

      for (rawProviderID, stored) in fileSettings.providers {
        guard let providerID = ProviderID.migrated(from: rawProviderID) else {
          continue
        }

        configurations[providerID] = ProviderConfiguration(
          providerID: providerID,
          displayName: stored.displayName,
          baseURL: stored.baseURL,
          model: stored.model,
          isEnabled: stored.isEnabled
        )

        let apiKey = stored.apiKey.trimmedForQuery
        if !apiKey.isEmpty {
          apiKeys[providerID] = apiKey
        }
      }
    }

    return ProviderState(
      preferredProvider: preferredProvider,
      configurations: configurations,
      apiKeys: apiKeys
    )
  }

  private static func defaultProviderConfigurations() -> [ProviderID: ProviderConfiguration] {
    Dictionary(
      uniqueKeysWithValues: ProviderID.allCases.map { providerID in
        (providerID, ProviderConfiguration.defaults(for: providerID))
      }
    )
  }

  private static func normalizedProvider(
    _ providerID: ProviderID,
    allowsMockProvider: Bool
  ) -> ProviderID {
    if allowsMockProvider || providerID.isProductVisible {
      return providerID
    }

    return ProviderID.productDefault
  }

  private struct StoredProviderConfiguration: Codable {
    let displayName: String
    let baseURL: String
    let model: String
    let isEnabled: Bool

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
      baseURL = try container.decode(String.self, forKey: .baseURL)
      model = try container.decode(String.self, forKey: .model)
      isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
    }
  }

  private struct ProviderState {
    let preferredProvider: ProviderID
    let configurations: [ProviderID: ProviderConfiguration]
    let apiKeys: [ProviderID: String]
  }

  private enum Keys {
    static let preferredProvider = "preferredProvider"
    static let targetLanguage = "targetLanguage"
    static let language1 = "language1"
    static let language2 = "language2"
    static let autoSwitchLanguages = "autoSwitchLanguages"
    static let showsMenuBarIcon = "showsMenuBarIcon"
    static let defaultCopyFormat = "defaultCopyFormat"
    static let providerConfigurations = "providerConfigurations"
    static let openAIBaseURL = "openAIBaseURL"
    static let openAIModel = "openAIModel"
    static let openAIAPIKey = "openAIAPIKey"
  }
}
