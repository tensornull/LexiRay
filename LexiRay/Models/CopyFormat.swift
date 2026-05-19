import Foundation

enum CopyFormat: String, CaseIterable, Codable, Identifiable {
  case originalText
  case plainText
  case markdown
  case html

  var id: String {
    rawValue
  }

  var displayName: String {
    switch self {
    case .originalText:
      "Original Text"
    case .plainText:
      "Plain Text"
    case .markdown:
      "Markdown"
    case .html:
      "HTML"
    }
  }
}
