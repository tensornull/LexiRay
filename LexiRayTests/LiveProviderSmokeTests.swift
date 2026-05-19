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

    try await assertLiveStreamingTranslation(from: provider)
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

    try await assertLiveStreamingTranslation(from: provider)
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

    try await assertLiveStreamingTranslation(from: provider)
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

    try await assertLiveStreamingTranslation(from: provider)
  }

  private func assertLiveStreamingTranslation(from provider: TranslationProvider) async throws {
    let stream = try await provider.streamTranslation(
      TranslationRequest(
        text: "hello",
        sourceLanguage: "en",
        targetLanguage: "zh-Hans",
        selectionSource: .manual
      )
    )
    var partials: [String] = []
    var result: TranslationResult?

    for try await update in stream {
      switch update {
      case let .partial(text):
        partials.append(text)
      case let .completed(completed):
        result = completed
      }
    }

    XCTAssertFalse(partials.isEmpty, "\(provider.name) did not emit streaming partials.")
    XCTAssertFalse(result?.translatedText.trimmedForQuery.isEmpty ?? true)
  }

  private func liveEnvironment() throws -> LiveEnvironment {
    let env = ProcessInfo.processInfo.environment
    if env["LEXIRAY_LIVE_PROVIDER_SMOKE"] == "1" {
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

    let fileURL = Self.smokeConfigurationURL
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      throw XCTSkip("Set LEXIRAY_LIVE_PROVIDER_SMOKE=1 or create \(fileURL.path) to run live provider smoke tests.")
    }

    let data = try Data(contentsOf: fileURL)
    return try JSONDecoder().decode(LiveEnvironment.self, from: data).resolved()
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

  private static var smokeConfigurationURL: URL {
    URL(fileURLWithPath: "/tmp/lexiray-live-provider-smoke.json")
  }

  private struct LiveEnvironment: Decodable {
    let apiKey: String
    let apiKeyFile: String?
    let openAIBaseURL: String
    let anthropicBaseURL: String
    let geminiBaseURL: String
    let openAIModel: String
    let anthropicModel: String
    let geminiModel: String

    init(
      apiKey: String,
      apiKeyFile: String? = nil,
      openAIBaseURL: String,
      anthropicBaseURL: String,
      geminiBaseURL: String,
      openAIModel: String,
      anthropicModel: String,
      geminiModel: String
    ) {
      self.apiKey = apiKey
      self.apiKeyFile = apiKeyFile
      self.openAIBaseURL = openAIBaseURL
      self.anthropicBaseURL = anthropicBaseURL
      self.geminiBaseURL = geminiBaseURL
      self.openAIModel = openAIModel
      self.anthropicModel = anthropicModel
      self.geminiModel = geminiModel
    }

    func resolved() throws -> Self {
      guard apiKey.isEmpty, let apiKeyFile else {
        return self
      }

      let key = try String(contentsOfFile: apiKeyFile, encoding: .utf8).trimmedForQuery
      guard !key.isEmpty else {
        throw XCTSkip("Live API key file is empty.")
      }

      return Self(
        apiKey: key,
        apiKeyFile: nil,
        openAIBaseURL: openAIBaseURL,
        anthropicBaseURL: anthropicBaseURL,
        geminiBaseURL: geminiBaseURL,
        openAIModel: openAIModel,
        anthropicModel: anthropicModel,
        geminiModel: geminiModel
      )
    }
  }
}
