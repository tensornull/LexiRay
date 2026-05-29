import Foundation

struct LLMProviderConfiguration {
  let provider: ProviderID
  let baseURL: String
  let apiKey: String
  let model: String
  let advancedParameters: ProviderAdvancedParameters

  init(
    provider: ProviderID,
    baseURL: String,
    apiKey: String,
    model: String,
    advancedParameters: ProviderAdvancedParameters = ProviderAdvancedParameters()
  ) {
    self.provider = provider
    self.baseURL = baseURL
    self.apiKey = apiKey
    self.model = model
    self.advancedParameters = advancedParameters
  }

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
    let text = try validatedText(request.llmInputText)
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
    let text = try validatedText(request.llmInputText)
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
    let text = try validatedText(request.llmInputText)
    let endpoint = try ProviderEndpoint.openAI(baseURL: configuration.normalizedBaseURL, path: "responses")
    let body = OpenAIResponsesRequest(
      model: configuration.model,
      instructions: TranslationPrompt.instructions(targetLanguage: request.targetLanguage),
      input: text,
      advancedParameters: configuration.advancedParameters
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
    let text = try validatedText(request.llmInputText)
    guard !configuration.apiKey.trimmedForQuery.isEmpty else {
      throw TranslationError.missingAPIKey
    }

    let endpoint = try ProviderEndpoint.openAI(baseURL: configuration.normalizedBaseURL, path: "responses")
    let body = OpenAIResponsesRequest(
      model: configuration.model,
      instructions: TranslationPrompt.instructions(targetLanguage: request.targetLanguage),
      input: text,
      advancedParameters: configuration.advancedParameters,
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
    let text = try validatedText(request.llmInputText)
    guard !configuration.apiKey.trimmedForQuery.isEmpty else {
      throw TranslationError.missingAPIKey
    }

    let endpoint = try ProviderEndpoint.anthropic(baseURL: configuration.normalizedBaseURL)
    let body = AnthropicMessagesRequest(
      model: configuration.model,
      maxTokens: 2048,
      system: TranslationPrompt.instructions(targetLanguage: request.targetLanguage),
      messages: [.init(role: "user", content: AnthropicTranslationPrompt.userContent(text: text, targetLanguage: request.targetLanguage))]
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
    let text = try validatedText(request.llmInputText)
    guard !configuration.apiKey.trimmedForQuery.isEmpty else {
      throw TranslationError.missingAPIKey
    }

    let endpoint = try ProviderEndpoint.anthropic(baseURL: configuration.normalizedBaseURL)
    let body = AnthropicMessagesRequest(
      model: configuration.model,
      maxTokens: 2048,
      system: TranslationPrompt.instructions(targetLanguage: request.targetLanguage),
      messages: [.init(role: "user", content: AnthropicTranslationPrompt.userContent(text: text, targetLanguage: request.targetLanguage))],
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
    let text = try validatedText(request.llmInputText)
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
    let text = try validatedText(request.llmInputText)
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
    Translate the user's text into \(targetLanguage). Return only the translation.

    Preserve paragraph count, paragraph order, blank lines, Markdown structure, fenced code block boundaries, names, numbers, URLs, keys, and identifiers.
    Preserve actual newline characters in Markdown. Do not collapse Markdown headings, lists, quotes, or code fences into one paragraph.
    If the input contains fenced code blocks, keep the fences and language tags. Inside code blocks, translate only natural-language prose, comments, or string values when that is clearly intended; do not change JSON keys, code syntax, indentation, or punctuation.
    Never convert a fenced code block into a bullet list, paragraph, quote, or inline text.
    Do not merge separate paragraphs. Do not add explanations.
    """
  }
}

private enum AnthropicTranslationPrompt {
  static func userContent(text: String, targetLanguage: String) -> String {
    """
    Translate the following source text into \(targetLanguage). Return only the translation.

    Source text:
    \(text)
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
      let responseBody = debugText(from: data)
      let message = providerHTTPFailureMessage(
        statusCode: httpResponse.statusCode,
        providerFailureMessage: providerFailureMessage,
        providerMessage: ProviderErrorMessage.message(from: data),
        responseBody: responseBody
      )
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
      let responseBody = await collectFailureBody(from: stream.lines)
      let message = providerHTTPFailureMessage(
        statusCode: httpResponse.statusCode,
        providerFailureMessage: providerFailureMessage,
        providerMessage: ProviderErrorMessage.message(fromText: responseBody),
        responseBody: responseBody
      )
      throw TranslationError.network(message)
    }

    return stream
  } catch let error as TranslationError {
    throw error
  } catch {
    throw TranslationError.network(error.localizedDescription)
  }
}

private let providerDebugBodyCharacterLimit = 6_000

private func providerHTTPFailureMessage(
  statusCode: Int,
  providerFailureMessage: String,
  providerMessage: String?,
  responseBody: String?
) -> String {
  var sections = ["\(providerFailureMessage) (HTTP \(statusCode))"]

  if let providerMessage = providerMessage?.nonEmptyTrimmed,
     providerMessage != providerFailureMessage
  {
    sections.append(providerMessage)
  }

  if let responseBody = sanitizedDebugSnippet(responseBody) {
    sections.append("Response body:\n\(responseBody)")
  }

  return sections.joined(separator: "\n\n")
}

private func providerStreamFailureMessage(
  providerFailureMessage: String,
  object: [String: Any]
) -> String {
  let providerMessage = ProviderErrorMessage.message(from: object)
  var sections = [providerFailureMessage]

  if let providerMessage = providerMessage?.nonEmptyTrimmed,
     providerMessage != providerFailureMessage
  {
    sections.append(providerMessage)
  }

  if let eventText = sanitizedDebugSnippet(debugText(fromJSONObject: object)) {
    sections.append("Stream event:\n\(eventText)")
  }

  return sections.joined(separator: "\n\n")
}

@MainActor
private func collectFailureBody(from lines: AsyncThrowingStream<String, Error>) async -> String? {
  var collected: [String] = []
  var characterCount = 0

  do {
    for try await line in lines {
      collected.append(line)
      characterCount += line.count + 1
      if characterCount >= providerDebugBodyCharacterLimit {
        break
      }
    }
  } catch {
    collected.append("Failed to read response body: \(error.localizedDescription)")
  }

  return collected.joined(separator: "\n").nonEmptyTrimmed
}

private func debugText(from data: Data) -> String? {
  guard !data.isEmpty else {
    return nil
  }

  if let object = try? JSONSerialization.jsonObject(with: data),
     let text = debugText(fromJSONObject: object)
  {
    return text
  }

  return String(data: data, encoding: .utf8)?.nonEmptyTrimmed ?? "\(data.count) response bytes"
}

private func debugText(fromJSONObject object: Any) -> String? {
  guard JSONSerialization.isValidJSONObject(object),
        let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
  else {
    return nil
  }

  return String(data: data, encoding: .utf8)?.nonEmptyTrimmed
}

private func sanitizedDebugSnippet(_ rawText: String?) -> String? {
  guard var text = rawText?.nonEmptyTrimmed else {
    return nil
  }

  text = replacingMatches(
    in: text,
    pattern: #"(?i)(Bearer\s+)[A-Za-z0-9._~+/\-=]+"#,
    options: [],
    with: "$1[redacted]"
  )
  text = replacingMatches(
    in: text,
    pattern: #"(?i)("(?:authorization|api[_-]?key|x-api-key|x-goog-api-key)"\s*:\s*")[^"]+(")"#,
    options: [],
    with: "$1[redacted]$2"
  )

  guard text.count > providerDebugBodyCharacterLimit else {
    return text
  }

  let omittedCount = text.count - providerDebugBodyCharacterLimit
  return "\(String(text.prefix(providerDebugBodyCharacterLimit)))\n[truncated \(omittedCount) characters]"
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
          continuation.yield(.partial(preferredStreamText(finalText: text, accumulatedText: accumulatedText)))
        case .done:
          shouldStop = true
        }
      }

