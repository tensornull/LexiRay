@testable import LexiRay
import XCTest

@MainActor
final class SettingsStoreTests: XCTestCase {
  func testSettingsPersistProviderChoice() throws {
    let defaults = try makeDefaults()
    let store = SettingsStore(defaults: defaults)
    store.preferredProvider = .openAICompatible
    store.targetLanguage = "ja"

    let reloaded = SettingsStore(defaults: defaults)

    XCTAssertEqual(reloaded.preferredProvider, .openAICompatible)
    XCTAssertEqual(reloaded.targetLanguage, "ja")
  }

  func testResetProviderSettingsRestoresDefaults() throws {
    let defaults = try makeDefaults()
    let store = SettingsStore(defaults: defaults)
    store.preferredProvider = .openAICompatible
    store.openAIAPIKey = "secret"

    store.resetProviderSettings()

    XCTAssertEqual(store.preferredProvider, .mock)
    XCTAssertEqual(store.openAIAPIKey, "")
  }

  private func makeDefaults() throws -> UserDefaults {
    let suiteName = "LexiRayTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }
}
