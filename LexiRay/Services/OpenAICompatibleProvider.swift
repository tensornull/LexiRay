import Foundation

struct OpenAICompatibleConfiguration {
  let baseURL: String
  let apiKey: String
  let model: String
}

struct OpenAICompatibleProvider: TranslationProvider {
  let id: ProviderID = .openAICompatible
  let name = "OpenAI Compatible"

  private let configuration: OpenAICompatibleConfiguration
  private let session: URLSession

  init(configuration: OpenAICompatibleConfiguration, session: URLSession = .shared) {
    self.configuration = configuration
    self.session = session
  }

  func translate(_ request: TranslationRequest) async throws -> TranslationResult {
    guard let text = request.text.nonEmptyTrimmed else {
      throw TranslationError.emptyInput
    }

    guard !configuration.apiKey.trimmedForQuery.isEmpty else {
      throw TranslationError.missingAPIKey
    }

    guard let baseURL = URL(string: configuration.baseURL) else {
      throw TranslationError.providerUnavailable("OpenAI-compatible base URL is invalid")
    }

    var endpoint = baseURL
    endpoint.appendPathComponent("chat")
    endpoint.appendPathComponent("completions")

    var urlRequest = URLRequest(url: endpoint)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.httpBody = try JSONEncoder().encode(
      OpenAIChatRequest(
        model: configuration.model,
        messages: [
          .init(role: "system", content: "Translate the user's text into \(request.targetLanguage). Return only the translation."),
          .init(role: "user", content: text)
        ],
        temperature: 0.2
      )
    )

    do {
      let (data, response) = try await session.data(for: urlRequest)

      guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
        throw TranslationError.network("OpenAI-compatible provider request failed")
      }

      let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
      guard let translatedText = decoded.choices.first?.message.content.nonEmptyTrimmed else {
        throw TranslationError.invalidResponse
      }

      return TranslationResult(
        request: request,
        providerID: id,
        providerName: name,
        translatedText: translatedText,
        detectedLanguage: request.sourceLanguage
      )
    } catch let error as TranslationError {
      throw error
    } catch {
      throw TranslationError.network(error.localizedDescription)
    }
  }
}

private struct OpenAIChatRequest: Encodable {
  let model: String
  let messages: [OpenAIChatMessage]
  let temperature: Double
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
