import Foundation

struct LLMProviderConfiguration {
  let provider: ProviderID
  let baseURL: String
  let apiKey: String
  let model: String

  var normalizedBaseURL: String {
    ProviderConfiguration.normalizeBaseURL(baseURL)
  }
}

struct OpenAIChatCompletionsProvider: TranslationProvider {
  let id: ProviderID = .openAIChatCompletions
  let name = ProviderID.openAIChatCompletions.displayName

  private let configuration: LLMProviderConfiguration
  private let client: HTTPClient

  init(configuration: LLMProviderConfiguration, client: HTTPClient = URLSession.shared) {
    self.configuration = configuration
    self.client = client
  }

  func translate(_ request: TranslationRequest) async throws -> TranslationResult {
    let text = try validatedText(request.text)
    let endpoint = try ProviderEndpoint.openAI(baseURL: configuration.normalizedBaseURL, path: "chat/completions")
    let body = OpenAIChatRequest(
      model: configuration.model,
      messages: [
        .init(role: "system", content: TranslationPrompt.instructions(targetLanguage: request.targetLanguage)),
        .init(role: "user", content: text)
      ],
      temperature: 0.2
    )

    let response: OpenAIChatResponse = try await performJSONRequest(
      endpoint: endpoint,
      apiKey: configuration.apiKey,
      body: body,
      client: client
    )

    guard let translatedText = response.choices.first?.message.content.nonEmptyTrimmed else {
      throw TranslationError.invalidResponse
    }

    return result(for: request, translatedText: translatedText, providerID: id, providerName: name)
  }

  func streamTranslation(_ request: TranslationRequest) async throws -> AsyncThrowingStream<TranslationStreamUpdate, Error> {
    let text = try validatedText(request.text)
    guard !configuration.apiKey.trimmedForQuery.isEmpty else {
      throw TranslationError.missingAPIKey
    }

    let endpoint = try ProviderEndpoint.openAI(baseURL: configuration.normalizedBaseURL, path: "chat/completions")
    let body = OpenAIChatRequest(
      model: configuration.model,
      messages: [
        .init(role: "system", content: TranslationPrompt.instructions(targetLanguage: request.targetLanguage)),
        .init(role: "user", content: text)
      ],
      temperature: 0.2,
      stream: true
    )

    var urlRequest = try jsonRequest(endpoint: endpoint, body: body)
    urlRequest.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
    let lineStream = try await openLineStream(
      from: urlRequest,
      client: client,
      providerFailureMessage: "\(name) request failed"
    )

    return makeStreamingTranslation(
      for: request,
      providerID: id,
      providerName: name,
      lineStream: lineStream,
      decodeEvent: openAIChatStreamAction
    )
  }
}

struct OpenAIResponsesProvider: TranslationProvider {
  let id: ProviderID = .openAIResponses
  let name = ProviderID.openAIResponses.displayName

  private let configuration: LLMProviderConfiguration
  private let client: HTTPClient

  init(configuration: LLMProviderConfiguration, client: HTTPClient = URLSession.shared) {
    self.configuration = configuration
    self.client = client
  }

  func translate(_ request: TranslationRequest) async throws -> TranslationResult {
    let text = try validatedText(request.text)
    let endpoint = try ProviderEndpoint.openAI(baseURL: configuration.normalizedBaseURL, path: "responses")
    let body = OpenAIResponsesRequest(
      model: configuration.model,
      instructions: TranslationPrompt.instructions(targetLanguage: request.targetLanguage),
      input: text,
      temperature: 0.2
    )

    let response: OpenAIResponsesResponse = try await performJSONRequest(
      endpoint: endpoint,
      apiKey: configuration.apiKey,
      body: body,
      client: client
    )

    guard let translatedText = response.translatedText?.nonEmptyTrimmed else {
      throw TranslationError.invalidResponse
    }

    return result(for: request, translatedText: translatedText, providerID: id, providerName: name)
  }

