import Foundation

enum MainSection: String, CaseIterable, Identifiable {
  case dashboard
  case providers
  case settings

  var id: Self {
    self
  }

  var title: String {
    switch self {
    case .dashboard:
      "Dashboard"
    case .providers:
      "Providers"
    case .settings:
      "Settings"
    }
  }

  var systemImage: String {
    switch self {
    case .dashboard:
      "rectangle.grid.2x2"
    case .providers:
      "bolt.horizontal.circle"
    case .settings:
      "gearshape"
    }
  }
}
