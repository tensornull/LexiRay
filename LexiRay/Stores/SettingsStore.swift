import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
  @Published var preferredProvider: ProviderID {
    didSet { defaults.set(preferredProvider.rawValue, forKey: Keys.preferredProvider) }
  }

  @Published var targetLanguage: String {
    didSet { defaults.set(targetLanguage, forKey: Keys.targetLanguage) }
  }

  @Published var openAIBaseURL: String {
    didSet { defaults.set(openAIBaseURL, forKey: Keys.openAIBaseURL) }
  }

  @Published var openAIModel: String {
    didSet { defaults.set(openAIModel, forKey: Keys.openAIModel) }
  }

  @Published var openAIAPIKey: String {
    didSet { defaults.set(openAIAPIKey, forKey: Keys.openAIAPIKey) }
  }

  @Published var showProviderDetails: Bool {
    didSet { defaults.set(showProviderDetails, forKey: Keys.showProviderDetails) }
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults

    let providerRawValue = defaults.string(forKey: Keys.preferredProvider)
    preferredProvider = providerRawValue.flatMap(ProviderID.init(rawValue:)) ?? .mock
    targetLanguage = defaults.string(forKey: Keys.targetLanguage) ?? "zh-Hans"
    openAIBaseURL = defaults.string(forKey: Keys.openAIBaseURL) ?? "https://api.openai.com/v1"
    openAIModel = defaults.string(forKey: Keys.openAIModel) ?? "gpt-4.1-mini"
    openAIAPIKey = defaults.string(forKey: Keys.openAIAPIKey) ?? ""
    showProviderDetails = defaults.object(forKey: Keys.showProviderDetails) as? Bool ?? true
  }

  func resetProviderSettings() {
    preferredProvider = .mock
    targetLanguage = "zh-Hans"
    openAIBaseURL = "https://api.openai.com/v1"
    openAIModel = "gpt-4.1-mini"
    openAIAPIKey = ""
    showProviderDetails = true
  }

  private enum Keys {
    static let preferredProvider = "preferredProvider"
    static let targetLanguage = "targetLanguage"
    static let openAIBaseURL = "openAIBaseURL"
    static let openAIModel = "openAIModel"
    static let openAIAPIKey = "openAIAPIKey"
    static let showProviderDetails = "showProviderDetails"
  }
}
