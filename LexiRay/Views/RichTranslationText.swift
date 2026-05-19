import AppKit
import SwiftUI

struct RichTranslationText: View {
  let text: String
  var font: Font
  var lineLimit: Int?

  var body: some View {
    Text(RichTranslationRenderer.attributedString(for: text))
      .font(font)
      .textSelection(.enabled)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .lineLimit(lineLimit)
  }
}

enum RichTranslationRenderer {
  static func attributedString(for text: String) -> AttributedString {
    if looksLikeHTML(text), let html = htmlAttributedString(for: text) {
      return html
    }

    if let markdown = try? AttributedString(markdown: text) {
      return markdown
    }

    return AttributedString(text)
  }

  static func plainString(for text: String) -> String {
    String(attributedString(for: text).characters)
  }

  static func htmlString(for text: String) -> String {
    if looksLikeHTML(text) {
      return sanitizedHTML(text)
    }

    let attributed = NSAttributedString(attributedString(for: text))
    let range = NSRange(location: 0, length: attributed.length)
    guard let data = try? attributed.data(
      from: range,
      documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
    ), let html = String(data: data, encoding: .utf8) else {
      return "<p>\(escapeHTML(plainString(for: text)))</p>"
    }

    return sanitizedHTML(html)
  }

  static func sanitizedHTML(_ html: String) -> String {
    var sanitized = html
    sanitized = replacingMatches(
      in: sanitized,
      pattern: #"<(script|style|iframe|object|embed|img)\b[^>]*>.*?</\1>"#,
      options: [.caseInsensitive, .dotMatchesLineSeparators],
      with: ""
    )
    sanitized = replacingMatches(
      in: sanitized,
      pattern: #"<(script|style|iframe|object|embed|img)\b[^>]*?/?>"#,
      options: [.caseInsensitive, .dotMatchesLineSeparators],
      with: ""
    )
    sanitized = replacingMatches(
      in: sanitized,
      pattern: #"\s+on[a-z]+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)"#,
      options: [.caseInsensitive],
      with: ""
    )
    sanitized = replacingMatches(
      in: sanitized,
      pattern: #"\s+(href|src)\s*=\s*("javascript:[^"]*"|'javascript:[^']*'|javascript:[^\s>]+)"#,
      options: [.caseInsensitive],
      with: ""
    )
    return sanitized
  }

  private static func looksLikeHTML(_ text: String) -> Bool {
    text.range(
      of: #"<[A-Za-z][A-Za-z0-9:-]*(\s|>|/)"#,
      options: .regularExpression
    ) != nil
  }

  private static func htmlAttributedString(for html: String) -> AttributedString? {
    let sanitized = sanitizedHTML(html)
    guard let data = sanitized.data(using: .utf8) else {
      return nil
    }

    guard let attributed = try? NSAttributedString(
      data: data,
      options: [
        .documentType: NSAttributedString.DocumentType.html,
        .characterEncoding: String.Encoding.utf8.rawValue
      ],
      documentAttributes: nil
    ) else {
      return nil
    }

    return AttributedString(attributed)
  }

  private static func replacingMatches(
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

  private static func escapeHTML(_ text: String) -> String {
    text
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&#39;")
  }
}
