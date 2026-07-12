// Scenario: OCR overlays one panel per physical display. Single-display hosts
// emit an explicit uncovered record instead of silently claiming coverage.
let screens = NSScreen.screens
let coverageURL = URL(fileURLWithPath: shotDir).appendingPathComponent("ocr-multi-display-coverage.txt")

guard screens.count >= 2 else {
  let note = "UNCOVERED: requires at least two displays; detected \(screens.count)"
  try note.write(to: coverageURL, atomically: true, encoding: .utf8)
  print("UI_UNCOVERED[ocr_multi_display]: \(note)")
  blocked(note)
}

ensureAppRunning()
activateWorkspaceApp()
let hotKey = loadOCRHotKey()
press(hotKey.keyCode, flags: hotKey.flags)

let primaryTop = screens.first?.frame.maxY ?? 0
let expectedOverlayFrames = screens.map { screen in
  CGRect(
    x: screen.frame.minX,
    y: primaryTop - screen.frame.maxY,
    width: screen.frame.width,
    height: screen.frame.height
  )
}

func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
  abs(lhs.minX - rhs.minX) < 4
    && abs(lhs.minY - rhs.minY) < 4
    && abs(lhs.width - rhs.width) < 4
    && abs(lhs.height - rhs.height) < 4
}

func overlayWindowInfos() -> [[String: Any]] {
  lexirayWindowInfos().filter { window in
    expectedOverlayFrames.contains { framesMatch(windowBounds(window), $0) }
  }
}

func overlaysCoverDisplaysOneToOne() -> Bool {
  let overlayFrames = overlayWindowInfos().map(windowBounds)
  return overlayFrames.count == expectedOverlayFrames.count
    && expectedOverlayFrames.allSatisfy { expected in
      overlayFrames.count(where: { framesMatch($0, expected) }) == 1
    }
}

require(
  waitFor("OCR overlays on every display", timeout: 8) { overlaysCoverDisplaysOneToOne() },
  "OCR overlays did not cover each physical display origin and size exactly once"
)

let overlayRecords = expectedOverlayFrames.enumerated().map { index, expectedFrame -> String in
  guard let overlay = overlayWindowInfos().first(where: { framesMatch(windowBounds($0), expectedFrame) }),
        let identifier = windowID(overlay),
        let ownerPID = windowOwnerPID(overlay)
  else {
    fail("OCR overlay evidence window was missing for display \(index + 1)")
  }
  return "display[\(index + 1)]=window_id:\(identifier),owner_pid:\(ownerPID),bounds:\(NSStringFromRect(windowBounds(overlay)))"
}

let screenFrames = screens.map { NSStringFromRect($0.frame) }.joined(separator: "\n")
let overlayFrames = overlayWindowInfos().map { NSStringFromRect(windowBounds($0)) }.joined(separator: "\n")
let note = """
COVERED: \(screens.count) displays
screens:
\(screenFrames)
overlays:
\(overlayFrames)
window identities:
\(overlayRecords.joined(separator: "\n"))
"""
try note.write(to: coverageURL, atomically: true, encoding: .utf8)

press(53)
require(
  waitFor("OCR overlays close") { overlayWindowInfos().isEmpty },
  "OCR overlays did not close after Escape"
)
pass()
