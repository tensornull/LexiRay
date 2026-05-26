@testable import LexiRay
import XCTest

final class RichTranslationRendererTests: XCTestCase {
  func testMarkdownRendersToExpectedPlainString() {
    let rendered = RichTranslationRenderer.plainString(for: "**Bold**\n\n- one\n- `two`")

    XCTAssertTrue(rendered.contains("Bold"))
    XCTAssertTrue(rendered.contains("one"))
    XCTAssertTrue(rendered.contains("two"))
  }

  func testPlainTextPreservesLineBreaks() {
    let text = "First line\nSecond line\n\nFourth line"

    XCTAssertEqual(RichTranslationRenderer.plainString(for: text), text)
  }

  func testMarkdownPreservesVisibleLineBreaks() {
    let rendered = RichTranslationRenderer.plainString(for: "**Bold**\nNext line")

    XCTAssertEqual(rendered, "Bold\nNext line")
  }

  func testMarkdownRendersInlineFormatting() {
    let rendered = RichTranslationRenderer.attributedString(for: "**Bold** and `code` [link](https://example.test)")

    XCTAssertEqual(String(rendered.characters), "Bold and code link")
    XCTAssertTrue(rendered.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
    XCTAssertTrue(rendered.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
    XCTAssertTrue(rendered.runs.contains { $0.link?.absoluteString == "https://example.test" })
  }

  func testMarkdownBuildsBlockModel() {
    let blocks = RichTranslationRenderer.blocks(for: """
    ## Title

    - one
    - two

    > quoted

    ```json
    {"ok": true}
    ```
    """)

    XCTAssertTrue(blocks.contains { if case .heading(2, _) = $0 { true } else { false } })
    XCTAssertEqual(blocks.count(where: { if case .listItem = $0 { true } else { false } }), 2)
    XCTAssertTrue(blocks.contains { if case .quote = $0 { true } else { false } })
    XCTAssertTrue(blocks.contains { if case .code("json", #"{"ok": true}"#) = $0 { true } else { false } })
  }

  func testStructuredPlainTextBuildsCodeBlock() {
    let blocks = RichTranslationRenderer.blocks(for: """
    {
      "type": "error",
      "message": "failed"
    }
    """)

    XCTAssertEqual(blocks, [
      .code(language: "json", code: """
      {
        "type": "error",
        "message": "failed"
      }
      """)
    ])
  }

  func testListItemWithJSONTailBuildsCodeBlock() {
    let blocks = RichTranslationRenderer.blocks(for: """
    - Message is: {
        "type": "error",
        "message": "failed"
      }
    """)

    XCTAssertTrue(blocks.contains { if case .listItem = $0 { true } else { false } })
    XCTAssertTrue(blocks.contains { if case let .code("json", code) = $0 { code.contains(#""type": "error""#) } else { false } })
  }

  func testMarkdownFenceContentIsNotHardBreakRewritten() {
    let markdown = """
    ```swift
    let first = 1
    let second = 2
    ```
    Done
    """

    let prepared = RichTranslationRenderer.markdownPreservingVisibleLineBreaks(markdown)

    XCTAssertTrue(prepared.contains("let first = 1\nlet second = 2"))
    XCTAssertFalse(prepared.contains("let first = 1  \nlet second = 2"))
    XCTAssertEqual(RichTranslationRenderer.plainString(for: markdown), "let first = 1\nlet second = 2\nDone")
  }

  func testHTMLRendersToExpectedPlainString() {
    let rendered = RichTranslationRenderer.plainString(for: "<p>Hello <strong>world</strong></p><a href=\"https://example.test\">Link</a>")

    XCTAssertTrue(rendered.contains("Hello world"))
    XCTAssertTrue(rendered.contains("Link"))
  }

  func testUnsafeHTMLIsRemovedBeforeRendering() {
    let sanitized = RichTranslationRenderer.sanitizedHTML(
      #"<p onclick="alert(1)">Safe</p><script>alert(1)</script><img src="https://example.test/a.png"><a href="javascript:alert(1)">bad</a>"#
    )

    XCTAssertFalse(sanitized.localizedCaseInsensitiveContains("<script"))
    XCTAssertFalse(sanitized.localizedCaseInsensitiveContains("<img"))
    XCTAssertFalse(sanitized.localizedCaseInsensitiveContains("onclick"))
    XCTAssertFalse(sanitized.localizedCaseInsensitiveContains("javascript:"))
    XCTAssertTrue(sanitized.contains("Safe"))
  }

  func testPlainTextFallsBackWithoutChangingContent() {
    let text = "Plain < text without an HTML tag"

    XCTAssertEqual(RichTranslationRenderer.plainString(for: text), text)
  }
}
