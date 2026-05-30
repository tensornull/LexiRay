import Carbon
@testable import LexiRay
import SwiftUI
import XCTest

@MainActor
final class SettingsStoreTests: XCTestCase {
  func testSettingsPersistProviderChoice() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)
    store.preferredProvider = .openAIResponses
    store.targetLanguage = "ja"
    store.language1 = "fr"
    store.autoSwitchLanguages = false

    let reloaded = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)

    XCTAssertEqual(reloaded.preferredProvider, .openAIResponses)
    XCTAssertEqual(reloaded.targetLanguage, "ja")
    XCTAssertEqual(reloaded.language1, "fr")
    XCTAssertEqual(reloaded.language2, "ja")
    XCTAssertFalse(reloaded.autoSwitchLanguages)
  }

  func testResetProviderSettingsRestoresDefaults() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)
    store.preferredProvider = .openAIResponses
    store.setAPIKey("secret", for: .openAIResponses)
    store.showsMenuBarIcon = false

    store.resetProviderSettings()

    XCTAssertEqual(store.preferredProvider, .openAIResponses)
    XCTAssertEqual(store.apiKey(for: .openAIResponses), "")
    XCTAssertEqual(store.language1, "en")
    XCTAssertEqual(store.language2, "zh-Hans")
    XCTAssertTrue(store.autoSwitchLanguages)
    XCTAssertFalse(store.showsMenuBarIcon)
  }

  func testMenuBarIconDefaultsToShown() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()

    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)

    XCTAssertTrue(store.showsMenuBarIcon)
  }

  func testMenuBarIconVisibilityPersists() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)

    store.showsMenuBarIcon = false

    let reloaded = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)
    XCTAssertFalse(reloaded.showsMenuBarIcon)
  }

  func testAutoCopyModeDefaultsToOff() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()

    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)

    XCTAssertEqual(store.autoCopyMode, .off)
  }

  func testAutoCopyModePersists() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)

    store.autoCopyMode = .firstProviderSuccess

    let reloaded = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)
    XCTAssertEqual(reloaded.autoCopyMode, .firstProviderSuccess)
  }

  func testDefaultCopyFormatPersists() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)

    store.defaultCopyFormat = .html

    let reloaded = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)
    XCTAssertEqual(reloaded.defaultCopyFormat, .html)
  }

  func testTranslationHistoryLimitDefaultsPersistsAndClamps() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)

    XCTAssertEqual(store.translationHistoryLimit, 100)

    store.translationHistoryLimit = 12
    XCTAssertEqual(SettingsStore(defaults: defaults, providerFileStore: providerFileStore).translationHistoryLimit, 12)

    store.translationHistoryLimit = 0
    XCTAssertEqual(store.translationHistoryLimit, 1)

    store.translationHistoryLimit = 999
    XCTAssertEqual(store.translationHistoryLimit, 100)
  }

  func testHotKeysDefaultAndPersist() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)
    let customTranslate = HotKeyConfiguration(
      keyCode: UInt32(kVK_ANSI_T),
      modifiers: UInt32(controlKey) | UInt32(optionKey),
      keyEquivalent: "T"
    )
    let customOCR = HotKeyConfiguration(
      keyCode: UInt32(kVK_ANSI_R),
      modifiers: UInt32(controlKey) | UInt32(cmdKey),
      keyEquivalent: "R"
    )

    XCTAssertEqual(store.translateHotKey, .defaultTranslate)
    XCTAssertEqual(store.ocrHotKey, .defaultOCR)

    store.translateHotKey = customTranslate
    store.ocrHotKey = customOCR

    let reloaded = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)
    XCTAssertEqual(reloaded.translateHotKey, customTranslate)
    XCTAssertEqual(reloaded.ocrHotKey, customOCR)
  }

  func testDefaultHotKeysUseCurrentShortcuts() {
    let dockToggleHotKey = HotKeyConfiguration(
      keyCode: UInt32(kVK_ANSI_D),
      modifiers: UInt32(cmdKey) | UInt32(optionKey),
      keyEquivalent: "D"
    )

    XCTAssertNotEqual(HotKeyConfiguration.defaultTranslate, dockToggleHotKey)
    XCTAssertEqual(HotKeyConfiguration.defaultTranslate.keyCode, UInt32(kVK_ANSI_A))
    XCTAssertEqual(
      HotKeyConfiguration.defaultTranslate.modifiers,
      UInt32(controlKey) | UInt32(optionKey)
    )
    XCTAssertEqual(HotKeyConfiguration.defaultTranslate.keyEquivalent, "A")
    XCTAssertEqual(HotKeyConfiguration.defaultOCR.keyCode, UInt32(kVK_ANSI_S))
    XCTAssertEqual(HotKeyConfiguration.defaultOCR.modifiers, UInt32(controlKey) | UInt32(optionKey))
    XCTAssertEqual(HotKeyConfiguration.defaultOCR.keyEquivalent, "S")
  }

  func testHotKeyConvertsToMenuKeyboardShortcut() {
    let shortcut = HotKeyConfiguration.defaultTranslate.menuKeyboardShortcut

    XCTAssertNotNil(shortcut)
    XCTAssertEqual(shortcut?.modifiers, SwiftUI.EventModifiers([.control, .option]))
  }

  func testResetHotKeysRestoresDefaults() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)
    store.translateHotKey = HotKeyConfiguration(
      keyCode: UInt32(kVK_ANSI_R),
      modifiers: UInt32(controlKey) | UInt32(optionKey),
      keyEquivalent: "R"
    )
    store.ocrHotKey = HotKeyConfiguration(
      keyCode: UInt32(kVK_ANSI_P),
      modifiers: UInt32(controlKey) | UInt32(cmdKey),
      keyEquivalent: "P"
    )

    store.resetHotKeys()

    XCTAssertEqual(store.translateHotKey, .defaultTranslate)
    XCTAssertEqual(store.ocrHotKey, .defaultOCR)
  }

  func testLegacyDockTranslateHotKeyMigratesToDefault() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    let legacyHotKey = HotKeyConfiguration(
      keyCode: UInt32(kVK_ANSI_D),
      modifiers: UInt32(cmdKey) | UInt32(optionKey),
      keyEquivalent: "D"
    )
    try defaults.set(JSONEncoder().encode(legacyHotKey), forKey: "translateHotKey")

    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)

    XCTAssertEqual(store.translateHotKey, .defaultTranslate)
    let persistedData = try XCTUnwrap(defaults.data(forKey: "translateHotKey"))
    let persistedHotKey = try JSONDecoder().decode(HotKeyConfiguration.self, from: persistedData)
    XCTAssertEqual(persistedHotKey, .defaultTranslate)
  }

  func testLegacyDefaultHotKeysMigrateToCurrentDefaults() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    let legacyTranslate = HotKeyConfiguration(
      keyCode: UInt32(kVK_ANSI_T),
      modifiers: UInt32(cmdKey) | UInt32(optionKey) | UInt32(shiftKey),
      keyEquivalent: "T"
    )
    let legacyOCR = HotKeyConfiguration(
      keyCode: UInt32(kVK_ANSI_O),
      modifiers: UInt32(cmdKey) | UInt32(optionKey),
      keyEquivalent: "O"
    )
    try defaults.set(JSONEncoder().encode(legacyTranslate), forKey: "translateHotKey")
    try defaults.set(JSONEncoder().encode(legacyOCR), forKey: "ocrHotKey")

    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)

    XCTAssertEqual(store.translateHotKey, .defaultTranslate)
    XCTAssertEqual(store.ocrHotKey, .defaultOCR)
    let persistedTranslateData = try XCTUnwrap(defaults.data(forKey: "translateHotKey"))
    let persistedOCRData = try XCTUnwrap(defaults.data(forKey: "ocrHotKey"))
    XCTAssertEqual(try JSONDecoder().decode(HotKeyConfiguration.self, from: persistedTranslateData), .defaultTranslate)
    XCTAssertEqual(try JSONDecoder().decode(HotKeyConfiguration.self, from: persistedOCRData), .defaultOCR)
  }

  func testBareLetterHotKeyIsInvalid() {
    let bareLetter = HotKeyConfiguration(
      keyCode: UInt32(kVK_ANSI_D),
      modifiers: 0,
      keyEquivalent: "D"
    )

    XCTAssertFalse(bareLetter.isValidGlobalShortcut)
  }

  func testFloatingPanelPlacementAndLastOriginPersist() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)

    XCTAssertEqual(store.floatingPanelPlacement, .screenCenter)

    store.floatingPanelPlacement = .topRight
    store.recordFloatingPanelOrigin(x: 120, y: 340)

    let reloaded = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)
    XCTAssertEqual(reloaded.floatingPanelPlacement, .topRight)
    XCTAssertEqual(reloaded.floatingPanelLastOrigin, FloatingPanelSavedOrigin(x: 120, y: 340))
  }

  func testFloatingPanelLastSizePersists() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)

    XCTAssertNil(store.floatingPanelLastSize)

    store.recordFloatingPanelSize(width: 760, height: 520)

    let reloaded = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)
    XCTAssertEqual(reloaded.floatingPanelLastSize, FloatingPanelSavedSize(width: 760, height: 520))
  }

  func testBlankLanguageSettingsFallbackToDefaultsAndPersist() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    defaults.set("", forKey: "language1")
    defaults.set("   ", forKey: "language2")
    defaults.set("", forKey: "targetLanguage")

    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)

    XCTAssertEqual(store.language1, "en")
    XCTAssertEqual(store.language2, "zh-Hans")
    XCTAssertEqual(store.targetLanguage, "zh-Hans")
    XCTAssertEqual(store.resolvedTargetLanguage(for: "zh-Hans"), "en")
    XCTAssertEqual(defaults.string(forKey: "language1"), "en")
    XCTAssertEqual(defaults.string(forKey: "language2"), "zh-Hans")
  }

  func testProviderConfigurationsPersist() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)
    var configuration = store.configuration(for: .anthropicMessages)
    configuration.displayName = "Claude Fast"
    configuration.baseURL = "https://example.test/v1"
    configuration.model = "claude-test"
    configuration.isEnabled = false

    store.updateConfiguration(configuration)

    let reloaded = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)
    XCTAssertEqual(reloaded.configuration(for: .anthropicMessages).displayName, "Claude Fast")
    XCTAssertEqual(reloaded.configuration(for: .anthropicMessages).effectiveDisplayName, "Claude Fast")
    XCTAssertEqual(reloaded.configuration(for: .anthropicMessages).baseURL, "https://example.test/v1")
    XCTAssertEqual(reloaded.configuration(for: .anthropicMessages).model, "claude-test")
    XCTAssertFalse(reloaded.configuration(for: .anthropicMessages).isEnabled)
  }

  func testOpenAIResponsesAdvancedParametersPersistAndReset() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)
    var configuration = store.configuration(for: .openAIResponses)
    configuration.advancedParameters = ProviderAdvancedParameters(
      temperature: 0.4,
      maxOutputTokens: 2048,
      reasoningEffort: .high,
      reasoningSummary: .auto,
      textVerbosity: .low
    )

    store.updateConfiguration(configuration)

    let reloaded = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)
    XCTAssertEqual(reloaded.configuration(for: .openAIResponses).advancedParameters, configuration.advancedParameters)

    reloaded.resetProviderSettings()
    XCTAssertTrue(reloaded.configuration(for: .openAIResponses).advancedParameters.isEmpty)
  }

  func testCustomProviderInstancesPersistInOrder() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)
    var custom = store.addProvider(providerID: .openAIChatCompletions)
    custom.displayName = "Comet Chat Backup"
    custom.baseURL = "https://backup.example.test/v1"
    custom.model = "gpt-backup"
    custom.isEnabled = true
    store.updateConfiguration(custom)
    store.setAPIKey("backup-secret", forConfigurationID: custom.id)

    let reloaded = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)
    let reloadedCustom = try XCTUnwrap(reloaded.configuration(for: custom.id))
    let file = try readProviderFile(from: providerFileStore)

    XCTAssertEqual(reloadedCustom.providerID, .openAIChatCompletions)
    XCTAssertEqual(reloadedCustom.displayName, "Comet Chat Backup")
    XCTAssertEqual(reloadedCustom.baseURL, "https://backup.example.test/v1")
    XCTAssertEqual(reloadedCustom.model, "gpt-backup")
    XCTAssertTrue(reloadedCustom.isEnabled)
    XCTAssertEqual(reloaded.apiKey(forConfigurationID: custom.id), "backup-secret")
    XCTAssertTrue(file.providerOrder.contains(custom.id))
    XCTAssertEqual(file.providers[custom.id]?.providerID, .openAIChatCompletions)
  }

  func testBuiltInProviderCanBeRemovedAndAddedBackAsInstance() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)

    store.removeProvider(configurationID: ProviderID.openAIResponses.rawValue)
    let custom = store.addProvider(providerID: .openAIResponses)
    let reloaded = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)

    XCTAssertFalse(store.visibleProviderConfigurations().contains { $0.id == ProviderID.openAIResponses.rawValue })
    XCTAssertTrue(store.visibleProviderConfigurations().contains { $0.id == custom.id })
    XCTAssertEqual(custom.providerID, .openAIResponses)
    XCTAssertFalse(reloaded.visibleProviderConfigurations().contains { $0.id == ProviderID.openAIResponses.rawValue })
    XCTAssertTrue(reloaded.visibleProviderConfigurations().contains { $0.id == custom.id })
  }

  func testProviderSettingsPersistAsStringKeyedJSONFile() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)
    var configuration = store.configuration(for: .geminiGenerateContent)
    configuration.displayName = "Gemini Preview"
    configuration.baseURL = "https://example.test/gemini"

    store.updateConfiguration(configuration)

    let data = try Data(contentsOf: providerFileStore.fileURL)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let providers = try XCTUnwrap(object["providers"] as? [String: Any])
    let gemini = try XCTUnwrap(providers[ProviderID.geminiGenerateContent.rawValue] as? [String: Any])
    XCTAssertEqual(gemini["displayName"] as? String, "Gemini Preview")
    XCTAssertNil(providers[ProviderID.mock.rawValue])
    XCTAssertEqual(object["preferredProvider"] as? String, ProviderID.openAIResponses.rawValue)
  }

  func testProviderConfigurationsLoadStringKeyedJSON() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    let data = try JSONSerialization.data(withJSONObject: [
      ProviderID.openAIChatCompletions.rawValue: [
        "baseURL": "https://example.test/v1",
        "model": "chat-test",
        "isEnabled": true
      ]
    ])
    defaults.set(data, forKey: "providerConfigurations")

    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)

    XCTAssertEqual(store.configuration(for: .openAIChatCompletions).baseURL, "https://example.test/v1")
    XCTAssertEqual(store.configuration(for: .openAIChatCompletions).displayName, "")
    XCTAssertEqual(store.configuration(for: .openAIChatCompletions).effectiveDisplayName, ProviderID.openAIChatCompletions.displayName)
    XCTAssertEqual(store.configuration(for: .openAIChatCompletions).model, "chat-test")
    XCTAssertTrue(store.configuration(for: .openAIChatCompletions).isEnabled)
  }

  func testProviderSettingsFileLoadsWithoutDisplayName() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    try FileManager.default.createDirectory(
      at: providerFileStore.fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let data = try JSONSerialization.data(withJSONObject: [
      "version": 1,
      "preferredProvider": ProviderID.openAIResponses.rawValue,
      "providers": [
        ProviderID.openAIResponses.rawValue: [
          "baseURL": "https://example.test/v1",
          "model": "gpt-test",
          "isEnabled": true,
          "apiKey": "secret"
        ]
      ]
    ])
    try data.write(to: providerFileStore.fileURL)

    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)

    XCTAssertEqual(store.configuration(for: .openAIResponses).displayName, "")
    XCTAssertEqual(store.configuration(for: .openAIResponses).effectiveDisplayName, ProviderID.openAIResponses.displayName)
    XCTAssertTrue(store.configuration(for: .openAIResponses).advancedParameters.isEmpty)
    XCTAssertEqual(store.apiKey(for: .openAIResponses), "secret")
  }

  func testBuiltInOpenAIChatDisplayNameVariantsNormalizeToDefault() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    let customID = "\(ProviderID.openAIChatCompletions.rawValue)-custom"
    providerFileStore.save(
      ProviderSettingsFile(
        version: 2,
        preferredProvider: ProviderID.openAIResponses.rawValue,
        providerOrder: [ProviderID.openAIChatCompletions.rawValue, customID],
        providers: [
          ProviderID.openAIChatCompletions.rawValue: StoredProviderSettings(
            providerID: .openAIChatCompletions,
            displayName: "OpenAIChatCompletions",
            baseURL: "https://example.test/v1",
            model: "chat-test",
            isEnabled: true,
            apiKey: "secret"
          ),
          customID: StoredProviderSettings(
            providerID: .openAIChatCompletions,
            displayName: "OpenAI ChatCompletions",
            baseURL: "https://backup.example.test/v1",
            model: "chat-backup",
            isEnabled: false,
            apiKey: ""
          )
        ]
      )
    )

    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)
    let file = try readProviderFile(from: providerFileStore)

    XCTAssertEqual(store.configuration(for: .openAIChatCompletions).displayName, "")
    XCTAssertEqual(store.configuration(for: .openAIChatCompletions).effectiveDisplayName, ProviderID.openAIChatCompletions.displayName)
    XCTAssertFalse(store.configuration(for: .openAIChatCompletions).hasCustomDisplayName)
    XCTAssertEqual(store.configuration(for: customID)?.displayName, "OpenAI ChatCompletions")
    XCTAssertEqual(store.configuration(for: customID)?.effectiveDisplayName, "OpenAI ChatCompletions")
    XCTAssertTrue(store.configuration(for: customID)?.hasCustomDisplayName == true)
    XCTAssertEqual(file.providers[ProviderID.openAIChatCompletions.rawValue]?.displayName, "")
    XCTAssertEqual(file.providers[customID]?.displayName, "OpenAI ChatCompletions")
  }

  func testMigratesLegacyOpenAICompatibleProvider() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    defaults.set("openAICompatible", forKey: "preferredProvider")

    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)

    XCTAssertEqual(store.preferredProvider, .openAIChatCompletions)
  }

  func testAPIKeyPersistsInProviderSettingsFile() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)

    store.setAPIKey(" local-secret ", for: .openAIResponses)

    let reloaded = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)
    let file = try readProviderFile(from: providerFileStore)
    XCTAssertEqual(reloaded.apiKey(for: .openAIResponses), "local-secret")
    XCTAssertEqual(file.providers[ProviderID.openAIResponses.rawValue]?.apiKey, "local-secret")
  }

  func testProviderSettingsFilePermissions() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)

    store.setAPIKey("secret", for: .anthropicMessages)

    XCTAssertEqual(try permission(at: providerFileStore.fileURL.deletingLastPathComponent()), 0o700)
    XCTAssertEqual(try permission(at: providerFileStore.fileURL), 0o600)
  }

  func testMigratesLegacyUserDefaultsAPIKeyIntoProviderFile() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    defaults.set("legacy-secret", forKey: "openAIAPIKey")

    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)

    XCTAssertEqual(store.apiKey(for: .openAIChatCompletions), "legacy-secret")
    XCTAssertNil(defaults.string(forKey: "openAIAPIKey"))
    XCTAssertEqual(try readProviderFile(from: providerFileStore).providers[ProviderID.openAIChatCompletions.rawValue]?.apiKey, "legacy-secret")
  }

  func testCorruptedProviderSettingsFileFallsBackToDefaults() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    try FileManager.default.createDirectory(
      at: providerFileStore.fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("{".utf8).write(to: providerFileStore.fileURL)

    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)

    XCTAssertEqual(store.preferredProvider, .openAIResponses)
    XCTAssertEqual(store.configuration(for: .openAIChatCompletions).baseURL, "https://api.cometapi.com/v1")
  }

  func testProviderDefaultsUseCometModernModels() {
    let openAIChat = ProviderConfiguration.defaults(for: .openAIChatCompletions)
    XCTAssertEqual(openAIChat.baseURL, "https://api.cometapi.com/v1")
    XCTAssertEqual(openAIChat.model, "gpt-5.5")
    XCTAssertFalse(openAIChat.isEnabled)

    let openAIResponses = ProviderConfiguration.defaults(for: .openAIResponses)
    XCTAssertEqual(openAIResponses.baseURL, "https://api.cometapi.com/v1")
    XCTAssertEqual(openAIResponses.model, "gpt-5.5")
    XCTAssertTrue(openAIResponses.isEnabled)

    let anthropic = ProviderConfiguration.defaults(for: .anthropicMessages)
    XCTAssertEqual(anthropic.baseURL, "https://api.cometapi.com")
    XCTAssertEqual(anthropic.model, "claude-sonnet-4-6")
    XCTAssertFalse(anthropic.isEnabled)

    let gemini = ProviderConfiguration.defaults(for: .geminiGenerateContent)
    XCTAssertEqual(gemini.baseURL, "https://api.cometapi.com/v1beta")
    XCTAssertEqual(gemini.model, "gemini-3-flash-preview")
    XCTAssertFalse(gemini.isEnabled)
  }

  func testEnabledProviderConfigurationsUseProductOrder() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)
    var openAIResponses = store.configuration(for: .openAIResponses)
    openAIResponses.isEnabled = true
    var gemini = store.configuration(for: .geminiGenerateContent)
    gemini.isEnabled = true
    var systemDictionary = store.configuration(for: .systemDictionary)
    systemDictionary.isEnabled = true

    store.updateConfiguration(gemini)
    store.updateConfiguration(systemDictionary)
    store.updateConfiguration(openAIResponses)

    XCTAssertEqual(
      store.enabledProviderConfigurations().map(\.providerID),
      [.openAIResponses, .geminiGenerateContent, .systemDictionary]
    )
  }

  func testProductProviderListHidesMock() {
    XCTAssertFalse(ProviderID.productCases.contains(.mock))
  }

  func testProductionSettingsMigratesMockPreferredProvider() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    defaults.set(ProviderID.mock.rawValue, forKey: "preferredProvider")

    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)
    let file = try readProviderFile(from: providerFileStore)

    XCTAssertEqual(store.preferredProvider, .openAIResponses)
    XCTAssertEqual(file.preferredProvider, ProviderID.openAIResponses.rawValue)
  }

  func testProductionSettingsMigratesMockProviderSettingsFile() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    providerFileStore.save(
      ProviderSettingsFile(
        preferredProvider: ProviderID.mock.rawValue,
        providers: [:]
      )
    )

    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)
    let file = try readProviderFile(from: providerFileStore)

    XCTAssertEqual(store.preferredProvider, .openAIResponses)
    XCTAssertEqual(file.preferredProvider, ProviderID.openAIResponses.rawValue)
  }

  func testMigratesLegacyTargetLanguageToLanguage2() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    defaults.set("ja", forKey: "targetLanguage")

    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)

    XCTAssertEqual(store.language1, "en")
    XCTAssertEqual(store.language2, "ja")
    XCTAssertEqual(store.targetLanguage, "ja")
    XCTAssertTrue(store.autoSwitchLanguages)
  }

  func testLanguage2AndTargetLanguageStayCompatible() throws {
    let defaults = try makeDefaults()
    let providerFileStore = makeProviderFileStore()
    let store = SettingsStore(defaults: defaults, providerFileStore: providerFileStore)

    store.language2 = "ko"
    XCTAssertEqual(store.targetLanguage, "ko")

    store.targetLanguage = "de"
    XCTAssertEqual(store.language2, "de")
  }

  private func makeDefaults() throws -> UserDefaults {
    let suiteName = "LexiRayTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }

  private func makeProviderFileStore() -> ProviderSettingsFileStore {
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("LexiRaySettingsStoreTests-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("providers.json", isDirectory: false)
    return ProviderSettingsFileStore(fileURL: fileURL)
  }

  private func readProviderFile(from store: ProviderSettingsFileStore) throws -> ProviderSettingsFile {
    let data = try Data(contentsOf: store.fileURL)
    return try JSONDecoder().decode(ProviderSettingsFile.self, from: data)
  }

  private func permission(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let value = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
    return value.intValue
  }
}
