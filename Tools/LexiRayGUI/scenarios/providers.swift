// Scenario: provider editing uses real drag events, preserves order across a
// restart, adds a blank endpoint, and removes only the selected instance.
let providerFixture = """
{
  "version": 2,
  "preferredProvider": "systemDictionary",
  "providerOrder": ["openAIResponses", "systemDictionary", "anthropicMessages"],
  "providers": {
    "openAIResponses": {
      "providerID": "openAIResponses", "displayName": "", "baseURL": "",
      "model": "", "isEnabled": false, "apiKey": ""
    },
    "systemDictionary": {
      "providerID": "systemDictionary", "displayName": "", "baseURL": "",
      "model": "", "isEnabled": true, "apiKey": ""
    },
    "anthropicMessages": {
      "providerID": "anthropicMessages", "displayName": "", "baseURL": "",
      "model": "", "isEnabled": false, "apiKey": ""
    }
  }
}
"""

func savedProviderSettings() -> [String: Any] {
  guard let data = try? Data(contentsOf: providersFileURL),
        let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  else {
    fail("could not read isolated provider settings")
  }
  return settings
}

func savedProviderOrder() -> [String] {
  savedProviderSettings()["providerOrder"] as? [String] ?? []
}

// AX reports logical frames on a scaled secondary display while CGEvent uses
// the window-server coordinate space. Convert through the owning window rather
// than sending a distant tile's unscaled AX point to another app or display.
func providerScreenPoint(_ point: CGPoint) -> CGPoint {
  guard let accessibilityWindow = lexirayMainAXWindow().flatMap(axFrame),
        let screenWindow = lexirayMainWindowInfo().map(windowBounds),
        accessibilityWindow.width > 0, accessibilityWindow.height > 0
  else {
    fail("could not resolve provider window coordinate spaces")
  }
  return CGPoint(
    x: screenWindow.minX + (point.x - accessibilityWindow.minX) * screenWindow.width / accessibilityWindow.width,
    y: screenWindow.minY + (point.y - accessibilityWindow.minY) * screenWindow.height / accessibilityWindow.height
  )
}

func positionProvidersOnPrimaryDisplay() {
  guard let window = lexirayMainAXWindow() else {
    blocked("provider window was not available for primary-display positioning")
  }
  let display = CGDisplayBounds(CGMainDisplayID())
  var origin = CGPoint(x: display.minX + 100, y: display.minY + 100)
  let desiredSize = CGSize(width: min(1050, display.width - 200), height: min(700, display.height - 200))
  guard let position = AXValueCreate(.cgPoint, &origin),
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position) == .success
  else {
    blocked("provider window could not be moved to the primary display")
  }

  // Resolve the current AX/CG scale after moving displays, then size the window
  // without assuming that a secondary-display scale carries over to primary.
  RunLoop.current.run(until: Date().addingTimeInterval(0.25))
  for _ in 0 ..< 3 {
    guard let accessibilityFrame = axFrame(window),
          let screenFrame = lexirayMainWindowInfo().map(windowBounds),
          screenFrame.width > 0, screenFrame.height > 0
    else {
      blocked("provider window geometry was unavailable after positioning")
    }
    var size = CGSize(
      width: desiredSize.width * accessibilityFrame.width / screenFrame.width,
      height: desiredSize.height * accessibilityFrame.height / screenFrame.height
    )
    guard let value = AXValueCreate(.cgSize, &size),
          AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) == .success
    else {
      blocked("provider window could not be resized on the primary display")
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
  }
  guard waitFor("primary-display provider window", {
    guard let frame = lexirayMainWindowInfo().map(windowBounds) else { return false }
    return display.contains(frame) && abs(frame.minX - origin.x) < 5 && abs(frame.minY - origin.y) < 5
  }) else {
    blocked("provider window did not settle fully inside the primary display")
  }
  activateWorkspaceApp()
  guard waitFor("positioned provider window foreground", {
    NSWorkspace.shared.frontmostApplication?.processIdentifier == workspaceProcessIdentifier
  }) else {
    blocked("provider window did not retain foreground ownership after positioning")
  }
}

