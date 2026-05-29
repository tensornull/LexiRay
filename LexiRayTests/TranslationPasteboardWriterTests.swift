import AppKit
@testable import LexiRay
import XCTest

@MainActor
final class TranslationPasteboardWriterTests: XCTestCase {
  func testWritesOriginalTextAsString() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("LexiRayPasteboardTests-\(UUID().uuidString)"))

    TranslationPasteboardWriter.write(result: makeResult("**hello**"), format: .originalText, to: pasteboard)

    XCTAssertEqual(pasteboard.string(forType: .string), "**hello**")
  }

  func testWritesPlainTextFromRenderedContent() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("LexiRayPasteboardTests-\(UUID().uuidString)"))

    TranslationPasteboardWriter.write(result: makeResult("**hello**"), format: .plainText, to: pasteboard)

    XCTAssertEqual(pasteboard.string(forType: .string), "hello")
  }

  func testWritesMarkdownTypeAndStringFallback() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("LexiRayPasteboardTests-\(UUID().uuidString)"))

    TranslationPasteboardWriter.write(result: makeResult("**hello**"), format: .markdown, to: pasteboard)

    XCTAssertEqual(pasteboard.string(forType: TranslationPasteboardWriter.markdownPasteboardType), "**hello**")
    XCTAssertEqual(pasteboard.string(forType: .string), "**hello**")
  }

  func testWritesSanitizedHTMLAndPlainStringFallback() {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("LexiRayPasteboardTests-\(UUID().uuidString)"))
    let html = #"<p onclick="bad()">Hello <strong>world</strong></p><script>bad()</script>"#

    TranslationPasteboardWriter.write(result: makeResult(html), format: .html, to: pasteboard)

    let copiedHTML = pasteboard.string(forType: .html) ?? ""
    XCTAssertTrue(copiedHTML.contains("Hello"))
    XCTAssertFalse(copiedHTML.localizedCaseInsensitiveContains("<script"))
    XCTAssertFalse(copiedHTML.localizedCaseInsensitiveContains("onclick"))
    XCTAssertTrue(pasteboard.string(forType: .string)?.contains("Hello world") == true)
  }

  func testClipboardSelectionReaderReturnsNilWhenCopyDoesNotUpdatePasteboard() async {
    let pasteboard = makePasteboard()
    _ = pasteboard.setString("sentinel", forType: .string)
    let reader = ClipboardSelectionReader(
      pasteboard: pasteboard,
      frontmostBundleIdentifier: { "com.apple.TextEdit" },
      copyAction: {},
      waitAfterCopy: { _ in }
    )

    let copiedText = await reader.copyCurrentSelection()

    XCTAssertNil(copiedText)
    XCTAssertEqual(pasteboard.string(forType: .string), "sentinel")
  }

  func testClipboardSelectionReaderReturnsFreshCopiedTextAndRestoresPasteboard() async {
    let pasteboard = makePasteboard()
    _ = pasteboard.setString("sentinel", forType: .string)
    let reader = ClipboardSelectionReader(
      pasteboard: pasteboard,
      frontmostBundleIdentifier: { "com.apple.TextEdit" },
      copyAction: {},
      waitAfterCopy: { _ in
        pasteboard.clearContents()
        _ = pasteboard.setString("fresh selection", forType: .string)
      }
    )

    let copiedText = await reader.copyCurrentSelection()

    XCTAssertEqual(copiedText, "fresh selection")
    XCTAssertEqual(pasteboard.string(forType: .string), "sentinel")
  }

  func testClipboardSelectionReaderSkipsSimulatedCopyWhenLexiRayIsFrontmost() async {
    let pasteboard = makePasteboard()
    _ = pasteboard.setString("sentinel", forType: .string)
    var didCopy = false
    let reader = ClipboardSelectionReader(
      pasteboard: pasteboard,
      frontmostBundleIdentifier: { AppConstants.bundleID },
      copyAction: {
        didCopy = true
      },
      waitAfterCopy: { _ in }
    )

    let copiedText = await reader.copyCurrentSelection()

    XCTAssertNil(copiedText)
    XCTAssertFalse(didCopy)
    XCTAssertEqual(pasteboard.string(forType: .string), "sentinel")
  }

  private func makeResult(_ text: String) -> TranslationResult {
    TranslationResult(
      request: TranslationRequest(
        text: "hello",
        sourceLanguage: "en",
        targetLanguage: "zh-Hans",
        selectionSource: .manual
      ),
      providerID: .mock,
      providerName: "Mock",
      translatedText: text
    )
  }

  private func makePasteboard() -> NSPasteboard {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("LexiRayPasteboardTests-\(UUID().uuidString)"))
    pasteboard.clearContents()
    return pasteboard
  }
}
