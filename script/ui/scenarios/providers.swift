// Scenario: providers section renders with aligned header controls and no
// leftover language-direction pill.
openMainWindow()

guard let providersFrame = axElement(identifier: "SidebarProviders").flatMap(axFrame) else {
  fail("providers sidebar item was not reachable")
}
click(CGPoint(x: providersFrame.minX + 90, y: providersFrame.midY))
RunLoop.current.run(until: Date().addingTimeInterval(0.2))
require(
  waitFor("provider header and add button", timeout: 5, {
    axElement(identifier: "ProviderHeaderTitle") != nil && axElement(identifier: "ProviderAddMenuButton") != nil
  }),
  "provider header controls were not reachable"
)

if let headerFrame = axElement(identifier: "ProviderHeaderTitle").flatMap(axFrame),
   let addFrame = axElement(identifier: "ProviderAddMenuButton").flatMap(axFrame),
   abs(headerFrame.midY - addFrame.midY) > 14 {
  fail("add provider button is not aligned with provider title")
}

require(
  !lexirayVisibleTextContains("<->"),
  "provider page still shows a language direction pill"
)

snapMain("providers")
pass()
