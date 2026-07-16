import Carbon
@testable import LexiRay
import XCTest

@MainActor
final class GlobalHotKeyServiceTests: XCTestCase {
  func testMapsRegistrationOutcomes() {
    XCTAssertEqual(
      GlobalHotKeyService.registrationStatus(isValid: false, osStatus: noErr),
      .invalid
    )
    XCTAssertEqual(
      GlobalHotKeyService.registrationStatus(isValid: true, osStatus: noErr),
      .registered
    )
    XCTAssertEqual(
      GlobalHotKeyService.registrationStatus(isValid: true, osStatus: OSStatus(eventHotKeyExistsErr)),
      .conflict
    )
    XCTAssertEqual(
      GlobalHotKeyService.registrationStatus(isValid: true, osStatus: OSStatus(paramErr)),
      .systemError(OSStatus(paramErr))
    )
  }

  func testRegistersBothShortcutsWhenOneConflicts() {
    var attemptedIDs: [UInt32] = []

    let results = GlobalHotKeyService.independentlyRegister(
      translateHotKey: .defaultTranslate,
      ocrHotKey: .defaultOCR
    ) { _, id in
      attemptedIDs.append(id)
      return id == 1 ? .conflict : .registered
    }

    XCTAssertEqual(attemptedIDs, [1, 2])
    XCTAssertEqual(results.translate, .conflict)
    XCTAssertEqual(results.ocr, .registered)
  }

  func testInvalidTranslateShortcutDoesNotPreventOCRRegistration() {
    var attemptedIDs: [UInt32] = []

    let results = GlobalHotKeyService.independentlyRegister(
      translateHotKey: .defaultTranslate,
      ocrHotKey: .defaultOCR
    ) { _, id in
      attemptedIDs.append(id)
      return id == 1 ? .invalid : .registered
    }

    XCTAssertEqual(attemptedIDs, [1, 2])
    XCTAssertEqual(results.translate, .invalid)
    XCTAssertEqual(results.ocr, .registered)
  }
}