func openProviders() {
  openMainWindow()
  positionProvidersOnPrimaryDisplay()
  guard let providersFrame = axElement(identifier: "SidebarProviders").flatMap(axFrame) else {
    fail("providers sidebar item was not reachable")
  }
  click(providerScreenPoint(CGPoint(x: providersFrame.minX + 90, y: providersFrame.midY)))
  require(
    waitFor("provider header and add button", timeout: 5, {
      axElement(identifier: "ProviderHeaderTitle") != nil && axElement(identifier: "ProviderAddMenuButton") != nil
    }),
    "provider header controls were not reachable"
  )
}

func providerDragPoints() -> (start: CGPoint, end: CGPoint) {
  activateWorkspaceApp()
  guard waitFor("provider drag foreground owner", {
    NSWorkspace.shared.frontmostApplication?.processIdentifier == workspaceProcessIdentifier
  }) else {
    blocked("provider drag blocked because another application owns the foreground")
  }
  // Wait for the Edit/Done layout transition before resolving fresh frames.
  RunLoop.current.run(until: Date().addingTimeInterval(0.3))
  guard let source = axElement(identifier: "ProviderReorderTile-systemDictionary").flatMap(axFrame),
        let target = axElement(identifier: "ProviderReorderTile-openAIResponses").flatMap(axFrame),
        let accessibilityWindow = lexirayMainAXWindow().flatMap(axFrame),
        let screenWindow = lexirayMainWindowInfo().map(windowBounds)
  else {
    fail("provider drag targets were not reachable")
  }
  let start = providerScreenPoint(CGPoint(x: source.midX, y: source.midY))
  let end = providerScreenPoint(CGPoint(x: target.midX, y: target.midY))
  require(screenWindow.contains(start) && screenWindow.contains(end), "provider drag points are outside the owned window")
  print("UI_DRAG_GEOMETRY[providers]: AX=\(accessibilityWindow), CG=\(screenWindow), source=\(source), target=\(target), start=\(start), end=\(end)")
  return (start, end)
}

func dragProvider(from start: CGPoint, to end: CGPoint, cancel: Bool = false) {
  guard NSWorkspace.shared.frontmostApplication?.processIdentifier == workspaceProcessIdentifier else {
    blocked("provider drag lost foreground ownership before mouse down")
  }
  let source = CGEventSource(stateID: .hidSystemState)
  var previousPoint = start
  func post(_ kind: CGEventType, at point: CGPoint) {
    let event = CGEvent(mouseEventSource: source, mouseType: kind, mouseCursorPosition: point, mouseButton: .left)
    event?.flags = []
    if kind == .leftMouseDragged {
      event?.setIntegerValueField(.mouseEventDeltaX, value: Int64((point.x - previousPoint.x).rounded()))
      event?.setIntegerValueField(.mouseEventDeltaY, value: Int64((point.y - previousPoint.y).rounded()))
      event?.setDoubleValueField(.mouseEventPressure, value: 1)
    }
    event?.post(tap: .cghidEventTap)
    previousPoint = point
  }
  post(.mouseMoved, at: start)
  RunLoop.current.run(until: Date().addingTimeInterval(0.1))
  let appKitCursor = NSEvent.mouseLocation
  let display = CGDisplayBounds(CGMainDisplayID())
  let actualCursor = CGPoint(x: appKitCursor.x, y: display.maxY - appKitCursor.y)
  print("UI_DRAG_CURSOR[providers]: requested=\(start), actual=\(actualCursor), foreground=\(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1)")
  guard hypot(actualCursor.x - start.x, actualCursor.y - start.y) < 8 else {
    blocked("provider drag cursor did not reach the owned tile after mouse move")
  }
  guard NSWorkspace.shared.frontmostApplication?.processIdentifier == workspaceProcessIdentifier else {
    blocked("provider drag lost foreground ownership after mouse move")
  }
  post(.leftMouseDown, at: start)
  RunLoop.current.run(until: Date().addingTimeInterval(0.15))
  for step in 1 ... 30 {
    let fraction = CGFloat(step) / 30
    post(.leftMouseDragged, at: CGPoint(
      x: start.x + (end.x - start.x) * fraction,
      y: start.y + (end.y - start.y) * fraction
    ))
    RunLoop.current.run(until: Date().addingTimeInterval(0.025))
  }
  RunLoop.current.run(until: Date().addingTimeInterval(0.25))
  guard NSWorkspace.shared.frontmostApplication?.processIdentifier == workspaceProcessIdentifier else {
    post(.leftMouseUp, at: end)
    blocked("provider drag lost foreground ownership during synthetic input")
  }
  if cancel {
    press(CGKeyCode(kVK_Escape))
  }
  post(.leftMouseUp, at: end)
}

