// Scenario: an unpinned panel hides on outside click; a pinned panel survives
// outside clicks and closes only via the close button.
openBlankComposer()

let unpinnedPanel = panelWindows()[0]
click(CGPoint(x: max(30, unpinnedPanel.minX - 120), y: max(30, unpinnedPanel.minY - 120)))
require(
  waitFor("unpinned panel hides after outside click", { panelWindows().isEmpty }),
  "unpinned panel did not hide after outside click"
)

openBlankComposer()
require(pressLexiRayButton(description: "Pin"), "pin button was not reachable")
snapPanel("panel-pinned")

let pinnedPanel = panelWindows()[0]
click(CGPoint(x: max(30, pinnedPanel.minX - 120), y: max(30, pinnedPanel.minY - 120)))
require(
  waitFor("pinned panel survives outside click", { !panelWindows().isEmpty }),
  "pinned panel hid after outside click"
)

closePanel()
pass()
