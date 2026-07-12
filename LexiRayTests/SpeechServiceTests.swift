@testable import LexiRay
import XCTest

final class SpeechServiceTests: XCTestCase {
  func testCancelledPreviousUtteranceCannotCompleteReplacement() {
    let previous = NSObject()
    let replacement = NSObject()
    var state = SpeechUtteranceState()

    state.start(ObjectIdentifier(previous))
    state.start(ObjectIdentifier(replacement))

    XCTAssertFalse(state.complete(ObjectIdentifier(previous)))
    XCTAssertEqual(state.activeID, ObjectIdentifier(replacement))
    XCTAssertTrue(state.complete(ObjectIdentifier(replacement)))
    XCTAssertNil(state.activeID)
  }

  func testExplicitStopIgnoresLaterCancellationCallback() {
    let utterance = NSObject()
    var state = SpeechUtteranceState()

    state.start(ObjectIdentifier(utterance))
    state.stop()

    XCTAssertFalse(state.complete(ObjectIdentifier(utterance)))
    XCTAssertNil(state.activeID)
  }
}
