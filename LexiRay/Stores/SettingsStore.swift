import Carbon
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
      let normalized = Self.normalizedLanguage(targetLanguage, fallback: LanguageDetector.defaultLanguage2)
      if normalized != targetLanguage {
        targetLanguage = normalized
        return
      }
      defaults.set(targetLanguage, forKey: Keys.targetLanguage)
      if language2 != targetLanguage {
        language2 = targetLanguage
      }
    }
  }

  @Published var language1: String {
    didSet {
      let normalized = Self.normalizedLanguage(language1, fallback: LanguageDetector.defaultLanguage1)
      if normalized != language1 {
        language1 = normalized
        return
      }
      defaults.set(language1, forKey: Keys.language1)
    }
  }

  @Published var language2: String {
    didSet {
      let normalized = Self.normalizedLanguage(language2, fallback: LanguageDetector.defaultLanguage2)
      if normalized != language2 {
        language2 = normalized
        return
      }
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

  @Published var translateHotKey: HotKeyConfiguration {
    didSet { persistHotKey(translateHotKey, forKey: Keys.translateHotKey) }
  }

  @Published var ocrHotKey: HotKeyConfiguration {
    didSet { persistHotKey(ocrHotKey, forKey: Keys.ocrHotKey) }
  }

  @Published var floatingPanelPlacement: FloatingPanelPlacement {
    didSet { defaults.set(floatingPanelPlacement.rawValue, forKey: Keys.floatingPanelPlacement) }
  }

  @Published private(set) var floatingPanelLastOrigin: FloatingPanelSavedOrigin? {
    didSet { persistFloatingPanelLastOrigin() }
  }

  @Published var defaultCopyFormat: CopyFormat {
    didSet { defaults.set(defaultCopyFormat.rawValue, forKey: Keys.defaultCopyFormat) }
  }

  @Published var providerConfigurations: [ProviderConfiguration] {
    didSet { persistProviderSettingsFile() }
  }

  @Published private(set) var apiKeyRevision = UUID()

  private let defaults: UserDefaults
  private let providerFileStore: ProviderSettingsFileStore
  private let allowsMockProvider: Bool
  private var providerAPIKeys: [String: String]

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
    let initialLanguage2 = Self.normalizedLanguage(
      defaults.string(forKey: Keys.language2)
      ?? defaults.string(forKey: Keys.targetLanguage)
      ?? LanguageDetector.defaultLanguage2,
      fallback: LanguageDetector.defaultLanguage2
    )
    language1 = Self.normalizedLanguage(
      defaults.string(forKey: Keys.language1) ?? LanguageDetector.defaultLanguage1,
      fallback: LanguageDetector.defaultLanguage1
    )
    language2 = initialLanguage2
    targetLanguage = initialLanguage2
    autoSwitchLanguages = defaults.object(forKey: Keys.autoSwitchLanguages) as? Bool ?? true
    showsMenuBarIcon = defaults.object(forKey: Keys.showsMenuBarIcon) as? Bool ?? true
    translateHotKey = Self.loadHotKey(
      defaults: defaults,
      key: Keys.translateHotKey,
      fallback: .defaultTranslate
    )
    ocrHotKey = Self.loadHotKey(
      defaults: defaults,
      key: Keys.ocrHotKey,
      fallback: .defaultOCR
    )
    floatingPanelPlacement = FloatingPanelPlacement(rawValue: defaults.string(forKey: Keys.floatingPanelPlacement) ?? "")
      ?? .screenCenter
    floatingPanelLastOrigin = Self.loadFloatingPanelLastOrigin(defaults: defaults)
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

  func resetHotKeys() {
    translateHotKey = .defaultTranslate
    ocrHotKey = .defaultOCR
  }

  func recordFloatingPanelOrigin(x: Double, y: Double) {
    floatingPanelLastOrigin = FloatingPanelSavedOrigin(x: x, y: y)
  }

  func configuration(for providerID: ProviderID) -> ProviderConfiguration {
    providerConfigurations.first(where: { $0.id == providerID.rawValue })
      ?? ProviderConfiguration.defaults(for: providerID)
  }

  func configuration(for configurationID: String) -> ProviderConfiguration? {
    providerConfigurations.first(where: { $0.id == configurationID })
  }

  func visibleProviderIDs() -> [ProviderID] {
    visibleProviderConfigurations().map(\.providerID)
  }

  func visibleProviderConfigurations() -> [ProviderConfiguration] {
    providerConfigurations.filter { configuration in
      allowsMockProvider || configuration.providerID.isProductVisible
    }
  }

  func enabledProviderConfigurations() -> [ProviderConfiguration] {
    visibleProviderConfigurations()
      .filter(\.isEnabled)
  }

  func updateConfiguration(_ configuration: ProviderConfiguration) {
    if let index = providerConfigurations.firstIndex(where: { $0.id == configuration.id }) {
      providerConfigurations[index] = configuration
    } else {
      providerConfigurations.append(configuration)
    }
  }

  @discardableResult
  func addProvider(providerID: ProviderID) -> ProviderConfiguration {
    let configuration = ProviderConfiguration.custom(providerID: providerID)
    providerConfigurations.append(configuration)
    return configuration
  }

  func removeProvider(configurationID: String) {
    guard configuration(for: configurationID) != nil else {
      return
    }

    providerConfigurations.removeAll { $0.id == configurationID }
    providerAPIKeys.removeValue(forKey: configurationID)
    persistProviderSettingsFile()
  }

  func setAPIKey(_ apiKey: String, for providerID: ProviderID) {
    setAPIKey(apiKey, forConfigurationID: providerID.rawValue)
  }

  func setAPIKey(_ apiKey: String, forConfigurationID configurationID: String) {
    let trimmed = apiKey.trimmedForQuery
    if trimmed.isEmpty {
      providerAPIKeys.removeValue(forKey: configurationID)
    } else {
      providerAPIKeys[configurationID] = trimmed
    }
    persistProviderSettingsFile()
    apiKeyRevision = UUID()
  }

  func apiKey(for providerID: ProviderID) -> String {
    apiKey(forConfigurationID: providerID.rawValue)
  }

  func apiKey(forConfigurationID configurationID: String) -> String {
    providerAPIKeys[configurationID] ?? ""
  }

  func hasAPIKey(for providerID: ProviderID) -> Bool {
    !apiKey(for: providerID).trimmedForQuery.isEmpty
  }

  func hasAPIKey(forConfigurationID configurationID: String) -> Bool {
    !apiKey(forConfigurationID: configurationID).trimmedForQuery.isEmpty
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
    let configurationsToStore = providerConfigurations.filter { configuration in
      allowsMockProvider || configuration.providerID.isProductVisible
    }
    let providers = Dictionary(uniqueKeysWithValues: configurationsToStore.map { configuration in
      (
        configuration.id,
        StoredProviderSettings(
          providerID: configuration.providerID,
          displayName: configuration.displayName,
          baseURL: configuration.baseURL,
          model: configuration.model,
          isEnabled: configuration.isEnabled,
          apiKey: providerAPIKeys[configuration.id] ?? ""
        )
      )
    })

    providerFileStore.save(
      ProviderSettingsFile(
        version: 2,
        preferredProvider: Self.normalizedProvider(
          preferredProvider,
          allowsMockProvider: allowsMockProvider
        ).rawValue,
        providerOrder: configurationsToStore.map(\.id),
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
      providerAPIKeys[ProviderID.openAIChatCompletions.rawValue] = legacyAPIKey.trimmedForQuery
      defaults.removeObject(forKey: Keys.openAIAPIKey)
    }
  }

  private func migrateLanguageSettingsIfNeeded() {
    if defaults.object(forKey: Keys.language1) == nil {
      defaults.set(language1, forKey: Keys.language1)
    }
    if defaults.string(forKey: Keys.language1) != language1 {
      defaults.set(language1, forKey: Keys.language1)
    }

    if defaults.object(forKey: Keys.language2) == nil {
      defaults.set(language2, forKey: Keys.language2)
    }
    if defaults.string(forKey: Keys.language2) != language2 {
      defaults.set(language2, forKey: Keys.language2)
    }

    if defaults.object(forKey: Keys.targetLanguage) == nil {
      defaults.set(language2, forKey: Keys.targetLanguage)
    }
    if defaults.string(forKey: Keys.targetLanguage) != targetLanguage {
      defaults.set(targetLanguage, forKey: Keys.targetLanguage)
    }

    if defaults.object(forKey: Keys.autoSwitchLanguages) == nil {
      defaults.set(autoSwitchLanguages, forKey: Keys.autoSwitchLanguages)
    }

    if defaults.object(forKey: Keys.showsMenuBarIcon) == nil {
      defaults.set(showsMenuBarIcon, forKey: Keys.showsMenuBarIcon)
    }

    if defaults.object(forKey: Keys.translateHotKey) == nil {
      persistHotKey(translateHotKey, forKey: Keys.translateHotKey)
    }

    if defaults.object(forKey: Keys.ocrHotKey) == nil {
      persistHotKey(ocrHotKey, forKey: Keys.ocrHotKey)
    }

    if defaults.object(forKey: Keys.floatingPanelPlacement) == nil {
      defaults.set(floatingPanelPlacement.rawValue, forKey: Keys.floatingPanelPlacement)
    }

    if defaults.object(forKey: Keys.defaultCopyFormat) == nil {
      defaults.set(defaultCopyFormat.rawValue, forKey: Keys.defaultCopyFormat)
    }
  }

  private func persistHotKey(_ hotKey: HotKeyConfiguration, forKey key: String) {
    guard let data = try? JSONEncoder().encode(hotKey) else {
      return
    }
    defaults.set(data, forKey: key)
  }

  private func persistFloatingPanelLastOrigin() {
    guard let floatingPanelLastOrigin else {
      defaults.removeObject(forKey: Keys.floatingPanelLastOrigin)
      return
    }

    guard let data = try? JSONEncoder().encode(floatingPanelLastOrigin) else {
      return
    }
    defaults.set(data, forKey: Keys.floatingPanelLastOrigin)
  }

  private static func loadHotKey(
    defaults: UserDefaults,
    key: String,
    fallback: HotKeyConfiguration
  ) -> HotKeyConfiguration {
    guard let data = defaults.data(forKey: key),
          let hotKey = try? JSONDecoder().decode(HotKeyConfiguration.self, from: data),
          hotKey.isValidGlobalShortcut
    else {
      return fallback
    }

    if key == Keys.translateHotKey, hotKey == legacyDockToggleTranslateHotKey {
      if let data = try? JSONEncoder().encode(fallback) {
        defaults.set(data, forKey: key)
      }
      return fallback
    }

    return hotKey
  }

  private static func loadFloatingPanelLastOrigin(defaults: UserDefaults) -> FloatingPanelSavedOrigin? {
    guard let data = defaults.data(forKey: Keys.floatingPanelLastOrigin) else {
      return nil
    }
    return try? JSONDecoder().decode(FloatingPanelSavedOrigin.self, from: data)
  }

  private static func loadProviderConfigurations(from defaults: UserDefaults) -> [ProviderConfiguration] {
    var configurationsByID = Dictionary(
      uniqueKeysWithValues: defaultProviderConfigurations().map { ($0.id, $0) }
    )
    guard
      let data = defaults.data(forKey: Keys.providerConfigurations)
    else {
      return defaultProviderConfigurations()
    }

    let stored: [(String, ProviderID, StoredProviderConfiguration)]
    if let keyed = try? JSONDecoder().decode([String: StoredProviderConfiguration].self, from: data) {
      stored = keyed.compactMap { rawProviderID, value in
        guard let providerID = ProviderID.migrated(from: rawProviderID) else {
          return nil
        }
        return (providerID.rawValue, providerID, value)
      }
    } else if let legacy = try? JSONDecoder().decode([ProviderID: StoredProviderConfiguration].self, from: data) {
      stored = legacy.map { ($0.key.rawValue, $0.key, $0.value) }
    } else {
      return defaultProviderConfigurations()
    }

    for (id, providerID, value) in stored {
      configurationsByID[id] = ProviderConfiguration(
        id: id,
        providerID: providerID,
        displayName: value.displayName,
        baseURL: value.baseURL,
        model: value.model,
        isEnabled: value.isEnabled
      )
    }

    return orderedConfigurations(configurationsByID: configurationsByID, providerOrder: [])
  }

  private static func loadProviderState(
    fileSettings: ProviderSettingsFile?,
    defaults: UserDefaults
  ) -> ProviderState {
    var preferredProvider = ProviderID.migrated(from: defaults.string(forKey: Keys.preferredProvider)) ?? ProviderID.productDefault
    var configurations = loadProviderConfigurations(from: defaults)
    var apiKeys: [String: String] = [:]

    if let fileSettings {
      preferredProvider = ProviderID.migrated(from: fileSettings.preferredProvider) ?? preferredProvider
      let shouldMergeDefaults = fileSettings.version < 2 && fileSettings.providerOrder.isEmpty
      var configurationsByID = shouldMergeDefaults
        ? Dictionary(uniqueKeysWithValues: defaultProviderConfigurations().map { ($0.id, $0) })
        : [:]

      for (rawConfigurationID, stored) in fileSettings.providers {
        guard let providerID = stored.providerID ?? ProviderID.migrated(from: rawConfigurationID) else {
          continue
        }

        let configurationID = stored.providerID == nil && ProviderID.migrated(from: rawConfigurationID) != nil
          ? providerID.rawValue
          : rawConfigurationID
        configurationsByID[configurationID] = ProviderConfiguration(
          id: configurationID,
          providerID: providerID,
          displayName: stored.displayName,
          baseURL: stored.baseURL,
          model: stored.model,
          isEnabled: stored.isEnabled
        )

        let apiKey = stored.apiKey.trimmedForQuery
        if !apiKey.isEmpty {
          apiKeys[configurationID] = apiKey
        }
      }

      configurations = orderedConfigurations(
        configurationsByID: configurationsByID,
        providerOrder: fileSettings.providerOrder
      )
    }

    return ProviderState(
      preferredProvider: preferredProvider,
      configurations: configurations,
      apiKeys: apiKeys
    )
  }

  private static func defaultProviderConfigurations() -> [ProviderConfiguration] {
    ([.mock] + ProviderID.productCases).map { providerID in
      ProviderConfiguration.defaults(for: providerID)
    }
  }

  private static func orderedConfigurations(
    configurationsByID: [String: ProviderConfiguration],
    providerOrder: [String]
  ) -> [ProviderConfiguration] {
    var usedIDs = Set<String>()
    var ordered: [ProviderConfiguration] = []

    for id in providerOrder {
      guard let configuration = configurationsByID[id] else {
        continue
      }
      ordered.append(configuration)
      usedIDs.insert(id)
    }

    for providerID in [.mock] + ProviderID.productCases {
      let id = providerID.rawValue
      guard !usedIDs.contains(id), let configuration = configurationsByID[id] else {
        continue
      }
      ordered.append(configuration)
      usedIDs.insert(id)
    }

    let remaining = configurationsByID.values
      .filter { !usedIDs.contains($0.id) }
      .sorted { $0.id < $1.id }
    ordered.append(contentsOf: remaining)
    return ordered
  }

  private static func normalizedLanguage(_ language: String, fallback: String) -> String {
    language.nonEmptyTrimmed ?? fallback
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

  private static let legacyDockToggleTranslateHotKey = HotKeyConfiguration(
    keyCode: UInt32(kVK_ANSI_D),
    modifiers: UInt32(cmdKey) | UInt32(optionKey),
    keyEquivalent: "D"
  )

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
    let configurations: [ProviderConfiguration]
    let apiKeys: [String: String]
  }

  private enum Keys {
    static let preferredProvider = "preferredProvider"
    static let targetLanguage = "targetLanguage"
    static let language1 = "language1"
    static let language2 = "language2"
    static let autoSwitchLanguages = "autoSwitchLanguages"
    static let showsMenuBarIcon = "showsMenuBarIcon"
    static let translateHotKey = "translateHotKey"
    static let ocrHotKey = "ocrHotKey"
    static let floatingPanelPlacement = "floatingPanelPlacement"
    static let floatingPanelLastOrigin = "floatingPanelLastOrigin"
    static let defaultCopyFormat = "defaultCopyFormat"
    static let providerConfigurations = "providerConfigurations"
    static let openAIBaseURL = "openAIBaseURL"
    static let openAIModel = "openAIModel"
    static let openAIAPIKey = "openAIAPIKey"
  }
}
