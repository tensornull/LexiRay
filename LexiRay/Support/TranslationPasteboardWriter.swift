import AppKit
import Foundation

enum TranslationPasteboardWriter {
  static var markdownPasteboardType: NSPasteboard.PasteboardType {
    NSPasteboard.PasteboardType("net.daringfireball.markdown")
  }

  static func write(
    result: TranslationResult,
    format: CopyFormat,
    to pasteboard: NSPasteboard = .general
  ) {
    let rawText = result.translatedText
    let text = string(for: rawText, format: format)
    pasteboard.clearContents()

    switch format {
    case .originalText, .plainText:
      pasteboard.setString(text, forType: .string)
    case .markdown:
      pasteboard.setString(text, forType: Self.markdownPasteboardType)
      pasteboard.setString(text, forType: .string)
    case .html:
      pasteboard.setString(text, forType: .html)
      pasteboard.setString(RichTranslationRenderer.plainString(for: rawText), forType: .string)
    }
  }

  static func string(for rawText: String, format: CopyFormat) -> String {
    switch format {
    case .originalText:
      rawText
    case .plainText:
      RichTranslationRenderer.plainString(for: rawText)
    case .markdown:
      rawText
    case .html:
      RichTranslationRenderer.htmlString(for: rawText)
    }
  }
}
