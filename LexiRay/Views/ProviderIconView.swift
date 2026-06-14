import SwiftUI

enum ProviderIconKind: Equatable {
  case openAI
  case anthropic
  case gemini
  case system(String)
}

extension ProviderID {
  var iconKind: ProviderIconKind {
    switch self {
    case .openAIChatCompletions, .openAIResponses:
      .openAI
    case .anthropicMessages:
      .anthropic
    case .geminiGenerateContent:
      .gemini
    case .mock, .systemDictionary:
      .system(systemImage)
    }
  }
}

struct ProviderIconView: View {
  let providerID: ProviderID

  var body: some View {
    switch providerID.iconKind {
    case .openAI:
      Image("OpenAIProviderIcon")
        .resizable()
        .scaledToFit()
        .frame(width: 17, height: 17)
        .accessibilityLabel("OpenAI")
    case .anthropic:
      Image("AnthropicProviderIcon")
        .resizable()
        .scaledToFit()
        .frame(width: 17, height: 17)
        .accessibilityLabel("Anthropic")
    case .gemini:
      Image("GeminiProviderIcon")
        .resizable()
        .scaledToFit()
        .frame(width: 17, height: 17)
        .accessibilityLabel("Gemini")
    case let .system(systemName):
      Image(systemName: systemName)
        .foregroundStyle(.secondary)
        .frame(width: 17, height: 17)
    }
  }
}
