// Scenario: a controlled mock streaming provider grows the floating panel from
// a short partial to a longer partial and final result without overflowing text.
let streamingProvidersJSON = """
{
  "version": 2,
  "preferredProvider": "mock",
  "providerOrder": [
    "mock"
  ],
  "providers": {
    "mock": {
      "providerID": "mock",
      "displayName": "Streaming Mock",
      "baseURL": "",
      "model": "",
      "isEnabled": true,
      "apiKey": ""
    }
  }
}
"""

try? FileManager.default.createDirectory(at: lexirayHomeURL, withIntermediateDirectories: true)
try streamingProvidersJSON.write(to: providersFileURL, atomically: true, encoding: .utf8)
restartWorkspaceApp()
resetToBaseline()

openBlankComposer()
let idleSize = floatingPanelSize() ?? .zero
require(idleSize.height <= 260, "blank streaming start panel is too tall: \(idleSize.height)")

let streamingText = "LexiRay streaming panel growth text"
require(focusAndReplaceSourceText(streamingText), "source editor did not accept streaming fixture text")
require(
  waitFor("streaming fixture source text", { floatingSourceText().contains(streamingText) }),
  "streaming fixture text did not reach the source editor"
)

press(36, flags: .maskCommand)
require(
  waitFor("short streaming partial", timeout: 8, {
    lexirayVisibleTextContains("LexiRay streaming partial.")
  }),
  "short streaming partial did not render"
)
let shortSize = floatingPanelSize() ?? .zero
require(shortSize.height >= idleSize.height, "short streaming panel shrank unexpectedly")
snapPanel("streaming-growth-short")

require(
  waitFor("long streaming partial", timeout: 8, {
    lexirayVisibleTextContains("逐步变长的 UI 场景文本")
  }),
  "long streaming partial did not render"
)
require(
  waitFor("long streaming panel grows", timeout: 3, {
    guard let size = floatingPanelSize() else {
      return false
    }
    return size.height >= shortSize.height + 18 || size.width >= shortSize.width + 18
  }),
  "long streaming partial did not grow the panel: short=\(shortSize), current=\(floatingPanelSize() ?? .zero)"
)
let longSize = floatingPanelSize() ?? .zero
let longOverflow = visibleStaticTextOverflowingFloatingPanelRightBoundary()
require(longOverflow.isEmpty, "long streaming text overflowed: \(longOverflow.joined(separator: "; "))")
snapPanel("streaming-growth-long")

require(
  waitFor("streaming completion", timeout: 8, {
    lexirayVisibleTextContains("最终结果继续保持可读")
  }),
  "streaming final result did not render"
)
let completeSize = floatingPanelSize() ?? .zero
require(
  completeSize.height >= longSize.height - 8,
  "complete streaming panel collapsed too much: long=\(longSize), complete=\(completeSize)"
)
let completeOverflow = visibleStaticTextOverflowingFloatingPanelRightBoundary()
require(completeOverflow.isEmpty, "complete streaming text overflowed: \(completeOverflow.joined(separator: "; "))")
snapPanel("streaming-growth-complete")

closePanel()
pass()