try? FileManager.default.createDirectory(at: lexirayHomeURL, withIntermediateDirectories: true)
try providerFixture.write(to: providersFileURL, atomically: true, encoding: .utf8)
restartWorkspaceApp()
openProviders()

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

require(pressLexiRayButton(identifier: "ProviderEditButton"), "Edit Providers was not reachable")
require(
  waitFor("provider edit tiles") {
    axElement(identifier: "ProviderReorderTile-systemDictionary") != nil
      && axElement(identifier: "ProviderRemove-systemDictionary") != nil
  },
  "edit mode did not expose reorder tiles and minus controls"
)
let canceledDrag = providerDragPoints()
dragProvider(
  from: canceledDrag.start,
  to: canceledDrag.end,
  cancel: true
)
RunLoop.current.run(until: Date().addingTimeInterval(0.3))
require(
  savedProviderOrder() == ["openAIResponses", "systemDictionary", "anthropicMessages"],
  "canceling a provider drag changed saved ordering"
)
let committedDrag = providerDragPoints()
dragProvider(
  from: committedDrag.start,
  to: committedDrag.end
)
require(
  waitFor("dragged provider order") { savedProviderOrder() == ["systemDictionary", "openAIResponses", "anthropicMessages"] },
  "native drag did not persist the new provider order"
)
snapMain("providers-edit")
require(pressLexiRayButton(identifier: "ProviderEditButton"), "Done was not reachable")

restartWorkspaceApp()
openProviders()
require(savedProviderOrder() == ["systemDictionary", "openAIResponses", "anthropicMessages"], "provider order changed after restart")
guard let addButton = axElement(identifier: "ProviderAddMenuButton"), let addFrame = axFrame(addButton) else {
  fail("Add Provider was not reachable")
}
click(providerScreenPoint(CGPoint(x: addFrame.midX, y: addFrame.midY)))
require(waitFor("Gemini add menu item") { axMenuItem(title: "Gemini GenerateContent") != nil }, "Gemini add menu item was not reachable")
guard let geminiItem = axMenuItem(title: "Gemini GenerateContent") else {
  fail("Gemini menu item disappeared")
}
require(AXUIElementPerformAction(geminiItem, kAXPressAction as CFString) == .success, "Gemini menu item did not activate")
require(waitFor("new Gemini provider") { savedProviderOrder().count == 4 }, "new provider was not persisted")
guard let newID = savedProviderOrder().last,
      let providers = savedProviderSettings()["providers"] as? [String: [String: Any]],
      let newProvider = providers[newID]
else {
  fail("added provider settings were missing")
}
require(newProvider["baseURL"] as? String == "", "new provider contained an unsolicited endpoint")
require(newProvider["model"] as? String == "", "new provider contained an unsolicited model")
require(newProvider["isEnabled"] as? Bool == false, "new provider was enabled without configuration")

require(pressLexiRayButton(identifier: "ProviderEditButton"), "Edit Providers was not reachable after adding")
require(
  waitFor("new provider minus control") { axElement(identifier: "ProviderRemove-\(newID)") != nil },
  "new provider did not expose a minus control"
)
require(pressLexiRayButton(identifier: "ProviderRemove-\(newID)"), "new provider minus control did not activate")
require(waitFor("provider removal") { savedProviderOrder().count == 3 }, "minus control did not remove the selected instance")
require(
  pressLexiRayButton(identifier: "ProviderMoveEarlier-anthropicMessages"),
  "keyboard-accessible move control did not activate"
)
require(
  waitFor("accessible provider order") { savedProviderOrder() == ["systemDictionary", "anthropicMessages", "openAIResponses"] },
  "move control did not persist the provider order"
)
require(pressLexiRayButton(identifier: "ProviderEditButton"), "Done did not exit provider editing")

pass()
