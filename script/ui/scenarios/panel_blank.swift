// Scenario: translate hotkey with no selection opens a blank composer with a
// compact provider standby preview; close button dismisses it.
openBlankComposer()

require(
  !lexirayVisibleTextContains("No Translation"),
  "empty selection shows a no-translation warning"
)
require(
  !lexirayVisibleTextContains("No source text yet."),
  "blank panel still shows the old empty result card"
)
require(
  lexirayVisibleTextContains("System Dictionary"),
  "blank panel did not show a provider standby row"
)
require(
  lexirayVisibleTextContains("Stand by"),
  "blank panel did not show provider standby state"
)

let measuredHeight = panelAXSizes().first?.height ?? panelWindows()[0].height
require(measuredHeight <= 500, "blank floating panel is too tall: \(measuredHeight)")

snapPanel("panel-blank")
closePanel()
pass()
