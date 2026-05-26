import AppKit

enum FloatingPanelPositionResolver {
  static let margin: CGFloat = 12
  private static let cursorOffset: CGFloat = 14

  static func origin(
    placement: FloatingPanelPlacement,
    panelSize: NSSize,
    visibleFrame: NSRect,
    mouseLocation: NSPoint,
    lastOrigin: NSPoint?
  ) -> NSPoint {
    let rawOrigin: NSPoint = switch placement {
    case .nearCursor:
      NSPoint(
        x: mouseLocation.x + cursorOffset,
        y: mouseLocation.y - panelSize.height - cursorOffset
      )
    case .screenCenter:
      NSPoint(
        x: visibleFrame.midX - panelSize.width / 2,
        y: visibleFrame.midY - panelSize.height / 2
      )
    case .topLeft:
      NSPoint(
        x: visibleFrame.minX + margin,
        y: visibleFrame.maxY - panelSize.height - margin
      )
    case .topRight:
      NSPoint(
        x: visibleFrame.maxX - panelSize.width - margin,
        y: visibleFrame.maxY - panelSize.height - margin
      )
    case .bottomLeft:
      NSPoint(
        x: visibleFrame.minX + margin,
        y: visibleFrame.minY + margin
      )
    case .bottomRight:
      NSPoint(
        x: visibleFrame.maxX - panelSize.width - margin,
        y: visibleFrame.minY + margin
      )
    case .lastPosition:
      lastOrigin ?? NSPoint(
        x: visibleFrame.midX - panelSize.width / 2,
        y: visibleFrame.midY - panelSize.height / 2
      )
    }

    return clamped(rawOrigin, panelSize: panelSize, visibleFrame: visibleFrame)
  }

  static func clamped(_ origin: NSPoint, panelSize: NSSize, visibleFrame: NSRect) -> NSPoint {
    NSPoint(
      x: min(max(origin.x, visibleFrame.minX + margin), visibleFrame.maxX - panelSize.width - margin),
      y: min(max(origin.y, visibleFrame.minY + margin), visibleFrame.maxY - panelSize.height - margin)
    )
  }
}
