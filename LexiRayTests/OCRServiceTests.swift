import CoreGraphics
import Foundation
@testable import LexiRay
import ScreenCaptureKit
import XCTest

final class OCRServiceTests: XCTestCase {
  func testNormalizeRecognizedLinesTrimsBlankLines() {
    XCTAssertEqual(
      OCRService.normalizeRecognizedLines(["  hello  ", "", " world "]),
      "hello\nworld"
    )
  }

  func testNormalizedTextGroupsMixedLanguageAndCodeByRows() {
    let candidates = [
      OCRService.RecognizedTextCandidate(
        text: "CODE_SIGNING_ALLOWED=NO",
        boundingBox: CGRect(x: 0.62, y: 0.43, width: 0.28, height: 0.04),
        confidence: 0.8
      ),
      OCRService.RecognizedTextCandidate(
        text: "xcodebuild test -project LexiRay.xcodeproj",
        boundingBox: CGRect(x: 0.08, y: 0.43, width: 0.5, height: 0.04),
        confidence: 0.78
      ),
      OCRService.RecognizedTextCandidate(
        text: "验证:",
        boundingBox: CGRect(x: 0.04, y: 0.82, width: 0.12, height: 0.05),
        confidence: 0.9
      ),
      OCRService.RecognizedTextCandidate(
        text: "./script/build_and_run.sh --verify",
        boundingBox: CGRect(x: 0.08, y: 0.22, width: 0.4, height: 0.04),
        confidence: 0.82
      )
    ]

    XCTAssertEqual(
      OCRService.normalizedText(from: candidates),
      """
      验证:
      xcodebuild test -project LexiRay.xcodeproj CODE_SIGNING_ALLOWED=NO
      ./script/build_and_run.sh --verify
      """
    )
  }

  func testPreprocessedImageScalesSmallSelections() throws {
    let image = try makeImage(width: 120, height: 40)
    let processed = OCRService.preprocessedImageForRecognition(image)

    XCTAssertGreaterThanOrEqual(processed.width, image.width * 2)
    XCTAssertGreaterThanOrEqual(processed.height, image.height * 2)
  }

  func testRecognitionRequestUsesMixedLanguagesWithoutCorrection() {
    let request = OCRService.makeRecognitionRequest()

    XCTAssertEqual(request.recognitionLanguages, ["zh-Hans", "en-US"])
    XCTAssertFalse(request.usesLanguageCorrection)
    XCTAssertTrue(request.automaticallyDetectsLanguage)
  }

  func testCaptureRectConversionFlipsMainDisplayYCoordinate() throws {
    let conversion = try XCTUnwrap(
      OCRService.captureRectConversion(
        for: CGRect(x: 100, y: 200, width: 300, height: 120),
        displays: [
          OCRCaptureDisplay(
            displayIndex: 1,
            appKitFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            displayBounds: CGRect(x: 0, y: 0, width: 1440, height: 900)
          )
        ]
      )
    )

    XCTAssertEqual(conversion.rect, CGRect(x: 100, y: 580, width: 300, height: 120))
    XCTAssertEqual(conversion.displayCount, 1)
    XCTAssertEqual(conversion.displayIndices, [1])
  }

  func testCaptureRectConversionKeepsNegativeSideDisplayXCoordinate() throws {
    let conversion = try XCTUnwrap(
      OCRService.captureRectConversion(
        for: CGRect(x: -1200, y: 100, width: 200, height: 50),
        displays: [
          OCRCaptureDisplay(
            displayIndex: 2,
            appKitFrame: CGRect(x: -1280, y: 0, width: 1280, height: 720),
            displayBounds: CGRect(x: -1280, y: 0, width: 1280, height: 720)
          )
        ]
      )
    )

    XCTAssertEqual(conversion.rect, CGRect(x: -1200, y: 570, width: 200, height: 50))
    XCTAssertEqual(conversion.displayCount, 1)
    XCTAssertEqual(conversion.displayIndices, [2])
  }

  func testCaptureRectConversionUnionsCrossDisplaySelection() throws {
    let conversion = try XCTUnwrap(
      OCRService.captureRectConversion(
        for: CGRect(x: 1380, y: 100, width: 120, height: 60),
        displays: [
          OCRCaptureDisplay(
            displayIndex: 1,
            appKitFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            displayBounds: CGRect(x: 0, y: 0, width: 1440, height: 900)
          ),
          OCRCaptureDisplay(
            displayIndex: 2,
            appKitFrame: CGRect(x: 1440, y: 0, width: 1000, height: 900),
            displayBounds: CGRect(x: 1440, y: 0, width: 1000, height: 900)
          )
        ]
      )
    )

    XCTAssertEqual(conversion.rect, CGRect(x: 1380, y: 740, width: 120, height: 60))
    XCTAssertEqual(conversion.displayCount, 2)
    XCTAssertEqual(conversion.displayIndices, [1, 2])
  }

  func testCaptureErrorMapsUserDeclinedToPermissionRecovery() {
    let error = NSError(
      domain: SCStreamErrorDomain,
      code: SCStreamError.userDeclined.rawValue
    )

    XCTAssertEqual(
      OCRService.captureError(from: error),
      .screenRecordingPermissionRequired
    )
  }

  func testCaptureErrorPreservesUnexpectedFailureDescription() {
    let error = NSError(
      domain: SCStreamErrorDomain,
      code: SCStreamError.failedToStart.rawValue,
      userInfo: [NSLocalizedDescriptionKey: "capture unavailable"]
    )

    XCTAssertEqual(
      OCRService.captureError(from: error),
      .captureFailed("capture unavailable")
    )
  }

  private func makeImage(width: Int, height: Int) throws -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = try XCTUnwrap(
      CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    )
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return try XCTUnwrap(context.makeImage())
  }
}