  func streamTranslation(_ request: TranslationRequest) async throws -> AsyncThrowingStream<TranslationStreamUpdate, Error> {
    let text = try validatedText(request.text)
    guard !configuration.apiKey.trimmedForQuery.isEmpty else {
      throw TranslationError.missingAPIKey
    }

    let endpoint = try ProviderEndpoint.openAI(baseURL: configuration.normalizedBaseURL, path: "responses")
    let body = OpenAIResponsesRequest(
      model: configuration.model,
      instructions: TranslationPrompt.instructions(targetLanguage: request.targetLanguage),
      input: text,
      temperature: 0.2,
      stream: true
    )

    var urlRequest = try jsonRequest(endpoint: endpoint, body: body)
    urlRequest.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
    let lineStream = try await openLineStream(
      from: urlRequest,
      client: client,
      providerFailureMessage: "\(name) request failed"
    )

    return makeStreamingTranslation(
      for: request,
      providerID: id,
      providerName: name,
      lineStream: lineStream,
      decodeEvent: openAIResponsesStreamAction
    )
  }
}

struct AnthropicMessagesProvider: TranslationProvider {
  let id: ProviderID = .anthropicMessages
  let name = ProviderID.anthropicMessages.displayName

  private let configuration: LLMProviderConfiguration
  private let client: HTTPClient

  init(configuration: LLMProviderConfiguration, client: HTTPClient = URLSession.shared) {
    self.configuration = configuration
    self.client = client
  }

  func translate(_ request: TranslationRequest) async throws -> TranslationResult {
    let text = try validatedText(request.text)
    guard !configuration.apiKey.trimmedForQuery.isEmpty else {
      throw TranslationError.missingAPIKey
    }

    let endpoint = try ProviderEndpoint.anthropic(baseURL: configuration.normalizedBaseURL)
    let body = AnthropicMessagesRequest(
      model: configuration.model,
      maxTokens: 2048,
      system: TranslationPrompt.instructions(targetLanguage: request.targetLanguage),
      messages: [.init(role: "user", content: text)]
    )

    var urlRequest = try jsonRequest(endpoint: endpoint, body: body)
    urlRequest.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
    urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

    let response: AnthropicMessagesResponse = try await decodeResponse(
      from: urlRequest,
      client: client,
      providerFailureMessage: "\(name) request failed"
    )

    guard let translatedText = response.content.compactMap(\.text).joined(separator: "\n").nonEmptyTrimmed else {
      throw TranslationError.invalidResponse
    }

    return result(for: request, translatedText: translatedText, providerID: id, providerName: name)
  }

  func streamTranslation(_ request: TranslationRequest) async throws -> AsyncThrowingStream<TranslationStreamUpdate, Error> {
    let text = try validatedText(request.text)
    guard !configuration.apiKey.trimmedForQuery.isEmpty else {
      throw TranslationError.missingAPIKey
    }

    let endpoint = try ProviderEndpoint.anthropic(baseURL: configuration.normalizedBaseURL)
    let body = AnthropicMessagesRequest(
      model: configuration.model,
      maxTokens: 2048,
      system: TranslationPrompt.instructions(targetLanguage: request.targetLanguage),
      messages: [.init(role: "user", content: text)],
      stream: true
    )

    var urlRequest = try jsonRequest(endpoint: endpoint, body: body)
    urlRequest.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
    urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    let lineStream = try await openLineStream(
      from: urlRequest,
      client: client,
      providerFailureMessage: "\(name) request failed"
    )

    return makeStreamingTranslation(
      for: request,
      providerID: id,
      providerName: name,
      lineStream: lineStream,
      decodeEvent: anthropicStreamAction
    )
  }
}

struct GeminiGenerateContentProvider: TranslationProvider {
  let id: ProviderID = .geminiGenerateContent
  let name = ProviderID.geminiGenerateContent.displayName

  private let configuration: LLMProviderConfiguration
  private let client: HTTPClient

  init(configuration: LLMProviderConfiguration, client: HTTPClient = URLSession.shared) {
    self.configuration = configuration
    self.client = client
  }

