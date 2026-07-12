// Scenario: selecting text in TextEdit and pressing the translate hotkey opens
// the floating panel with the selection loaded. Exercises the real
// Accessibility selection-reading path end to end.
let textFile = "\(workDir)/lexiray-ui-selection.txt"
try? "\(selectionSmokeText)\n中文划词翻译测试。\n".write(
  toFile: textFile,
  atomically: true,
  encoding: .utf8
)

terminateWorkspaceApp()

let textEditBundleIdentifier = "com.apple.TextEdit"
let preexistingTextEditProcessIdentifiers = Set(
  NSRunningApplication.runningApplications(withBundleIdentifier: textEditBundleIdentifier)
    .map(\.processIdentifier)
)
let textEditConfiguration = NSWorkspace.OpenConfiguration()
textEditConfiguration.addsToRecentItems = false
textEditConfiguration.createsNewApplicationInstance = true
var fixtureApplication: NSRunningApplication?
var fixtureLaunchCompleted = false
NSWorkspace.shared.open(
  [URL(fileURLWithPath: textFile)],
  withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
  configuration: textEditConfiguration
) { application, error in
  fixtureApplication = application
  fixtureLaunchCompleted = true
  if let error {
    fail("failed to open TextEdit: \(error.localizedDescription)")
  }
}

require(
  waitFor("TextEdit fixture launch") { fixtureLaunchCompleted && fixtureApplication != nil },
  "TextEdit fixture instance did not launch"
)
guard let fixtureApplication else {
  fail("TextEdit fixture launch returned no application")
}

let fixturePID = fixtureApplication.processIdentifier
guard !preexistingTextEditProcessIdentifiers.contains(fixturePID) else {
  blocked("TextEdit did not create an isolated fixture process")
}

registerScenarioCleanup {
  _ = closeApplicationWindow(processIdentifier: fixturePID, titleContains: "lexiray-ui-selection.txt")
  _ = fixtureApplication.terminate()
}

restartWorkspaceApp(
  extraArguments: ["--lexiray-acceptance-selection-pid", "\(fixturePID)"]
)
_ = fixtureApplication.activate(options: [.activateAllWindows])
guardAgainstShieldedSession()

var textWindow: CGRect?
require(
  waitFor("TextEdit smoke document", timeout: 10) {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == fixturePID else {
      return false
    }
    textWindow = applicationWindowFrame(
      processIdentifier: fixturePID,
      titleContains: "lexiray-ui-selection.txt"
    )
    return textWindow != nil
  },
  "TextEdit did not open the smoke document"
)

guard let textWindow else {
  fail("TextEdit fixture window capture unexpectedly disappeared")
}

click(CGPoint(x: textWindow.midX, y: textWindow.midY))
RunLoop.current.run(until: Date().addingTimeInterval(0.2))
press(0, flags: .maskCommand)
RunLoop.current.run(until: Date().addingTimeInterval(0.2))

let hotKey = loadTranslateHotKey()
press(hotKey.keyCode, flags: hotKey.flags)
require(
  waitFor("floating panel after selection hotkey", timeout: 20) { !panelWindows().isEmpty },
  "panel did not appear after selecting TextEdit text"
)

let measuredHeight = panelAXSizes().first?.height ?? panelWindows()[0].height
require(measuredHeight <= 560, "short floating panel is too tall: \(measuredHeight)")

require(
  waitFor("selection loaded into source editor") { floatingSourceText().contains(selectionSmokeText) },
  "selected text did not reach the source editor"
)
snapPanel("selection-translate")

closePanel()

// Close only the synthetic document. Never quit or mutate pre-existing user
// TextEdit windows.
require(
  closeApplicationWindow(processIdentifier: fixturePID, titleContains: "lexiray-ui-selection.txt"),
  "could not close the synthetic TextEdit smoke document"
)
pass()
