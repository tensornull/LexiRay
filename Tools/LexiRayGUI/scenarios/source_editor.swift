// Scenario: empty/focused/IME-marked/committed/cleared editor states keep the
// placeholder and source binding coherent.
openMainWindow()
openBlankComposer()

func mainManualSourceText() -> String? {
  guard let editor = axElement(identifier: "MainManualSourceEditor") else {
    return nil
  }
  return axString(editor, kAXValueAttribute)
}

guard let initialMainSourceText = mainManualSourceText() else {
  fail("main source editor was unavailable for cross-window IME isolation")
}

require(floatingSourceText().isEmpty, "source editor was not initially empty")
require(
  floatingPanelVisibleTextContains("Type or"),
  "empty source editor did not expose its placeholder"
)
snapPanel("source-editor-empty")

require(focusFloatingSourceEditor(), "source editor did not accept focus")
snapPanel("source-editor-focused")

setAcceptanceMarkedText("ni")
require(
  waitFor("IME marked text renders") { floatingSourceText().contains("ni") },
  "source editor did not render marked text"
)
require(
  mainManualSourceText() == initialMainSourceText,
  "IME marked text leaked from the floating editor into the main window"
)
require(
  !floatingPanelVisibleTextContains("Type or"),
  "placeholder remained visible over IME marked text"
)
snapPanel("source-editor-ime-marked")

commitAcceptanceMarkedText("你")
require(
  waitFor("IME text commits") { floatingSourceText().contains("你") && !floatingSourceText().contains("ni") },
  "source editor did not replace marked text with committed text"
)
require(
  mainManualSourceText() == initialMainSourceText,
  "committed IME text leaked from the floating editor into the main window"
)
snapPanel("source-editor-ime-committed")

let editedText = "LexiRay edited smoke text."
require(focusAndReplaceSourceText(editedText), "source editor did not accept focus")
require(
  waitFor("source editor accepts text") { floatingSourceText().contains(editedText) },
  "source editor did not accept edited text"
)
snapPanel("source-editor-typed")

require(pressLexiRayButton(description: "Clear Source"), "clear source button was not reachable")
require(
  waitFor("source editor clears") { floatingSourceText().isEmpty },
  "source editor did not clear"
)
require(
  !floatingPanelVisibleTextContains("No Translation"),
  "blank source shows a no-translation warning"
)
snapPanel("source-editor-cleared")

closePanel()

setAcceptanceMarkedText("hidden")
commitAcceptanceMarkedText("隐藏")
activateWorkspaceApp()
let hotKey = loadTranslateHotKey()
press(hotKey.keyCode, flags: hotKey.flags)
require(
  waitFor("floating composer reopens") { !panelWindows().isEmpty && floatingSourceEditor() != nil },
  "floating composer did not reopen after hidden IME check"
)
require(
  floatingSourceText().isEmpty,
  "hidden floating editor accepted an acceptance IME command"
)
snapPanel("source-editor-hidden-ime-ignored")
closePanel()
pass()
