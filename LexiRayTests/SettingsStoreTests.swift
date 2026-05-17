@testable import LexiRay
import XCTest

@MainActor
final class SettingsStoreTests: XCTestCase {
  private var defaults: UserDefaults!
  private var suiteName: String!

  override func setUp() {
    super.setUp()
    suiteName = "LexiRayTests-\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
    suiteName = nil
    super.tearDown()
  }

  func testSettingsPersistProviderChoice() {
    let store = SettingsStore(defaults: defaults)
    store.preferredProvider = .openAICompatible
    store.targetLanguage = "ja"

    let reloaded = SettingsStore(defaults: defaults)

    XCTAssertEqual(reloaded.preferredProvider, .openAICompatible)
    XCTAssertEqual(reloaded.targetLanguage, "ja")
  }

  func testResetProviderSettingsRestoresDefaults() {
    let store = SettingsStore(defaults: defaults)
    store.preferredProvider = .openAICompatible
    store.openAIAPIKey = "secret"

    store.resetProviderSettings()

    XCTAssertEqual(store.preferredProvider, .mock)
    XCTAssertEqual(store.openAIAPIKey, "")
  }
}
