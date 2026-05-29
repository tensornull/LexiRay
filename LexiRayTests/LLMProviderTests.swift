@testable import LexiRay
import XCTest

@MainActor
final class LLMProviderTests: XCTestCase {
  func testOpenAIChatCompletionsRequestAndResponse() async throws {
    let client = MockHTTPClient(responseJSON: #"{"choices":[{"message":{"role":"assistant","content":"你好"}}]}"#)
    let provider = OpenAIChatCompletionsProvider(
      configuration: makeConfiguration(provider: .openAIChatCompletions, baseURL: "https://api.example.test/v1/"),
      client: client
    )

    let result = try await provider.translate(makeRequest())

    XCTAssertEqual(result.translatedText, "你好")
    XCTAssertEqual(client.request?.url?.absoluteString, "https://api.example.test/v1/chat/completions")
    XCTAssertEqual(client.request?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
    XCTAssertEqual(try client.stringBodyValue("model"), "test-model")
  }

  func testOpenAIChatCompletionsStreamsDeltas() async throws {
    let client = MockHTTPClient(
      responseJSON: "{}",
      streamLines: [
        #"data: {"choices":[{"delta":{"content":"你"}}]}"#,
        "",
        #"data: {"choices":[{"delta":{"content":"好"}}]}"#,
        "",
        "data: [DONE]",
        ""
      ]
    )
    let provider = OpenAIChatCompletionsProvider(
      configuration: makeConfiguration(provider: .openAIChatCompletions),
      client: client
    )

    let (partials, result) = try await collectStream(from: provider)

    XCTAssertEqual(partials, ["你", "你好"])
    XCTAssertEqual(result?.translatedText, "你好")
    XCTAssertEqual(try client.boolBodyValue("stream"), true)
  }

  func testOpenAIResponsesRequestAndResponse() async throws {
    let client = MockHTTPClient(responseJSON: #"{"output":[{"content":[{"type":"output_text","text":"你好"}]}]}"#)
    let provider = OpenAIResponsesProvider(
      configuration: makeConfiguration(provider: .openAIResponses),
      client: client
    )

    let result = try await provider.translate(makeRequest())

    XCTAssertEqual(result.translatedText, "你好")
    XCTAssertEqual(client.request?.url?.absoluteString, "https://api.example.test/v1/responses")
    XCTAssertEqual(client.request?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
    XCTAssertEqual(try client.stringBodyValue("input"), "hello")
    XCTAssertNil(try client.jsonBody()["temperature"])
    XCTAssertNil(try client.jsonBody()["max_output_tokens"])
    XCTAssertNil(try client.jsonBody()["reasoning"])
    XCTAssertNil(try client.jsonBody()["text"])
  }

  func testOpenAIResponsesIncludesEnabledAdvancedParameters() async throws {
    let client = MockHTTPClient(responseJSON: #"{"output":[{"content":[{"type":"output_text","text":"你好"}]}]}"#)
    let provider = OpenAIResponsesProvider(
      configuration: makeConfiguration(
        provider: .openAIResponses,
        advancedParameters: ProviderAdvancedParameters(
          temperature: 0.3,
          maxOutputTokens: 4096,
          reasoningEffort: .low,
          reasoningSummary: .auto,
          textVerbosity: .high
        )
      ),
      client: client
    )

    _ = try await provider.translate(makeRequest())
    let body = try client.jsonBody()
    let reasoning = try XCTUnwrap(body["reasoning"] as? [String: Any])
    let text = try XCTUnwrap(body["text"] as? [String: Any])

    XCTAssertEqual(try XCTUnwrap(body["temperature"] as? NSNumber).doubleValue, 0.3, accuracy: 0.001)
    XCTAssertEqual(try XCTUnwrap(body["max_output_tokens"] as? NSNumber).intValue, 4096)
    XCTAssertEqual(reasoning["effort"] as? String, "low")
    XCTAssertEqual(reasoning["summary"] as? String, "auto")
    XCTAssertEqual(text["verbosity"] as? String, "high")
  }

  func testOpenAIResponsesSkipsOutputItemsWithoutTextContent() async throws {
    let client = MockHTTPClient(responseJSON: #"{"output":[{"type":"reasoning"},{"content":[{"type":"output_text","text":"你好"}]}]}"#)
    let provider = OpenAIResponsesProvider(
      configuration: makeConfiguration(provider: .openAIResponses),
      client: client
    )

    let result = try await provider.translate(makeRequest())

    XCTAssertEqual(result.translatedText, "你好")
  }

  func testOpenAIResponsesStreamsDeltasAndFinalText() async throws {
    let client = MockHTTPClient(
      responseJSON: "{}",
      streamLines: [
        "event: response.output_text.delta",
        #"data: {"type":"response.output_text.delta","delta":"你"}"#,
        "",
        "event: response.output_text.delta",
        #"data: {"type":"response.output_text.delta","delta":"好"}"#,
        "",
        "event: response.output_text.done",
        #"data: {"type":"response.output_text.done","text":"你好"}"#,
        "",
        "event: response.completed",
        #"data: {"type":"response.completed"}"#,
        ""
      ]
    )
    let provider = OpenAIResponsesProvider(
      configuration: makeConfiguration(provider: .openAIResponses),
      client: client
    )

    let (partials, result) = try await collectStream(from: provider)

    XCTAssertEqual(partials, ["你", "你好", "你好"])
    XCTAssertEqual(result?.translatedText, "你好")
    XCTAssertEqual(try client.boolBodyValue("stream"), true)
  }

  func testOpenAIResponsesStreamingIncludesEnabledAdvancedParameters() async throws {
    let client = MockHTTPClient(
      responseJSON: "{}",
      streamLines: [
        "event: response.output_text.delta",
        #"data: {"type":"response.output_text.delta","delta":"你"}"#,
        "",
        "event: response.completed",
        #"data: {"type":"response.completed"}"#,
        ""
      ]
    )
    let provider = OpenAIResponsesProvider(
      configuration: makeConfiguration(
        provider: .openAIResponses,
        advancedParameters: ProviderAdvancedParameters(
          maxOutputTokens: 512,
          textVerbosity: .low
        )
      ),
      client: client
    )

    _ = try await collectStream(from: provider)
    let body = try client.jsonBody()
    let text = try XCTUnwrap(body["text"] as? [String: Any])

    XCTAssertEqual(try client.boolBodyValue("stream"), true)
    XCTAssertNil(body["temperature"])
    XCTAssertEqual(try XCTUnwrap(body["max_output_tokens"] as? NSNumber).intValue, 512)
    XCTAssertEqual(text["verbosity"] as? String, "low")
  }

  func testOpenAIResponsesKeepsStructuredMarkdownWhenFinalTextIsCollapsed() async throws {
    let structuredMarkdown = "# 更新日志\n\n本项目的所有显著变更都将记录在此文件中。\n\n## [0.3.0] - 2026-05-26\n\n### 新增\n\n- `models` 现在默认读取公共模型目录。\n- `model info` 显示模型的详细目录元数据。"
    let collapsedMarkdown = "# 更新日志 本项目的所有显著变更都将记录在此文件中。 ## [0.3.0] - 2026-05-26 ### 新增 - `models` 现在默认读取公共模型目录。 - `model info` 显示模型的详细目录元数据。"
    let client = MockHTTPClient(
      responseJSON: "{}",
      streamLines: [
        "event: response.output_text.delta",
        "data: \(try jsonObjectLine(type: "response.output_text.delta", key: "delta", value: structuredMarkdown))",
        "",
        "event: response.output_text.done",
        "data: \(try jsonObjectLine(type: "response.output_text.done", key: "text", value: collapsedMarkdown))",
        "",
        "event: response.completed",
        #"data: {"type":"response.completed"}"#,
        ""
      ]
    )
    let provider = OpenAIResponsesProvider(
      configuration: makeConfiguration(provider: .openAIResponses),
      client: client
    )

    let (partials, result) = try await collectStream(from: provider)

    XCTAssertEqual(partials.last, structuredMarkdown)
    XCTAssertEqual(result?.translatedText, structuredMarkdown)
  }

  func testAnthropicMessagesRequestAndResponse() async throws {
    let client = MockHTTPClient(responseJSON: #"{"content":[{"type":"text","text":"你好"}]}"#)
    let provider = AnthropicMessagesProvider(
      configuration: makeConfiguration(provider: .anthropicMessages),
      client: client
    )

    let result = try await provider.translate(makeRequest())

    XCTAssertEqual(result.translatedText, "你好")
    XCTAssertEqual(client.request?.url?.absoluteString, "https://api.example.test/v1/messages")
    XCTAssertEqual(client.request?.value(forHTTPHeaderField: "x-api-key"), "test-key")
    XCTAssertEqual(client.request?.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
    XCTAssertEqual(try client.stringBodyValue("model"), "test-model")
    let messages = try XCTUnwrap(try client.jsonBody()["messages"] as? [[String: Any]])
    let userContent = try XCTUnwrap(messages.first?["content"] as? String)
    XCTAssertTrue(userContent.contains("Translate the following source text into zh-Hans."))
    XCTAssertTrue(userContent.contains("Source text:\nhello"))
  }

  func testAnthropicMessagesStreamsTextDeltas() async throws {
    let client = MockHTTPClient(
      responseJSON: "{}",
      streamLines: [
        "event: content_block_delta",
        #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"你"}}"#,
        "",
        "event: ping",
        #"data: {"type":"ping"}"#,
        "",
        "event: content_block_delta",
        #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"好"}}"#,
        "",
        "event: message_stop",
        #"data: {"type":"message_stop"}"#,
        ""
      ]
    )
    let provider = AnthropicMessagesProvider(
      configuration: makeConfiguration(provider: .anthropicMessages),
      client: client
    )

    let (partials, result) = try await collectStream(from: provider)

    XCTAssertEqual(partials, ["你", "你好"])
    XCTAssertEqual(result?.translatedText, "你好")
    XCTAssertEqual(try client.boolBodyValue("stream"), true)
    let messages = try XCTUnwrap(try client.jsonBody()["messages"] as? [[String: Any]])
    let userContent = try XCTUnwrap(messages.first?["content"] as? String)
    XCTAssertTrue(userContent.contains("Source text:\nhello"))
  }

  func testGeminiGenerateContentRequestAndResponse() async throws {
    let client = MockHTTPClient(responseJSON: #"{"candidates":[{"content":{"parts":[{"text":"你好"}]}}]}"#)
    let provider = GeminiGenerateContentProvider(
      configuration: makeConfiguration(provider: .geminiGenerateContent, model: "gemini-test"),
      client: client
    )

    let result = try await provider.translate(makeRequest())

    XCTAssertEqual(result.translatedText, "你好")
    XCTAssertEqual(client.request?.url?.absoluteString, "https://api.example.test/v1/models/gemini-test:generateContent")
    XCTAssertEqual(client.request?.value(forHTTPHeaderField: "x-goog-api-key"), "test-key")
    XCTAssertNotNil(try client.jsonBody()["systemInstruction"])
  }

  func testGeminiGenerateContentStreamsTextDeltas() async throws {
    let client = MockHTTPClient(
      responseJSON: "{}",
      streamLines: [
        #"data: {"candidates":[{"content":{"parts":[{"text":"你"}]}}]}"#,
        "",
        #"data: {"candidates":[{"content":{"parts":[{"text":"好"}]}}]}"#,
        ""
      ]
    )
    let provider = GeminiGenerateContentProvider(
      configuration: makeConfiguration(provider: .geminiGenerateContent, model: "gemini-test"),
      client: client
    )

    let (partials, result) = try await collectStream(from: provider)

    XCTAssertEqual(partials, ["你", "你好"])
    XCTAssertEqual(result?.translatedText, "你好")
    XCTAssertEqual(client.request?.url?.absoluteString, "https://api.example.test/v1/models/gemini-test:streamGenerateContent?alt=sse")
  }

  func testGeminiStreamReturnsProviderErrorMessage() async throws {
    let client = MockHTTPClient(
      responseJSON: "{}",
      streamLines: [
        #"data: {"error":{"code":429,"message":"Resource has been exhausted (e.g. check quota).","status":"RESOURCE_EXHAUSTED"}}"#,
        ""
      ]
    )
    let provider = GeminiGenerateContentProvider(
      configuration: makeConfiguration(provider: .geminiGenerateContent, model: "gemini-test"),
      client: client
    )

    do {
      _ = try await collectStream(from: provider)
      XCTFail("Expected provider error")
    } catch let error as TranslationError {
      XCTAssertEqual(error, .network("Resource has been exhausted (e.g. check quota)."))
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testOpenAIResponsesStreamHTTPFailureIncludesResponseBodyAndRedactsSecrets() async throws {
    let client = MockHTTPClient(
      responseJSON: "{}",
      statusCode: 400,
      streamLines: [
        #"{"error":{"message":"Bad request from provider"},"authorization":"Bearer test-key","api_key":"test-key"}"#
      ]
    )
    let provider = OpenAIResponsesProvider(
      configuration: makeConfiguration(provider: .openAIResponses),
      client: client
    )

    do {
      _ = try await provider.streamTranslation(makeRequest())
      XCTFail("Expected provider error")
    } catch let error as TranslationError {
      let message = error.localizedDescription
      XCTAssertTrue(message.contains("OpenAI Responses request failed (HTTP 400)"))
      XCTAssertTrue(message.contains("Bad request from provider"))
      XCTAssertTrue(message.contains("Response body:"))
      XCTAssertTrue(message.contains("[redacted]"))
      XCTAssertFalse(message.contains("Bearer test-key"))
      XCTAssertFalse(message.contains("test-key"))
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testOpenAIResponsesStreamFailureIncludesNestedErrorAndEventBody() async throws {
    let client = MockHTTPClient(
      responseJSON: "{}",
      streamLines: [
        #"data: {"type":"response.failed","response":{"error":{"message":"Upstream timeout"}},"authorization":"Bearer test-key"}"#,
        ""
      ]
    )
    let provider = OpenAIResponsesProvider(
      configuration: makeConfiguration(provider: .openAIResponses),
      client: client
    )

    do {
      _ = try await collectStream(from: provider)
      XCTFail("Expected provider error")
    } catch let error as TranslationError {
      let message = error.localizedDescription
      XCTAssertTrue(message.contains("OpenAI Responses stream failed"))
      XCTAssertTrue(message.contains("Upstream timeout"))
      XCTAssertTrue(message.contains("Stream event:"))
      XCTAssertTrue(message.contains("response.failed"))
      XCTAssertTrue(message.contains("[redacted]"))
      XCTAssertFalse(message.contains("Bearer test-key"))
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testProviderRejectsMissingAPIKey() async throws {
    let client = MockHTTPClient(responseJSON: #"{"choices":[]}"#)
    let provider = OpenAIChatCompletionsProvider(
      configuration: makeConfiguration(provider: .openAIChatCompletions, apiKey: ""),
      client: client
    )

    do {
      _ = try await provider.translate(makeRequest())
      XCTFail("Expected missing API key")
    } catch let error as TranslationError {
      XCTAssertEqual(error, .missingAPIKey)
    }
  }

  func testMalformedStreamFailsProvider() async throws {
    let client = MockHTTPClient(responseJSON: "{}", streamLines: ["data: {", ""])
    let provider = OpenAIChatCompletionsProvider(
      configuration: makeConfiguration(provider: .openAIChatCompletions),
      client: client
    )

    do {
      _ = try await collectStream(from: provider)
      XCTFail("Expected malformed stream to throw")
    } catch let error as TranslationError {
      guard case .network = error else {
        return XCTFail("Expected network stream failure")
      }
    }
  }

  private func collectStream(from provider: TranslationProvider) async throws -> ([String], TranslationResult?) {
    let stream = try await provider.streamTranslation(makeRequest())
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

    return (partials, result)
  }

  private func makeRequest() -> TranslationRequest {
    TranslationRequest(text: "hello", sourceLanguage: "en", targetLanguage: "zh-Hans", selectionSource: .manual)
  }

  private func makeConfiguration(
    provider: ProviderID,
    baseURL: String = "https://api.example.test/v1",
    apiKey: String = "test-key",
    model: String = "test-model",
    advancedParameters: ProviderAdvancedParameters = ProviderAdvancedParameters()
  ) -> LLMProviderConfiguration {
    LLMProviderConfiguration(
      provider: provider,
      baseURL: baseURL,
      apiKey: apiKey,
      model: model,
      advancedParameters: advancedParameters
    )
  }
}

private final class MockHTTPClient: HTTPClient {
  private(set) var request: URLRequest?
  private let data: Data
  private let statusCode: Int
  private let streamLines: [String]

  init(responseJSON: String, statusCode: Int = 200, streamLines: [String] = []) {
    data = Data(responseJSON.utf8)
    self.statusCode = statusCode
    self.streamLines = streamLines
  }

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    self.request = request
    let response = try HTTPURLResponse(
      url: XCTUnwrap(request.url),
      statusCode: statusCode,
      httpVersion: nil,
      headerFields: nil
    )
    return try (data, XCTUnwrap(response))
  }

  func lineStream(for request: URLRequest) async throws -> HTTPLineStream {
    self.request = request
    let response = try HTTPURLResponse(
      url: XCTUnwrap(request.url),
      statusCode: statusCode,
      httpVersion: nil,
      headerFields: nil
    )
    let lines = AsyncThrowingStream<String, Error> { continuation in
      for line in streamLines {
        continuation.yield(line)
      }
      continuation.finish()
    }
    return try HTTPLineStream(lines: lines, response: XCTUnwrap(response))
  }

  func jsonBody() throws -> [String: Any] {
    let body = try XCTUnwrap(request?.httpBody)
    let object = try JSONSerialization.jsonObject(with: body)
    return try XCTUnwrap(object as? [String: Any])
  }

  func stringBodyValue(_ key: String) throws -> String? {
    try jsonBody()[key] as? String
  }

  func boolBodyValue(_ key: String) throws -> Bool? {
    try jsonBody()[key] as? Bool
  }
}

private func jsonObjectLine(type: String, key: String, value: String) throws -> String {
  let object = [
    "type": type,
    key: value
  ]
  let data = try JSONSerialization.data(withJSONObject: object)
  return try XCTUnwrap(String(data: data, encoding: .utf8))
}
