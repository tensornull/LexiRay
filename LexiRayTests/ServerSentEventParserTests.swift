@testable import LexiRay
import XCTest

final class ServerSentEventParserTests: XCTestCase {
  func testParserCombinesMultiLineData() {
    var parser = ServerSentEventParser()

    XCTAssertNil(parser.consume("event: update"))
    XCTAssertNil(parser.consume("data: first"))
    XCTAssertNil(parser.consume("data: second"))
    let event = parser.consume("")

    XCTAssertEqual(event, ServerSentEvent(event: "update", data: "first\nsecond"))
  }

  func testParserEmitsDoneData() {
    var parser = ServerSentEventParser()

    XCTAssertNil(parser.consume("data: [DONE]"))

    XCTAssertEqual(parser.consume(""), ServerSentEvent(event: nil, data: "[DONE]"))
  }

  func testParserIgnoresCommentsAndUnknownFields() {
    var parser = ServerSentEventParser()

    XCTAssertNil(parser.consume(": keep-alive"))
    XCTAssertNil(parser.consume("retry: 1000"))
    XCTAssertNil(parser.consume("event: ping"))
    XCTAssertNil(parser.consume("data: {}"))

    XCTAssertEqual(parser.consume(""), ServerSentEvent(event: "ping", data: "{}"))
  }

  func testFinishFlushesPendingEvent() {
    var parser = ServerSentEventParser()

    XCTAssertNil(parser.consume("data: trailing"))

    XCTAssertEqual(parser.finish(), ServerSentEvent(event: nil, data: "trailing"))
  }
}