      do {
        for try await line in lineStream.lines {
          for event in parser.consumeEvents(line) {
            try handle(event)
          }

          if shouldStop {
            break
          }
        }

        if !shouldStop, let event = parser.finish() {
          try handle(event)
        }

        guard let translatedText = preferredStreamText(finalText: finalText, accumulatedText: accumulatedText).nonEmptyTrimmed else {
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

private func preferredStreamText(finalText: String?, accumulatedText: String) -> String {
  guard let finalText = finalText?.nonEmptyTrimmed else {
    return accumulatedText
  }

  guard let accumulatedText = accumulatedText.nonEmptyTrimmed else {
    return finalText
  }

  if isMarkdownStructureDowngrade(finalText: finalText, accumulatedText: accumulatedText) {
    return accumulatedText
  }

  return finalText
}

private func isMarkdownStructureDowngrade(finalText: String, accumulatedText: String) -> Bool {
  let accumulatedScore = markdownBlockStructureScore(accumulatedText)
  guard accumulatedScore > 0 else {
    return false
  }

  let finalScore = markdownBlockStructureScore(finalText)
  let accumulatedLines = nonEmptyLineCount(accumulatedText)
  let finalLines = nonEmptyLineCount(finalText)

  return finalScore < accumulatedScore && accumulatedLines >= finalLines + 1
}

private func markdownBlockStructureScore(_ text: String) -> Int {
  countMatches(
    in: text,
    pattern: #"(?m)^\s{0,3}(?:#{1,6}\s+|[-*+]\s+|\d+\.\s+|>\s+|```)"#
  )
}

private func nonEmptyLineCount(_ text: String) -> Int {
  text.components(separatedBy: .newlines).filter { !$0.trimmedForQuery.isEmpty }.count
}

private func countMatches(in text: String, pattern: String) -> Int {
  guard let expression = try? NSRegularExpression(pattern: pattern) else {
    return 0
  }

  let range = NSRange(text.startIndex ..< text.endIndex, in: text)
  return expression.numberOfMatches(in: text, range: range)
}

private func replacingMatches(
  in text: String,
  pattern: String,
  options: NSRegularExpression.Options,
  with replacement: String
) -> String {
  guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
    return text
  }

  let range = NSRange(text.startIndex ..< text.endIndex, in: text)
  return expression.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
}

private enum ProviderStreamAction {
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

  let object = try streamJSONObject(from: event)
  if let message = ProviderErrorMessage.message(from: object) {
    throw TranslationError.network(message)
  }

  let delta = (object["choices"] as? [[String: Any]])?
    .compactMap { choice in
      (choice["delta"] as? [String: Any])?["content"] as? String
    }
    .joined()
    ?? ""

  return delta.isEmpty ? .ignore : .append(delta)
}

private func openAIResponsesStreamAction(_ event: ServerSentEvent) throws -> ProviderStreamAction {
  if event.data == "[DONE]" {
    return .done
  }

  if event.event == "ping" {
    return .ignore
  }

  let object = try streamJSONObject(from: event)
  let type = object["type"] as? String ?? event.event ?? ""
  if let message = ProviderErrorMessage.message(from: object),
     isFailureEvent(object, fallbackEventName: event.event),
     type != "response.failed",
     type != "response.incomplete"
  {
    throw TranslationError.network(message)
  }

  switch type {
  case "response.output_text.delta":
    return stringValue("delta", in: object)?.isEmpty == false ? .append(stringValue("delta", in: object) ?? "") : .ignore
  case "response.output_text.done":
    return stringValue("text", in: object)?.isEmpty == false ? .finalText(stringValue("text", in: object) ?? "") : .ignore
  case "response.completed":
    return .done
  case "response.failed", "response.incomplete":
    throw TranslationError.network(providerStreamFailureMessage(
      providerFailureMessage: "OpenAI Responses stream failed",
      object: object
    ))
  default:
    return .ignore
  }
}

private func anthropicStreamAction(_ event: ServerSentEvent) throws -> ProviderStreamAction {
  if event.event == "ping" {
    return .ignore
  }

  let object = try streamJSONObject(from: event)
  if let message = ProviderErrorMessage.message(from: object), isFailureEvent(object, fallbackEventName: event.event) {
    throw TranslationError.network(message)
  }

  let type = object["type"] as? String ?? event.event ?? ""
  switch type {
  case "content_block_delta" where (object["delta"] as? [String: Any])?["type"] as? String == "text_delta":
    let text = (object["delta"] as? [String: Any])?["text"] as? String
    return text?.isEmpty == false ? .append(text ?? "") : .ignore
  case "message_stop":
    return .done
  case "error":
    throw TranslationError.network(ProviderErrorMessage.message(from: object) ?? "Anthropic stream failed")
  default:
    return .ignore
  }
}

private func geminiStreamAction(_ event: ServerSentEvent) throws -> ProviderStreamAction {
  if event.data == "[DONE]" || event.event == "ping" {
    return event.data == "[DONE]" ? .done : .ignore
  }

  let object = try streamJSONObject(from: event)
  if let message = ProviderErrorMessage.message(from: object) {
    throw TranslationError.network(message)
  }

  let delta = (object["candidates"] as? [[String: Any]])?
    .compactMap { candidate -> String? in
      guard let content = candidate["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]]
      else {
        return nil
      }
      return parts.compactMap { $0["text"] as? String }.joined()
    }
    .joined()
    ?? ""

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

    if let decoded = try? JSONDecoder().decode(GoogleErrorResponse.self, from: data) {
      return decoded.error.message.nonEmptyTrimmed
    }

    return nil
  }

  static func message(from object: [String: Any]) -> String? {
    guard let error = object["error"] else {
      if let response = object["response"] as? [String: Any] {
        return message(from: response)
      }
      return nil
    }

    if let message = error as? String {
      return message.nonEmptyTrimmed
    }

    if let errorObject = error as? [String: Any] {
      if let message = errorObject["message"] as? String {
        return message.nonEmptyTrimmed
      }
      if let message = errorObject["error"] as? String {
        return message.nonEmptyTrimmed
      }
    }

    return nil
  }

  static func message(fromText text: String?) -> String? {
    guard let text = text?.nonEmptyTrimmed,
          let data = text.data(using: .utf8)
    else {
      return nil
    }

    return message(from: data)
  }
}

private func streamJSONObject(from event: ServerSentEvent) throws -> [String: Any] {
  let data = Data(event.data.utf8)
  guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
    throw TranslationError.network("Provider stream returned malformed JSON.")
  }
  return object
}

private func stringValue(_ key: String, in object: [String: Any]) -> String? {
  object[key] as? String
}

private func isFailureEvent(_ object: [String: Any], fallbackEventName: String?) -> Bool {
  let type = object["type"] as? String ?? fallbackEventName ?? ""
  return type.contains("failed") || type.contains("error") || type.contains("incomplete")
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
  let temperature: Double?
  let maxOutputTokens: Int?
  let reasoning: OpenAIResponsesReasoning?
  let text: OpenAIResponsesText?
  let stream: Bool?

  init(
    model: String,
    instructions: String,
    input: String,
    advancedParameters: ProviderAdvancedParameters,
    stream: Bool? = nil
  ) {
    self.model = model
    self.instructions = instructions
    self.input = input
    temperature = advancedParameters.temperature.map { min(max($0, 0), 2) }
    maxOutputTokens = advancedParameters.maxOutputTokens.flatMap { $0 > 0 ? $0 : nil }
    reasoning = OpenAIResponsesReasoning(
      effort: advancedParameters.reasoningEffort,
      summary: advancedParameters.reasoningSummary
    )
    text = OpenAIResponsesText(verbosity: advancedParameters.textVerbosity)
    self.stream = stream
  }

  enum CodingKeys: String, CodingKey {
    case model
    case instructions
    case input
    case temperature
    case maxOutputTokens = "max_output_tokens"
    case reasoning
    case text
    case stream
  }
}

private struct OpenAIResponsesReasoning: Encodable {
  let effort: OpenAIReasoningEffort?
  let summary: OpenAIReasoningSummary?

  init?(effort: OpenAIReasoningEffort?, summary: OpenAIReasoningSummary?) {
    guard effort != nil || summary != nil else {
      return nil
    }
    self.effort = effort
    self.summary = summary
  }
}

private struct OpenAIResponsesText: Encodable {
  let verbosity: OpenAITextVerbosity?

  init?(verbosity: OpenAITextVerbosity?) {
    guard verbosity != nil else {
      return nil
    }
    self.verbosity = verbosity
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
  let text: String?
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

private struct GoogleErrorResponse: Decodable {
  let error: ErrorMessage

  struct ErrorMessage: Decodable {
    let message: String
  }
}

private struct StreamError: Decodable {
  let message: String?
}