  func translate(_ request: TranslationRequest) async throws -> TranslationResult {
    let text = try validatedText(request.text)
    guard !configuration.apiKey.trimmedForQuery.isEmpty else {
      throw TranslationError.missingAPIKey
    }

    let endpoint = try ProviderEndpoint.gemini(baseURL: configuration.normalizedBaseURL, model: configuration.model)
    let body = GeminiGenerateContentRequest(
      systemInstruction: .init(parts: [.init(text: TranslationPrompt.instructions(targetLanguage: request.targetLanguage))]),
      contents: [
        .init(role: "user", parts: [.init(text: text)])
      ],
      generationConfig: .init(temperature: 0.2)
    )

    var urlRequest = try jsonRequest(endpoint: endpoint, body: body)
    urlRequest.setValue(configuration.apiKey, forHTTPHeaderField: "x-goog-api-key")

    let response: GeminiGenerateContentResponse = try await decodeResponse(
      from: urlRequest,
      client: client,
      providerFailureMessage: "\(name) request failed"
    )

    guard let translatedText = response.candidates
      .flatMap(\.content.parts)
      .compactMap(\.text)
      .joined(separator: "\n")
      .nonEmptyTrimmed
    else {
      throw TranslationError.invalidResponse
    }

    return result(for: request, translatedText: translatedText, providerID: id, providerName: name)
  }

  func streamTranslation(_ request: TranslationRequest) async throws -> AsyncThrowingStream<TranslationStreamUpdate, Error> {
    let text = try validatedText(request.text)
    guard !configuration.apiKey.trimmedForQuery.isEmpty else {
      throw TranslationError.missingAPIKey
    }

    let endpoint = try ProviderEndpoint.geminiStream(baseURL: configuration.normalizedBaseURL, model: configuration.model)
    let body = GeminiGenerateContentRequest(
      systemInstruction: .init(parts: [.init(text: TranslationPrompt.instructions(targetLanguage: request.targetLanguage))]),
      contents: [
        .init(role: "user", parts: [.init(text: text)])
      ],
      generationConfig: .init(temperature: 0.2)
    )

    var urlRequest = try jsonRequest(endpoint: endpoint, body: body)
    urlRequest.setValue(configuration.apiKey, forHTTPHeaderField: "x-goog-api-key")
    let lineStream = try await openLineStream(
      from: urlRequest,
      client: client,
      providerFailureMessage: "\(name) request failed"
    )

    return makeStreamingTranslation(
      for: request,
      providerID: id,
      providerName: name,
      lineStream: lineStream,
      decodeEvent: geminiStreamAction
    )
  }
}

enum TranslationPrompt {
  static func instructions(targetLanguage: String) -> String {
    """
    Translate the user's text into \(targetLanguage). Return only the translation. Preserve the original meaning, names, numbers, formatting, line breaks, Markdown, and code blocks. Do not add explanations.
    """
  }
}

enum ProviderEndpoint {
  static func openAI(baseURL: String, path: String) throws -> URL {
    try endpoint(baseURL: baseURL, path: path)
  }

  static func anthropic(baseURL: String) throws -> URL {
    let normalizedBaseURL = ProviderConfiguration.normalizeBaseURL(baseURL)
    guard let components = URLComponents(string: normalizedBaseURL) else {
      throw TranslationError.providerUnavailable("Provider base URL is invalid")
    }

    let path = components.path.isEmpty ? "v1/messages" : "messages"
    return try endpoint(baseURL: normalizedBaseURL, path: path)
  }

  static func gemini(baseURL: String, model: String) throws -> URL {
    let normalizedModel = model.hasPrefix("models/") ? model : "models/\(model)"
    return try endpoint(baseURL: baseURL, path: "\(normalizedModel):generateContent")
  }

  static func geminiStream(baseURL: String, model: String) throws -> URL {
    let normalizedModel = model.hasPrefix("models/") ? model : "models/\(model)"
    let url = try endpoint(baseURL: baseURL, path: "\(normalizedModel):streamGenerateContent")
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      throw TranslationError.providerUnavailable("Provider base URL is invalid")
    }

    var queryItems = components.queryItems ?? []
    queryItems.append(URLQueryItem(name: "alt", value: "sse"))
    components.queryItems = queryItems

    guard let streamURL = components.url else {
      throw TranslationError.providerUnavailable("Provider base URL is invalid")
    }

