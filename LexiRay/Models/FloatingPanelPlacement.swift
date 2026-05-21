import Foundation

enum FloatingPanelPlacement: String, CaseIterable, Identifiable, Codable {
  case nearCursor
  case screenCenter
  case topLeft
  case topRight
  case bottomLeft
  case bottomRight
  case lastPosition

  var id: Self {
    self
  }

  var title: String {
    switch self {
    case .nearCursor:
      "Near Cursor"
    case .screenCenter:
      "Screen Center"
    case .topLeft:
      "Top Left"
    case .topRight:
      "Top Right"
    case .bottomLeft:
      "Bottom Left"
    case .bottomRight:
      "Bottom Right"
    case .lastPosition:
      "Remember Last Position"
    }
  }
}

struct FloatingPanelSavedOrigin: Codable, Equatable {
  var x: Double
  var y: Double
}
