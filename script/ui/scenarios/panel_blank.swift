// Scenario: translate hotkey with no selection opens a blank composer without
// warnings; the panel height stays compact; close button dismisses it.
openBlankComposer()

require(
  !lexirayVisibleTextContains("No Translation"),
  "empty selection shows a no-translation warning"
)

let measuredHeight = panelAXSizes().first?.height ?? panelWindows()[0].height
require(measuredHeight <= 560, "short floating panel is too tall: \(measuredHeight)")

snapPanel("panel-blank")
closePanel()
pass()
