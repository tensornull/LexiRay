// Scenario: arrow keys browse translation history from the blank composer and
// return to the blank state. Requires the seeded history fixture.
openBlankComposer()
require(focusFloatingSourceEditor(), "source editor did not accept focus before history navigation")

press(126)
require(
  waitFor("up arrow restores history") {
    let text = floatingSourceText()
    return text.contains(seededHistoryText)
      || text.contains(richWrapHistoryText)
      || text.contains(selectionSmokeText)
  },
  "up arrow did not restore translation history"
)

for _ in 0 ..< 3 where !floatingSourceText().contains(seededHistoryText) {
  press(126)
}

if !floatingSourceText().contains(seededHistoryText) {
  require(
    waitFor("up arrow reaches seeded history") { floatingSourceText().contains(seededHistoryText) },
    "up arrow did not continue to seeded translation history"
  )
}

snapPanel("history-restored")

var returnedToBlankComposer = false
for _ in 0 ..< 3 {
  press(125)
  let deadline = Date().addingTimeInterval(2)
  while Date() < deadline {
    if floatingSourceText().isEmpty {
      returnedToBlankComposer = true
      break
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
  }
  if returnedToBlankComposer {
    break
  }
}

require(returnedToBlankComposer, "down arrow did not leave history browsing")
snapPanel("history-back-to-blank")

closePanel()
pass()
