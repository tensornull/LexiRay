@testable import LexiRay
import XCTest

final class RichTranslationRendererTests: XCTestCase {
  func testMarkdownRendersToExpectedPlainString() {
    let rendered = RichTranslationRenderer.plainString(for: "**Bold**\n\n- one\n- `two`")

    XCTAssertTrue(rendered.contains("Bold"))
    XCTAssertTrue(rendered.contains("one"))
    XCTAssertTrue(rendered.contains("two"))
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
