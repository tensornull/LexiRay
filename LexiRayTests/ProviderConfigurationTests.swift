import AppKit
@testable import LexiRay
import XCTest

final class ProviderConfigurationTests: XCTestCase {
  func testDecodesConfigurationWithoutDisplayName() throws {
    let data = try JSONSerialization.data(withJSONObject: [
      "providerID": ProviderID.openAIResponses.rawValue,
      "baseURL": "https://example.test/v1",
      "model": "gpt-test",
      "isEnabled": true
    ])

    let configuration = try JSONDecoder().decode(ProviderConfiguration.self, from: data)

    XCTAssertEqual(configuration.displayName, "")
    XCTAssertEqual(configuration.effectiveDisplayName, ProviderID.openAIResponses.displayName)
    XCTAssertTrue(configuration.advancedParameters.isEmpty)
  }

  func testNormalizeBaseURLTrimsTrailingSlashes() {
    XCTAssertEqual(
      ProviderConfiguration.normalizeBaseURL(" https://api.example.test/v1/// "),
      "https://api.example.test/v1"
    )
  }

  func testBuiltInDefaultEquivalentDisplayNameIsNotCustom() {
    let configuration = ProviderConfiguration(
      providerID: .openAIChatCompletions,
      displayName: "OpenAIChatCompletions",
      baseURL: "https://example.test/v1",
      model: "chat-test",
      isEnabled: true
    )

    XCTAssertEqual(configuration.effectiveDisplayName, ProviderID.openAIChatCompletions.displayName)
    XCTAssertFalse(configuration.hasCustomDisplayName)
    XCTAssertEqual(configuration.normalizedForStorage().displayName, "")
  }

  func testCustomProviderDisplayNameIsPreserved() {
    let configuration = ProviderConfiguration(
      id: "openAIChatCompletions-custom",
      providerID: .openAIChatCompletions,
      displayName: "OpenAIChatCompletions",
      baseURL: "https://example.test/v1",
      model: "chat-test",
      isEnabled: true
    )

    XCTAssertEqual(configuration.effectiveDisplayName, "OpenAIChatCompletions")
    XCTAssertTrue(configuration.hasCustomDisplayName)
    XCTAssertEqual(configuration.normalizedForStorage().displayName, "OpenAIChatCompletions")
  }

  func testOpenAIEndpointPreservesBasePath() throws {
    let url = try ProviderEndpoint.openAI(baseURL: "https://api.example.test/custom/v1/", path: "responses")

    XCTAssertEqual(url.absoluteString, "https://api.example.test/custom/v1/responses")
  }

  func testGeminiEndpointBuildsGenerateContentPath() throws {
    let url = try ProviderEndpoint.gemini(baseURL: "https://api.example.test/v1beta", model: "gemini-test")

    XCTAssertEqual(url.absoluteString, "https://api.example.test/v1beta/models/gemini-test:generateContent")
  }

  func testAnthropicEndpointAddsVersionForRootBaseURL() throws {
    let url = try ProviderEndpoint.anthropic(baseURL: "https://api.example.test")

    XCTAssertEqual(url.absoluteString, "https://api.example.test/v1/messages")
  }

  func testAnthropicEndpointPreservesVersionedBaseURL() throws {
    let url = try ProviderEndpoint.anthropic(baseURL: "https://api.example.test/v1")

    XCTAssertEqual(url.absoluteString, "https://api.example.test/v1/messages")
  }

  func testLLMProvidersUseBrandIconKinds() {
    XCTAssertEqual(ProviderID.openAIResponses.iconKind, .openAI)
    XCTAssertEqual(ProviderID.openAIChatCompletions.iconKind, .openAI)
    XCTAssertEqual(ProviderID.anthropicMessages.iconKind, .anthropic)
    XCTAssertEqual(ProviderID.geminiGenerateContent.iconKind, .gemini)
  }

  func testNonLLMProvidersFallbackToSystemIcons() {
    XCTAssertEqual(ProviderID.systemDictionary.iconKind, .system("book"))
    XCTAssertEqual(ProviderID.mock.iconKind, .system("hammer"))
  }

  func testAddProviderMenuUsesOfficialAssetIconsAtFixedSize() {
    let expectedSize = ProviderID.menuIconSize

    let officialIcons: [(ProviderID, ProviderMenuIconSource)] = [
      (.openAIResponses, .asset(name: "OpenAIProviderIcon", isTemplate: false)),
      (.openAIChatCompletions, .asset(name: "OpenAIProviderIcon", isTemplate: false)),
      (.anthropicMessages, .asset(name: "AnthropicProviderIcon", isTemplate: false)),
      (.geminiGenerateContent, .asset(name: "GeminiProviderIcon", isTemplate: false))
    ]

    for (providerID, source) in officialIcons {
      XCTAssertEqual(providerID.menuIconSource, source)

      let image = providerID.menuIconImage()
      XCTAssertNotNil(image, "\(providerID.displayName) should load its official menu icon asset")
      XCTAssertEqual(image?.size.width, expectedSize.width)
      XCTAssertEqual(image?.size.height, expectedSize.height)

      if case let .asset(_, isTemplate) = source {
        XCTAssertEqual(image?.isTemplate, isTemplate)
      }
    }
  }

  func testAddProviderMenuItemCarriesProviderIdentityAndIcon() {
    let item = ProviderAddMenuItemFactory.makeProviderItem(
      providerID: .openAIResponses,
      target: nil,
      action: nil
    )

    XCTAssertEqual(item.title, ProviderID.openAIResponses.displayName)
    XCTAssertEqual(item.representedObject as? String, ProviderID.openAIResponses.rawValue)
    XCTAssertEqual(item.image?.size.width, ProviderID.menuIconSize.width)
    XCTAssertEqual(item.image?.size.height, ProviderID.menuIconSize.height)
  }
}
