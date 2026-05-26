@testable import LexiRay
import XCTest

final class SourceMarkdownPreparerTests: XCTestCase {
  func testPureJSONIsWrappedAsFencedCodeBlock() {
    let prepared = SourceMarkdownPreparer.prepare(#"{"type":"error","code":"beta_api_shape_disabled"}"#)

    XCTAssertTrue(prepared.hasPrefix("```json\n"))
    XCTAssertTrue(prepared.hasSuffix("\n```"))
    XCTAssertTrue(prepared.contains(#""type":"error""#))
  }

  func testMixedTextWrapsOnlyStructuredBlock() {
    let source = """
    Here is the payload:

    {
      "type": "error",
      "message": "failed"
    }

    Please explain it.
    """

    let prepared = SourceMarkdownPreparer.prepare(source)

    XCTAssertTrue(prepared.contains("Here is the payload:"))
    XCTAssertTrue(prepared.contains("```json\n{\n  \"type\": \"error\","))
    XCTAssertTrue(prepared.contains("Please explain it."))
  }

  func testPlainNaturalLanguageIsNotWrapped() {
    let source = "This is a normal paragraph.\nIt should stay as prose."

    XCTAssertEqual(SourceMarkdownPreparer.prepare(source), source)
  }
}