    return streamURL
  }

  private static func endpoint(baseURL: String, path: String) throws -> URL {
    let normalizedBaseURL = ProviderConfiguration.normalizeBaseURL(baseURL)
    guard !normalizedBaseURL.isEmpty, var components = URLComponents(string: normalizedBaseURL) else {
      throw TranslationError.providerUnavailable("Provider base URL is invalid")
    }

    let basePath = components.path
    let suffix = path.hasPrefix("/") ? String(path.dropFirst()) : path
    let joinedPath = [basePath, suffix]
      .filter { !$0.isEmpty }
      .joined(separator: "/")
    components.path = joinedPath.hasPrefix("/") ? joinedPath : "/\(joinedPath)"

    guard let url = components.url else {
      throw TranslationError.providerUnavailable("Provider base URL is invalid")
    }

    return url
  }
}

private func validatedText(_ rawText: String) throws -> String {
  guard let text = rawText.nonEmptyTrimmed else {
    throw TranslationError.emptyInput
  }
  return text
}

private func result(
  for request: TranslationRequest,
  translatedText: String,
  providerID: ProviderID,
  providerName: String
) -> TranslationResult {
  TranslationResult(
    request: request,
    providerID: providerID,
    providerName: providerName,
    translatedText: translatedText,
    detectedLanguage: request.sourceLanguage
  )
}

@MainActor
private func performJSONRequest<Response: Decodable>(
  endpoint: URL,
  apiKey: String,
  body: some Encodable,
  client: HTTPClient
) async throws -> Response {
  guard !apiKey.trimmedForQuery.isEmpty else {
    throw TranslationError.missingAPIKey
  }

  var request = try jsonRequest(endpoint: endpoint, body: body)
  request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
  return try await decodeResponse(from: request, client: client, providerFailureMessage: "Provider request failed")
}

private func jsonRequest(endpoint: URL, body: some Encodable) throws -> URLRequest {
  var request = URLRequest(url: endpoint)
  request.httpMethod = "POST"
  request.setValue("application/json", forHTTPHeaderField: "Content-Type")
  request.httpBody = try JSONEncoder().encode(body)
  return request
}

@MainActor
private func decodeResponse<Response: Decodable>(
  from request: URLRequest,
  client: HTTPClient,
  providerFailureMessage: String
) async throws -> Response {
  do {
    let (data, response) = try await client.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw TranslationError.network(providerFailureMessage)
    }

    guard (200 ..< 300).contains(httpResponse.statusCode) else {
      let message = ProviderErrorMessage.message(from: data) ?? providerFailureMessage
      throw TranslationError.network(message)
    }

    return try JSONDecoder().decode(Response.self, from: data)
  } catch let error as TranslationError {
    throw error
  } catch {
    throw TranslationError.network(error.localizedDescription)
  }
}

@MainActor
private func openLineStream(
  from request: URLRequest,
  client: HTTPClient,
  providerFailureMessage: String
) async throws -> HTTPLineStream {
  do {
    let stream = try await client.lineStream(for: request)
    guard let httpResponse = stream.response as? HTTPURLResponse else {
      throw TranslationError.network(providerFailureMessage)
    }

    guard (200 ..< 300).contains(httpResponse.statusCode) else {
      throw TranslationError.network(providerFailureMessage)
    }

    return stream
  } catch let error as TranslationError {
    throw error
  } catch {
    throw TranslationError.network(error.localizedDescription)
  }
}

