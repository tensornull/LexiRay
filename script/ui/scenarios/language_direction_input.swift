// Scenario: language menus apply and persist an Always direction for actual
// typed input, then swap and clear it without losing the input.
let languageProvidersJSON = """
{
  "version": 2,
  "preferredProvider": "mock",
  "providerOrder": ["mock"],
  "providers": {
    "mock": {
      "providerID": "mock",
      "displayName": "Language Mock",
      "baseURL": "",
      "model": "",
      "isEnabled": true,
      "apiKey": ""
    }
  }
}
"""

func selectLanguageMode(_ mode: String, pickerIdentifier: String) {
  require(
    selectAndVerifyLexiRayMenuMode(title: mode, pickerIdentifier: pickerIdentifier),
    "\(mode) mode was not selected in \(pickerIdentifier)"
  )
}

func selectLanguage(_ language: String, pickerIdentifier: String) {
  require(
    selectLexiRayMenuItem(title: language, pickerIdentifier: pickerIdentifier),
    "\(language) was not reachable in \(pickerIdentifier)"
  )
}

try? FileManager.default.createDirectory(at: lexirayHomeURL, withIntermediateDirectories: true)
try languageProvidersJSON.write(to: providersFileURL, atomically: true, encoding: .utf8)
restartWorkspaceApp()
resetToBaseline()

openBlankComposer()

let sourceText = "こんにちは LexiRay"
require(focusAndReplaceSourceText(sourceText), "source editor did not accept language scenario input")
require(
  waitFor("language scenario input") { floatingSourceText() == sourceText },
  "language scenario input was not reflected in the editor"
)

selectLanguageMode("Always", pickerIdentifier: "SourceLanguagePicker")
selectLanguage("Japanese", pickerIdentifier: "SourceLanguagePicker")
require(
  waitFor("persist Japanese source selection") {
    acceptanceDefaultString("pinnedSourceLanguage") == "ja"
  },
  "Japanese source selection was not persisted in the isolated acceptance suite"
)
require(
  waitFor("Japanese source selection") {
    axElement(identifier: "SourceLanguagePicker").map { axVisibleText($0).contains("Japanese") } == true
  },
  "source picker did not show Japanese"
)

RunLoop.current.run(until: Date().addingTimeInterval(0.5))
selectLanguageMode("Always", pickerIdentifier: "TargetLanguagePicker")
selectLanguage("English", pickerIdentifier: "TargetLanguagePicker")
require(
  waitFor("persist English target selection") {
    acceptanceDefaultString("pinnedTargetLanguage") == "en"
  },
  "English target selection was not persisted in the isolated acceptance suite"
)
require(
  waitFor("English target selection") {
    axElement(identifier: "TargetLanguagePicker").map { axVisibleText($0).contains("English") } == true
  },
  "target picker did not show English"
)
require(
  waitFor("Japanese to English request", timeout: 8) { lexirayVisibleTextContains("Direction: ja -> en") },
  "translation request did not use the selected Japanese to English direction"
)
snapPanel("language-japanese-to-english")

closePanel()
restartWorkspaceApp()
resetToBaseline()
openBlankComposer()
require(
  axElement(identifier: "SourceLanguagePicker").map { axVisibleText($0).contains("Japanese") } == true,
  "Always source language did not persist after restart"
)
require(
  axElement(identifier: "TargetLanguagePicker").map { axVisibleText($0).contains("English") } == true,
  "Always target language did not persist after restart"
)

let persistedSourceText = "LexiRay Always language restart check"
require(focusAndReplaceSourceText(persistedSourceText), "persisted language input was not accepted")
require(pressLexiRayElement(identifier: "FloatingPanelTranslate"), "persisted language translate control was not reachable")
require(
  waitFor("persisted Japanese to English request", timeout: 8) {
    lexirayVisibleTextContains("Direction: ja -> en")
  },
  "Always language direction was not used after restart"
)
snapPanel("language-always-after-restart")

require(pressLexiRayElement(identifier: "FloatingPanelSwapDirection"), "direction swap was not reachable")
require(
  waitFor("swapped source language") {
    axElement(identifier: "SourceLanguagePicker").map { axVisibleText($0).contains("English") } == true
  },
  "source picker did not change to English after swap"
)
require(
  axElement(identifier: "TargetLanguagePicker").map { axVisibleText($0).contains("Simplified Chinese") } == true,
  "target picker did not change to the configured opposite language after swap"
)
require(floatingSourceText() == persistedSourceText, "direction changes discarded actual source input")
require(
  waitFor("English to Simplified Chinese request", timeout: 8) {
    lexirayVisibleTextContains("Direction: en -> zh-Hans")
  },
  "swapped translation request did not use English to Simplified Chinese"
)
snapPanel("language-english-to-simplified-chinese")

selectLanguage("Auto", pickerIdentifier: "SourceLanguagePicker")
selectLanguage("Auto", pickerIdentifier: "TargetLanguagePicker")
require(
  waitFor("Always language cleanup") {
    let source = axElement(identifier: "SourceLanguagePicker").map(axVisibleText) ?? ""
    let target = axElement(identifier: "TargetLanguagePicker").map(axVisibleText) ?? ""
    return !source.contains("Japanese") && !target.contains("English")
      && acceptanceDefaultString("pinnedSourceLanguage") == nil
      && acceptanceDefaultString("pinnedTargetLanguage") == nil
  },
  "Always language settings were not cleared from the isolated acceptance suite"
)

closePanel()
restoreFixtureStateAndRestart()
pass()
