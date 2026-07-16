// Scenario: a deterministic denied Screen Recording state stops OCR before
// selection, shows recovery UI, and never triggers the real TCC prompt.
restartWorkspaceApp(extraArguments: ["--lexiray-acceptance-screen-capture=denied"])
activateWorkspaceApp()

let hotKey = loadOCRHotKey()
press(hotKey.keyCode, flags: hotKey.flags)

require(
  waitFor("OCR permission recovery panel", timeout: 8) { !panelWindows().isEmpty },
  "OCR permission denial did not show the floating recovery panel"
)

let screenFrames = NSScreen.screens.map(\.frame)
let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
let expectedOverlayFrames = screenFrames.map { frame in
  CGRect(
    x: frame.minX,
    y: primaryTop - frame.maxY,
    width: frame.width,
    height: frame.height
  )
}

let overlayWindows = lexirayWindowInfos().filter { window in
  expectedOverlayFrames.contains { expected in
    windowFramesApproximatelyMatch(windowBounds(window), expected)
  }
}

require(overlayWindows.isEmpty, "OCR selection overlays appeared before Screen Recording permission")

let recoveryButton = lexirayAXElements().first { element in
  axString(element, kAXRoleAttribute) == "AXButton"
    && axString(element, kAXIdentifierAttribute) == "FloatingPanelErrorRecoveryButton"
}

require(recoveryButton != nil, "OCR permission recovery action was not exposed as a button")

let recoveryButtonName = [
  axString(recoveryButton!, kAXTitleAttribute),
  axString(recoveryButton!, kAXDescriptionAttribute),
  axString(recoveryButton!, kAXValueAttribute)
].joined(separator: " ")

require(
  recoveryButtonName.contains("Open System Settings"),
  "OCR permission recovery button did not expose its accessible name"
)

require(
  lexirayAXElements().contains { element in
    axString(element, kAXIdentifierAttribute) == "FloatingPanelErrorTitle"
      && (
        axString(element, kAXTitleAttribute).contains("Screen Recording Required")
          || axString(element, kAXDescriptionAttribute).contains("Screen Recording Required")
          || axString(element, kAXValueAttribute).contains("Screen Recording Required")
      )
  },
  "OCR permission error title was not exposed"
)

snapPanel("ocr-permission-required")
closePanel()
pass()
