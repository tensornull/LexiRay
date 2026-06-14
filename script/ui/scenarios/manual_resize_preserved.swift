// Scenario: a user-resized floating panel keeps that size while short source
// edits and short results trigger automatic layout refreshes.
let manualResizeProvidersJSON = """
{
  "version": 2,
  "preferredProvider": "mock",
  "providerOrder": [
    "mock"
  ],
  "providers": {
    "mock": {
      "providerID": "mock",
      "displayName": "Manual Resize Mock",
      "baseURL": "",
      "model": "",
      "isEnabled": true,
      "apiKey": ""
    }
  }
}
"""

try? FileManager.default.createDirectory(at: lexirayHomeURL, withIntermediateDirectories: true)
try manualResizeProvidersJSON.write(to: providersFileURL, atomically: true, encoding: .utf8)
restartWorkspaceApp()
resetToBaseline()

openBlankComposer()
let initialSize = floatingPanelSize() ?? .zero
let requestedSize = CGSize(
  width: min(max(initialSize.width + 180, 860), 940),
  height: min(max(initialSize.height + 180, 560), 640)
)

require(setFloatingPanelSize(requestedSize), "floating panel did not accept manual AX resize")
guard let manualSize = floatingPanelSize() else {
  fail("floating panel disappeared after manual resize")
}
require(
  manualSize.width >= requestedSize.width - 16 && manualSize.height >= requestedSize.height - 16,
  "manual resize did not take effect: requested=\(requestedSize), actual=\(manualSize)"
)
snapPanel("manual-resize-empty")

let editedText = "hello"
require(focusAndReplaceSourceText(editedText), "source editor did not accept manual resize test text")
require(
  waitFor("manual resize source text", { floatingSourceText().contains(editedText) }),
  "manual resize text did not reach the source editor"
)
let typedSize = floatingPanelSize() ?? .zero
require(
  typedSize.width >= manualSize.width - 8 && typedSize.height >= manualSize.height - 8,
  "typing collapsed the manually resized panel: manual=\(manualSize), typed=\(typedSize)"
)
snapPanel("manual-resize-typed")

press(36, flags: .maskCommand)
require(
  waitFor("manual resize mock translation", timeout: 8, {
    lexirayVisibleTextContains("LexiRay mock translation:")
  }),
  "manual resize mock translation did not render"
)
let translatedSize = floatingPanelSize() ?? .zero
require(
  translatedSize.width >= manualSize.width - 8 && translatedSize.height >= manualSize.height - 8,
  "short translation collapsed the manually resized panel: manual=\(manualSize), translated=\(translatedSize)"
)
snapPanel("manual-resize-translated")

closePanel()
restoreFixtureStateAndRestart()
pass()