@MainActor
private func makeStreamingTranslation(
  for request: TranslationRequest,
  providerID: ProviderID,
  providerName: String,
  lineStream: HTTPLineStream,
  decodeEvent: @escaping @Sendable (ServerSentEvent) throws -> ProviderStreamAction
) -> AsyncThrowingStream<TranslationStreamUpdate, Error> {
  AsyncThrowingStream { continuation in
    let task = Task { @MainActor in
      var parser = ServerSentEventParser()
      var accumulatedText = ""
      var finalText: String?
      var shouldStop = false

      func handle(_ event: ServerSentEvent) throws {
        switch try decodeEvent(event) {
        case .ignore:
          break
        case let .append(delta):
          accumulatedText += delta
          continuation.yield(.partial(accumulatedText))
        case let .finalText(text):
          finalText = text
          continuation.yield(.partial(text))
        case .done:
          shouldStop = true
        }
      }

      do {
        for try await line in lineStream.lines {
          if let event = parser.consume(line) {
            try handle(event)
          }

          if shouldStop {
            break
          }
        }

        if !shouldStop, let event = parser.finish() {
          try handle(event)
        }

        guard let translatedText = (finalText ?? accumulatedText).nonEmptyTrimmed else {
          throw TranslationError.invalidResponse
        }

        continuation.yield(
          .completed(
            result(
              for: request,
              translatedText: translatedText,
              providerID: providerID,
              providerName: providerName
            )
          )
        )
        continuation.finish()
      } catch let error as TranslationError {
        continuation.finish(throwing: error)
      } catch {
        continuation.finish(throwing: TranslationError.network(error.localizedDescription))
      }
    }
    continuation.onTermination = { @Sendable _ in
      task.cancel()
    }
  }
}

private enum ProviderStreamAction: Sendable {
  case ignore
  case append(String)
  case finalText(String)
  case done
}

private func openAIChatStreamAction(_ event: ServerSentEvent) throws -> ProviderStreamAction {
  if event.data == "[DONE]" {
    return .done
  }

  if event.event == "ping" {
    return .ignore
  }

  let data = Data(event.data.utf8)
  if let message = ProviderErrorMessage.message(from: data) {
    throw TranslationError.network(message)
  }

  let chunk = try JSONDecoder().decode(OpenAIChatStreamChunk.self, from: data)
  let delta = chunk.choices
    .compactMap(\.delta?.content)
    .joined()

  return delta.isEmpty ? .ignore : .append(delta)
}

private func openAIResponsesStreamAction(_ event: ServerSentEvent) throws -> ProviderStreamAction {
  if event.data == "[DONE]" {
    return .done
  }

  if event.event == "ping" {
    return .ignore
  }

  let data = Data(event.data.utf8)
  if let message = ProviderErrorMessage.message(from: data) {
    throw TranslationError.network(message)
  }

  let responseEvent = try JSONDecoder().decode(OpenAIResponsesStreamEvent.self, from: data)
  switch responseEvent.type {
  case "response.output_text.delta":
    return responseEvent.delta?.isEmpty == false ? .append(responseEvent.delta ?? "") : .ignore
  case "response.output_text.done":
    return responseEvent.text?.isEmpty == false ? .finalText(responseEvent.text ?? "") : .ignore
  case "response.completed":
    return .done
  case "response.failed", "response.incomplete":
    throw TranslationError.network(responseEvent.error?.message ?? "OpenAI Responses stream failed")
  default:
    return .ignore
  }
}

private func anthropicStreamAction(_ event: ServerSentEvent) throws -> ProviderStreamAction {
  if event.event == "ping" {
    return .ignore
  }

  let data = Data(event.data.utf8)
  if let message = ProviderErrorMessage.message(from: data) {
    throw TranslationError.network(message)
  }

  let responseEvent = try JSONDecoder().decode(AnthropicStreamEvent.self, from: data)
  switch responseEvent.type {
  case "content_block_delta" where responseEvent.delta?.type == "text_delta":
    return responseEvent.delta?.text?.isEmpty == false ? .append(responseEvent.delta?.text ?? "") : .ignore
  case "message_stop":
    return .done
  case "error":
    throw TranslationError.network(responseEvent.error?.message ?? "Anthropic stream failed")
  default:
    return .ignore
  }
}

private func geminiStreamAction(_ event: ServerSentEvent) throws -> ProviderStreamAction {
  if event.data == "[DONE]" || event.event == "ping" {
    return event.data == "[DONE]" ? .done : .ignore
  }

  let data = Data(event.data.utf8)
  if let message = ProviderErrorMessage.message(from: data) {
    throw TranslationError.network(message)
  }

  let response = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)
  let delta = response.candidates
    .flatMap(\.content.parts)
    .compactMap(\.text)
    .joined()

  return delta.isEmpty ? .ignore : .append(delta)
}

private enum ProviderErrorMessage {
  static func message(from data: Data) -> String? {
    if let decoded = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
      return decoded.error.message.nonEmptyTrimmed
    }

