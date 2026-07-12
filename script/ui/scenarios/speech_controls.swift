// Scenario: source speech is unavailable when empty, toggles play/stop with
// text, and remains mutually exclusive with translated-result speech.
let speechProvidersJSON = """
{
  "version": 2,
  "preferredProvider": "mock",
  "providerOrder": ["mock"],
  "providers": {
    "mock": {
      "providerID": "mock",
      "displayName": "Speech Mock",
      "baseURL": "",
      "model": "",
      "isEnabled": true,
      "apiKey": ""
    }
  }
}
"""

try? FileManager.default.createDirectory(at: lexirayHomeURL, withIntermediateDirectories: true)
try speechProvidersJSON.write(to: providersFileURL, atomically: true, encoding: .utf8)
restartWorkspaceApp()
resetToBaseline()

openBlankComposer()
require(pressLexiRayButton(description: "Pin"), "speech scenario could not pin its panel")
require(axElement(identifier: "FloatingPanelSourceSpeech") == nil, "empty source exposed an enabled speech control")

let longSource = String(repeating: "LexiRay source speech acceptance. ", count: 20)
require(focusAndReplaceSourceText(longSource), "speech scenario source input was not accepted")
require(
  waitFor("source speech control") { axElement(identifier: "FloatingPanelSourceSpeech") != nil },
  "source speech control did not appear"
)
require(pressLexiRayElement(identifier: "FloatingPanelSourceSpeech"), "source speech control was not reachable")
require(
  waitFor("source speech starts") {
    axElement(identifier: "FloatingPanelSourceSpeech").map { axVisibleText($0).contains("Stop") } == true
  },
  "source speech did not enter its stop state"
)
snapPanel("speech-source-playing")

require(pressLexiRayElement(identifier: "FloatingPanelSourceSpeech"), "source speech stop control was not reachable")
require(
  waitFor("source speech stops") {
    axElement(identifier: "FloatingPanelSourceSpeech").map { !axVisibleText($0).contains("Stop") } == true
  },
  "source speech control did not return to its play state"
)
snapPanel("speech-source-stopped")

require(pressLexiRayElement(identifier: "FloatingPanelSourceSpeech"), "source speech replay control was not reachable")
require(
  waitFor("source speech restarts") {
    axElement(identifier: "FloatingPanelSourceSpeech").map { axVisibleText($0).contains("Stop") } == true
  },
  "source speech did not restart before mutual-exclusion verification"
)

require(pressLexiRayElement(identifier: "FloatingPanelTranslate"), "translate control was not reachable")
require(
  waitFor("mock speech translation", timeout: 8) { lexirayVisibleTextContains("LexiRay mock translation:") },
  "mock translation did not render"
)
require(
  axElement(identifier: "FloatingPanelSourceSpeech").map { !axVisibleText($0).contains("Stop") } == true,
  "starting translation did not stop source speech"
)

require(pressLexiRayElement(identifier: "TranslationSpeech-mock"), "translation speech control was not reachable")
require(
  waitFor("translation speech starts") {
    axElement(identifier: "TranslationSpeech-mock").map { axVisibleText($0).contains("Stop") } == true
  },
  "translation speech did not enter its stop state"
)
snapPanel("speech-translation-playing")

require(pressLexiRayElement(identifier: "FloatingPanelSourceSpeech"), "source speech restart was not reachable")
require(
  waitFor("source speech replaces translation speech") {
    let sourceIsStopping = axElement(identifier: "FloatingPanelSourceSpeech")
      .map { axVisibleText($0).contains("Stop") } == true
    let resultIsStopped = axElement(identifier: "TranslationSpeech-mock")
      .map { !axVisibleText($0).contains("Stop") } == true
    return sourceIsStopping && resultIsStopped
  },
  "source and translation speech were not mutually exclusive"
)
snapPanel("speech-source-replaced-result")

closePanel()
restoreFixtureStateAndRestart()
pass()
