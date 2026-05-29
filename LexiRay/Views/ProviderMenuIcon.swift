import AppKit

enum ProviderMenuIconSource: Equatable {
  case asset(name: String, isTemplate: Bool)
  case systemSymbol(name: String)
}

extension ProviderID {
  static var menuIconSize: NSSize {
    NSSize(width: 16, height: 16)
  }

  var menuIconSource: ProviderMenuIconSource {
    switch iconKind {
    case .openAI:
      .asset(name: "OpenAIProviderIcon", isTemplate: true)
    case .anthropic:
      .asset(name: "AnthropicProviderIcon", isTemplate: true)
    case .gemini:
      .asset(name: "GeminiProviderIcon", isTemplate: false)
    case let .system(systemName):
      .systemSymbol(name: systemName)
    }
  }

  func menuIconImage(size: NSSize = Self.menuIconSize) -> NSImage? {
    switch menuIconSource {
    case let .asset(name, isTemplate):
      guard let source = NSImage(named: NSImage.Name(name)) else {
        return nil
      }
      return source.menuIconCopy(size: size, isTemplate: isTemplate)
    case let .systemSymbol(name):
      guard let source = NSImage(systemSymbolName: name, accessibilityDescription: displayName) else {
        return nil
      }
      return source.menuIconCopy(size: size, isTemplate: true)
    }
  }
}

private extension NSImage {
  func menuIconCopy(size: NSSize, isTemplate: Bool) -> NSImage? {
    guard let image = copy() as? NSImage else {
      return nil
    }

    image.size = size
    image.isTemplate = isTemplate
    return image
  }
}
