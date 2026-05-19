@testable import LexiRay
import XCTest

@MainActor
final class LiveProviderSmokeTests: XCTestCase {
  func testLiveOpenAIChatCompletions() async throws {
    let environment = try liveEnvironment()
    let provider = OpenAIChatCompletionsProvider(
      configuration: LLMProviderConfiguration(
        provider: .openAIChatCompletions,
        baseURL: environment.openAIBaseURL,
        apiKey: environment.apiKey,
        model: environment.openAIModel
      )
    )

    try await assertLiveTranslation(from: provider)
  }

  func testLiveOpenAIResponses() async throws {
    let environment = try liveEnvironment()
    let provider = OpenAIResponsesProvider(
      configuration: LLMProviderConfiguration(
        provider: .openAIResponses,
        baseURL: environment.openAIBaseURL,
        apiKey: environment.apiKey,
        model: environment.openAIModel
      )
    )

    try await assertLiveTranslation(from: provider)
  }

  func testLiveAnthropicMessages() async throws {
    let environment = try liveEnvironment()
    let provider = AnthropicMessagesProvider(
      configuration: LLMProviderConfiguration(
        provider: .anthropicMessages,
        baseURL: environment.anthropicBaseURL,
        apiKey: environment.apiKey,
        model: environment.anthropicModel
      )
    )

    try await assertLiveTranslation(from: provider)
  }

  func testLiveGeminiGenerateContent() async throws {
    let environment = try liveEnvironment()
    let provider = GeminiGenerateContentProvider(
      configuration: LLMProviderConfiguration(
        provider: .geminiGenerateContent,
        baseURL: environment.geminiBaseURL,
        apiKey: environment.apiKey,
        model: environment.geminiModel
      )
    )

    try await assertLiveTranslation(from: provider)
  }

  private func assertLiveTranslation(from provider: TranslationProvider) async throws {
    let result = try await provider.translate(
      TranslationRequest(
        text: "Translate to Chinese: The app stays alive after closing the window.",
        sourceLanguage: "en",
        targetLanguage: "zh-Hans",
        selectionSource: .manual
      )
    )

    XCTAssertFalse(result.translatedText.trimmedForQuery.isEmpty)
  }

  private func liveEnvironment() throws -> LiveEnvironment {
    let env = ProcessInfo.processInfo.environment
    guard env["LEXIRAY_LIVE_PROVIDER_SMOKE"] == "1" else {
      throw XCTSkip("Set LEXIRAY_LIVE_PROVIDER_SMOKE=1 to run live provider smoke tests.")
    }

    return try LiveEnvironment(
      apiKey: liveAPIKey(env),
      openAIBaseURL: required("LEXIRAY_LIVE_OPENAI_BASE_URL", env),
      anthropicBaseURL: required("LEXIRAY_LIVE_ANTHROPIC_BASE_URL", env),
      geminiBaseURL: required("LEXIRAY_LIVE_GEMINI_BASE_URL", env),
      openAIModel: required("LEXIRAY_LIVE_OPENAI_MODEL", env),
      anthropicModel: required("LEXIRAY_LIVE_ANTHROPIC_MODEL", env),
      geminiModel: required("LEXIRAY_LIVE_GEMINI_MODEL", env)
    )
  }

  private func required(_ key: String, _ env: [String: String]) throws -> String {
    guard let value = env[key]?.nonEmptyTrimmed else {
      throw XCTSkip("Missing \(key).")
    }
    return value
  }

  private func liveAPIKey(_ env: [String: String]) throws -> String {
    if let path = env["LEXIRAY_LIVE_API_KEY_FILE"]?.nonEmptyTrimmed {
      let key = try String(contentsOfFile: path, encoding: .utf8).trimmedForQuery
      guard !key.isEmpty else {
        throw XCTSkip("Live API key file is empty.")
      }
      return key
    }

    return try required("LEXIRAY_LIVE_API_KEY", env)
  }

  private struct LiveEnvironment {
    let apiKey: String
    let openAIBaseURL: String
    let anthropicBaseURL: String
    let geminiBaseURL: String
    let openAIModel: String
    let anthropicModel: String
    let geminiModel: String
  }
}
