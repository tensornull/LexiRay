import Foundation

enum SelectionSource: String, Codable {
  case accessibility
  case browserAppleScript
  case simulatedCopy
  case manual
  case unavailable

  var displayName: String {
    switch self {
    case .accessibility:
      "Accessibility"
    case .browserAppleScript:
      "Browser"
    case .simulatedCopy:
      "Clipboard"
    case .manual:
      "Manual"
    case .unavailable:
      "Unavailable"
    }
  }
}

struct SelectionReadResult: Equatable {
  let text: String?
  let source: SelectionSource

  static let unavailable = SelectionReadResult(text: nil, source: .unavailable)
}
