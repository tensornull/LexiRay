// Scenario: selecting text in TextEdit and pressing the translate hotkey opens
// the floating panel with the selection loaded. Exercises the real
// Accessibility selection-reading path end to end.
let textFile = "\(workDir)/lexiray-ui-selection.txt"
try? "\(selectionSmokeText)\n中文划词翻译测试。\n".write(
  toFile: textFile,
  atomically: true,
  encoding: .utf8
)

ensureAppRunning()
let textEditWasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").isEmpty

NSWorkspace.shared.open(
  [URL(fileURLWithPath: textFile)],
  withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
  configuration: NSWorkspace.OpenConfiguration()
) { _, error in
  if let error {
    fail("failed to open TextEdit: \(error.localizedDescription)")
  }
}

RunLoop.current.run(until: Date().addingTimeInterval(1))
activate(bundleIdentifier: "com.apple.TextEdit")
RunLoop.current.run(until: Date().addingTimeInterval(0.5))
guardAgainstShieldedSession()

require(
  waitFor("TextEdit smoke document", timeout: 10, { !windows(owner: "TextEdit").isEmpty }),
  "TextEdit did not open the smoke document"
)

let textWindow = windows(owner: "TextEdit", name: "lexiray-ui-selection.txt").first ?? windows(owner: "TextEdit")[0]
click(CGPoint(x: textWindow.midX, y: textWindow.midY))
RunLoop.current.run(until: Date().addingTimeInterval(0.2))
press(0, flags: .maskCommand)
RunLoop.current.run(until: Date().addingTimeInterval(0.2))

let hotKey = loadTranslateHotKey()
press(hotKey.keyCode, flags: hotKey.flags)
require(
  waitFor("floating panel after selection hotkey", timeout: 20, { !panelWindows().isEmpty }),
  "panel did not appear after selecting TextEdit text"
)

let measuredHeight = panelAXSizes().first?.height ?? panelWindows()[0].height
require(measuredHeight <= 560, "short floating panel is too tall: \(measuredHeight)")

require(
  waitFor("selection loaded into source editor", { floatingSourceText().contains(selectionSmokeText) }),
  "selected text did not reach the source editor"
)
snapPanel("selection-translate")

closePanel()

// Leave no leaked windows behind: a stale TextEdit document breaks later
// scenarios and runs. Only quit TextEdit if this scenario started it.
if !textEditWasRunning {
  NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit")
    .forEach { _ = $0.terminate() }
}

pass()
