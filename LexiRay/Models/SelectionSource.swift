import Foundation

enum SelectionSource: String, Codable {
  case accessibility
  case browserAppleScript
  case simulatedCopy
  case manual
  case ocr
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
    case .ocr:
      "OCR"
    case .unavailable:
      "Unavailable"
    }
  }
}

struct SelectionReadResult: Equatable {
  let text: String?
  let source: SelectionSource
  let failureReason: SelectionFailureReason?

  init(text: String?, source: SelectionSource, failureReason: SelectionFailureReason? = nil) {
    self.text = text
    self.source = source
    self.failureReason = failureReason
  }

  static var unavailable: SelectionReadResult {
    SelectionReadResult(text: nil, source: .unavailable, failureReason: .noSelection)
  }
}

enum SelectionFailureReason: Equatable {
  case accessibilityPermissionMissing
  case copyFailed
  case noSelection
}
