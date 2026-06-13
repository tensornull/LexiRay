// Scenario: app launch shows the main window; closing it keeps the app alive.
openMainWindow()
snapMain("dashboard")

require(closeLexiRayMainWindow(), "main window close control was not reachable")
require(
  waitFor("main window closes", { lexirayMainWindows().isEmpty }),
  "main window did not close"
)
require(
  workspaceInstance() != nil,
  "LexiRay quit after closing the main window; menu bar app must keep running"
)

pass()
