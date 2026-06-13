// Scenario: a history result with inline code chips and a long Chinese sentence
// wraps inside the floating panel instead of clipping at the right edge.
openBlankComposer()
require(focusFloatingSourceEditor(), "source editor did not accept focus before history navigation")

press(126)
require(
  waitFor("up arrow restores rich wrap history") { floatingSourceText().contains(richWrapHistoryText) },
  "up arrow did not restore rich wrap history"
)

require(
  lexirayVisibleTextContains("gemini-3.1-pro-preview-all"),
  "rich inline code result was not visible"
)

let defaultOverflow = visibleStaticTextOverflowingFloatingPanelRightBoundary()
require(defaultOverflow.isEmpty, "default width rich result text overflowed: \(defaultOverflow.joined(separator: "; "))")
snapPanel("rich-result-wrap-default")

if let defaultSize = floatingPanelSize(),
   setFloatingPanelSize(CGSize(width: 900, height: defaultSize.height))
{
  require(
    waitFor("wide panel resize") { (floatingPanelSize()?.width ?? 0) >= 880 },
    "floating panel did not resize wider"
  )
  require(
    lexirayVisibleTextContains("gemini-3.1-pro-preview-all"),
    "rich inline code result was not visible after widening"
  )
  let wideOverflow = visibleStaticTextOverflowingFloatingPanelRightBoundary()
  require(wideOverflow.isEmpty, "wide rich result text overflowed: \(wideOverflow.joined(separator: "; "))")
  snapPanel("rich-result-wrap-wide")

  _ = setFloatingPanelSize(CGSize(width: 660, height: 330))
  _ = waitFor("restore compact panel size") {
    let size = floatingPanelSize() ?? .zero
    return abs(size.width - 660) < 8 && abs(size.height - 330) < 8
  }
} else {
  print("UI_NOTE[rich_result_wrap]: AX resize was not available; wide reflow screenshot skipped")
}

closePanel()
pass()
