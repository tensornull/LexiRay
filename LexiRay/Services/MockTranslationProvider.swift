import Foundation

struct MockTranslationProvider: TranslationProvider {
  let id: ProviderID = .mock
  let name = "Mock"
  var streamingFixtureEnabled = false

  func translate(_ request: TranslationRequest) async throws -> TranslationResult {
    guard let text = request.text.nonEmptyTrimmed else {
      throw TranslationError.emptyInput
    }

    let direction = "\(request.sourceLanguage ?? "auto") -> \(request.targetLanguage)"
    let translatedText = "LexiRay mock translation:\nDirection: \(direction)\n\(text)"

    return TranslationResult(
      request: request,
      providerID: id,
      providerName: name,
      translatedText: translatedText,
      detectedLanguage: request.sourceLanguage
    )
  }

  func streamTranslation(_ request: TranslationRequest) async throws -> AsyncThrowingStream<TranslationStreamUpdate, Error> {
    guard streamingFixtureEnabled, request.text.contains("LexiRay streaming panel growth text") else {
      let result = try await translate(request)
      return AsyncThrowingStream { continuation in
        continuation.yield(.completed(result))
        continuation.finish()
      }
    }

    return AsyncThrowingStream { continuation in
      Task {
        continuation.yield(.partial("LexiRay streaming partial."))
        try? await Task.sleep(nanoseconds: 900_000_000)
        continuation.yield(
          .partial(
            """
            LexiRay streaming partial.

            这是一段逐步变长的 UI 场景文本，用来验证悬浮窗会随着流式输出增长高度，而不是一开始就占用很大空间。
            """
          )
        )
        try? await Task.sleep(nanoseconds: 900_000_000)
        continuation.yield(
          .completed(
            TranslationResult(
              request: request,
              providerID: id,
              providerName: name,
              translatedText: """
              LexiRay streaming partial.

              这是一段逐步变长的 UI 场景文本，用来验证悬浮窗会随着流式输出增长高度，而不是一开始就占用很大空间。

              最终结果继续保持可读的行宽、圆角和玻璃背景。
              """,
              detectedLanguage: request.sourceLanguage
            )
          )
        )
        continuation.finish()
      }
    }
  }
}
