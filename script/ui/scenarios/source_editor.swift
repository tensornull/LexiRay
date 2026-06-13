// Scenario: source editor accepts typed text, the clear button empties it, and
// a blank source never shows a no-translation warning.
openBlankComposer()

let editedText = "LexiRay edited smoke text."
require(focusAndReplaceSourceText(editedText), "source editor did not accept focus")
require(
  waitFor("source editor accepts text", { floatingSourceText().contains(editedText) }),
  "source editor did not accept edited text"
)
snapPanel("source-editor-filled")

require(pressLexiRayButton(description: "Clear Source"), "clear source button was not reachable")
require(
  waitFor("source editor clears", { floatingSourceText().isEmpty }),
  "source editor did not clear"
)
require(
  !lexirayVisibleTextContains("No Translation"),
  "blank source shows a no-translation warning"
)
snapPanel("source-editor-cleared")

closePanel()
pass()