    if let decoded = try? JSONDecoder().decode(AnthropicErrorResponse.self, from: data) {
      return decoded.error.message.nonEmptyTrimmed
    }

    return nil
  }
}

private struct OpenAIChatRequest: Encodable {
  let model: String
  let messages: [OpenAIChatMessage]
  let temperature: Double
  let stream: Bool?

  init(model: String, messages: [OpenAIChatMessage], temperature: Double, stream: Bool? = nil) {
    self.model = model
    self.messages = messages
    self.temperature = temperature
    self.stream = stream
  }
}

private struct OpenAIChatMessage: Codable {
  let role: String
  let content: String
}

private struct OpenAIChatResponse: Decodable {
  let choices: [Choice]

  struct Choice: Decodable {
    let message: OpenAIChatMessage
  }
}

private struct OpenAIChatStreamChunk: Decodable {
  let choices: [Choice]

  struct Choice: Decodable {
    let delta: Delta?
  }

  struct Delta: Decodable {
    let content: String?
  }
}

private struct OpenAIResponsesRequest: Encodable {
  let model: String
  let instructions: String
  let input: String
  let temperature: Double
  let stream: Bool?

  init(model: String, instructions: String, input: String, temperature: Double, stream: Bool? = nil) {
    self.model = model
    self.instructions = instructions
    self.input = input
    self.temperature = temperature
    self.stream = stream
  }
}

private struct OpenAIResponsesResponse: Decodable {
  let outputText: String?
  let output: [OutputItem]?

  var translatedText: String? {
    outputText ?? output?
      .compactMap(\.content)
      .flatMap(\.self)
      .compactMap(\.text)
      .joined(separator: "\n")
  }

  enum CodingKeys: String, CodingKey {
    case outputText = "output_text"
    case output
  }

  struct OutputItem: Decodable {
    let content: [ContentItem]?
  }

  struct ContentItem: Decodable {
    let text: String?
  }
}

private struct OpenAIResponsesStreamEvent: Decodable {
  let type: String
  let delta: String?
  let text: String?
  let error: StreamError?
}

private struct AnthropicMessagesRequest: Encodable {
  let model: String
  let maxTokens: Int
  let system: String
  let messages: [AnthropicMessage]
  let stream: Bool?

  init(model: String, maxTokens: Int, system: String, messages: [AnthropicMessage], stream: Bool? = nil) {
    self.model = model
    self.maxTokens = maxTokens
    self.system = system
    self.messages = messages
    self.stream = stream
  }

  enum CodingKeys: String, CodingKey {
    case model
    case maxTokens = "max_tokens"
    case system
    case messages
    case stream
  }
}

private struct AnthropicMessage: Codable {
  let role: String
  let content: String
}

private struct AnthropicMessagesResponse: Decodable {
  let content: [Content]

  struct Content: Decodable {
    let type: String?
    let text: String?
  }
}

private struct AnthropicStreamEvent: Decodable {
  let type: String
  let delta: Delta?
  let error: StreamError?

  struct Delta: Decodable {
    let type: String?
    let text: String?
  }
}

private struct GeminiGenerateContentRequest: Encodable {
  let systemInstruction: GeminiContent
  let contents: [GeminiContent]
  let generationConfig: GeminiGenerationConfig
}

private struct GeminiContent: Codable {
  let role: String?
  let parts: [GeminiPart]

  init(role: String? = nil, parts: [GeminiPart]) {
    self.role = role
    self.parts = parts
  }
}

private struct GeminiPart: Codable {
  let text: String
}

private struct GeminiGenerationConfig: Encodable {
  let temperature: Double
}

private struct GeminiGenerateContentResponse: Decodable {
  let candidates: [Candidate]

  struct Candidate: Decodable {
    let content: GeminiContent
  }
}

private struct OpenAIErrorResponse: Decodable {
  let error: ErrorMessage

  struct ErrorMessage: Decodable {
    let message: String
  }
}

private struct AnthropicErrorResponse: Decodable {
  let error: ErrorMessage

  struct ErrorMessage: Decodable {
    let message: String
  }
}

private struct StreamError: Decodable {
  let message: String?
}
