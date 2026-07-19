// Scenario: rounded/translucent panel evidence across key/non-key, pinned,
// resized, light, and dark states. Pixel samples accompany every screenshot.
func captureVisualState(_ name: String) {
  snapPanel(name)
  recordPanelPixelEvidence(name)
}

restartWorkspaceApp(extraArguments: ["--lexiray-acceptance-appearance", "light"])
resetToBaseline()
openBlankComposer()
captureVisualState("panel-light-key")

if let captureError = snapPanelWithOpenLanguageMenu(
  "panel-light-menu-open",
  containing: "Always",
  pickerIdentifier: "TargetLanguagePicker",
  timeout: 3
) {
  fail(captureError)
}

recordPanelMenuOpenBorderEvidence(
  "panel-light-menu-open",
  referenceImageName: "panel-light-key"
)
require(dismissLexiRayLanguageMenu(timeout: 2), "target language menu did not dismiss")

require(pressLexiRayButton(description: "Pin"), "pin button was not reachable in light appearance")
captureVisualState("panel-light-pinned-key")

activate(bundleIdentifier: "com.apple.finder")
require(
  waitFor("light panel becomes non-key") { workspaceInstance()?.isActive == false && !panelWindows().isEmpty },
  "pinned light panel did not survive non-key transition"
)
captureVisualState("panel-light-pinned-non-key")

activateWorkspaceApp()
let lightSize = floatingPanelSize() ?? .zero
require(
  setFloatingPanelSize(CGSize(width: min(lightSize.width + 140, 940), height: min(lightSize.height + 120, 640))),
  "light panel did not accept resize"
)
captureVisualState("panel-light-pinned-resized")
closePanel()

restartWorkspaceApp(extraArguments: ["--lexiray-acceptance-appearance", "dark"])
resetToBaseline()
openBlankComposer()
captureVisualState("panel-dark-key")
require(pressLexiRayButton(description: "Pin"), "pin button was not reachable in dark appearance")
activate(bundleIdentifier: "com.apple.finder")
require(
  waitFor("dark panel becomes non-key") { workspaceInstance()?.isActive == false && !panelWindows().isEmpty },
  "pinned dark panel did not survive non-key transition"
)
captureVisualState("panel-dark-pinned-non-key")

activateWorkspaceApp()
closePanel()
pass()
