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
  }

  func testNormalizeBaseURLTrimsTrailingSlashes() {
    XCTAssertEqual(
      ProviderConfiguration.normalizeBaseURL(" https://api.example.test/v1/// "),
      "https://api.example.test/v1"
    )
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
}
