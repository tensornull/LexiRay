@testable import LexiRay
import XCTest

final class OCRServiceTests: XCTestCase {
  func testNormalizeRecognizedLinesTrimsBlankLines() {
    XCTAssertEqual(
      OCRService.normalizeRecognizedLines(["  hello  ", "", " world "]),
      "hello\nworld"
    )
  }
}
