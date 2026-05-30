import Foundation

enum AutoCopyMode: String, CaseIterable, Codable, Identifiable {
  case off
  case firstProviderSuccess

  var id: String {
    rawValue
  }

  var displayName: String {
    switch self {
    case .off:
      "Off"
    case .firstProviderSuccess:
      "First Provider Result"
    }
  }
}
