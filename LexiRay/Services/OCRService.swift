import AppKit
import CoreGraphics
import CoreImage
import Foundation
import ScreenCaptureKit
import Vision

@MainActor
protocol OCRRecognizing: AnyObject {
  func captureAndRecognizeText(in rect: CGRect) async throws -> String
}

struct OCRCaptureDisplay: Equatable {
  let appKitFrame: CGRect
  let displayBounds: CGRect
}

struct OCRCaptureRectConversion: Equatable {
  let rect: CGRect
  let displayCount: Int
}

@MainActor
final class OCRService: OCRRecognizing {
  struct RecognizedTextCandidate: Equatable {
    let text: String
    let boundingBox: CGRect
    let confidence: Float
  }

  private struct RecognitionResult {
    let text: String
    let averageConfidence: Float

    var isHighQuality: Bool {
      (text.count >= 16 && averageConfidence >= 0.55) || (text.count >= 80 && averageConfidence >= 0.45)
    }

    var score: Float {
      Float(text.count) + averageConfidence * 100 + Float(text.lineCount * 4)
    }
  }

  func captureAndRecognizeText(in rect: CGRect) async throws -> String {
    guard rect.width >= 8, rect.height >= 8 else {
      throw TranslationError.ocrUnavailable("Select a larger OCR region")
    }

    guard PermissionService.requestScreenCaptureIfNeeded() else {
      throw TranslationError.ocrUnavailable("Screen Recording permission is required for OCR")
    }

    let conversion = Self.captureRectConversion(for: rect, displays: Self.currentCaptureDisplays())
      ?? OCRCaptureRectConversion(rect: rect, displayCount: 0)
    AppLog.ocr.info(
      """
      OCR capture rect appKit=\(Self.describe(rect), privacy: .public) \
      capture=\(Self.describe(conversion.rect), privacy: .public) \
      displays=\(conversion.displayCount)
      """
    )

    let image = try await captureImage(in: conversion.rect)
    return try await recognizeText(in: image)
  }

  func recognizeText(in image: CGImage) async throws -> String {
    try await Task.detached(priority: .userInitiated) {
      var bestResult: RecognitionResult?
      var lastError: Error?

      for image in Self.recognitionImages(for: image) {
        do {
          let result = try Self.recognizeTextResult(in: image)
          if bestResult == nil || result.score > bestResult!.score {
            bestResult = result
          }
          if result.isHighQuality {
            return result.text
          }
        } catch {
          lastError = error
        }
      }

      if let bestResult {
        return bestResult.text
      }

      if let lastError {
        throw lastError
      }

      throw TranslationError.ocrUnavailable("No text was recognized in the selected region")
    }.value
  }

  nonisolated static var defaultRecognitionLanguages: [String] {
    ["zh-Hans", "en-US"]
  }

  nonisolated static func makeRecognitionRequest() -> VNRecognizeTextRequest {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = defaultRecognitionLanguages
    request.usesLanguageCorrection = false
    request.automaticallyDetectsLanguage = true
    return request
  }

  nonisolated static func normalizeRecognizedLines(_ lines: [String]) -> String {
    lines
      .map(sanitizeRecognizedLine)
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
  }

  nonisolated static func normalizedText(from candidates: [RecognizedTextCandidate]) -> String {
    let sanitizedCandidates = candidates.compactMap { candidate -> RecognizedTextCandidate? in
      let text = sanitizeRecognizedLine(candidate.text)
      guard !text.isEmpty else {
        return nil
      }

      return RecognizedTextCandidate(
        text: text,
        boundingBox: candidate.boundingBox,
        confidence: candidate.confidence
      )
    }

    return groupedRows(from: sanitizedCandidates)
      .map(joinedRowText)
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
  }

  nonisolated static func preprocessedImageForRecognition(_ image: CGImage) -> CGImage {
    enhancedImage(for: image) ?? image
  }

  nonisolated static func captureRectConversion(
    for appKitRect: CGRect,
    displays: [OCRCaptureDisplay]
  ) -> OCRCaptureRectConversion? {
    var convertedRect = CGRect.null
    var displayCount = 0

    for display in displays {
      let intersection = appKitRect.intersection(display.appKitFrame)
      guard !intersection.isNull, !intersection.isEmpty else {
        continue
      }

      let converted = CGRect(
        x: display.displayBounds.minX + (intersection.minX - display.appKitFrame.minX),
        y: display.displayBounds.minY + (display.appKitFrame.maxY - intersection.maxY),
        width: intersection.width,
        height: intersection.height
      )
      convertedRect = convertedRect.union(converted)
      displayCount += 1
    }

    guard displayCount > 0, !convertedRect.isNull, !convertedRect.isEmpty else {
      return nil
    }

    return OCRCaptureRectConversion(rect: convertedRect.integral, displayCount: displayCount)
  }

  private func captureImage(in rect: CGRect) async throws -> CGImage {
    guard #available(macOS 15.2, *) else {
      throw TranslationError.ocrUnavailable("OCR capture requires macOS 15.2 or newer")
    }

    return try await withCheckedThrowingContinuation { continuation in
      SCScreenshotManager.captureImage(in: rect) { image, error in
        if let error {
          continuation.resume(throwing: TranslationError.ocrUnavailable(error.localizedDescription))
          return
        }

        guard let image else {
          continuation.resume(throwing: TranslationError.ocrUnavailable("Screen capture returned no image"))
          return
        }

        continuation.resume(returning: image)
      }
    }
  }

  private nonisolated static func recognizeTextResult(in image: CGImage) throws -> RecognitionResult {
    let request = makeRecognitionRequest()
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([request])

    let candidates = (request.results ?? []).compactMap { observation -> RecognizedTextCandidate? in
      guard let candidate = observation.topCandidates(1).first else {
        return nil
      }

      return RecognizedTextCandidate(
        text: candidate.string,
        boundingBox: observation.boundingBox,
        confidence: candidate.confidence
      )
    }

    guard let text = normalizedText(from: candidates).nonEmptyTrimmed else {
      throw TranslationError.ocrUnavailable("No text was recognized in the selected region")
    }

    let averageConfidence = candidates.isEmpty
      ? 0
      : candidates.reduce(Float(0)) { $0 + $1.confidence } / Float(candidates.count)
    return RecognitionResult(text: text, averageConfidence: averageConfidence)
  }

  private static func currentCaptureDisplays() -> [OCRCaptureDisplay] {
    NSScreen.screens.compactMap { screen in
      guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
        return nil
      }

      return OCRCaptureDisplay(
        appKitFrame: screen.frame,
        displayBounds: CGDisplayBounds(CGDirectDisplayID(screenNumber.uint32Value))
      )
    }
  }

  private nonisolated static func recognitionImages(for image: CGImage) -> [CGImage] {
    guard let enhancedImage = enhancedImage(for: image) else {
      return [image]
    }

    return [enhancedImage, image]
  }

  private nonisolated static func enhancedImage(for image: CGImage) -> CGImage? {
    guard image.width > 0, image.height > 0 else {
      return nil
    }

    var output = CIImage(cgImage: image)
    let scale = recognitionScale(forWidth: image.width, height: image.height)
    if scale > 1 {
      output = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    output = output
      .applyingFilter(
        "CIColorControls",
        parameters: [
          "inputSaturation": 0,
          "inputContrast": 1.22,
          "inputBrightness": 0.02
        ]
      )
      .applyingFilter("CISharpenLuminance", parameters: ["inputSharpness": 0.35])

    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    return CIContext().createCGImage(
      output,
      from: output.extent.integral,
      format: .RGBA8,
      colorSpace: colorSpace
    )
  }

  private nonisolated static func recognitionScale(forWidth width: Int, height: Int) -> CGFloat {
    let minDimension = CGFloat(min(width, height))
    let maxDimension = CGFloat(max(width, height))
    guard minDimension > 0, maxDimension > 0 else {
      return 1
    }

    var scale: CGFloat = 1
    if minDimension < 480 {
      scale = min(3, 480 / minDimension)
    }
    if maxDimension * scale > 3200 {
      scale = max(1, 3200 / maxDimension)
    }
    return max(1, scale)
  }

  private nonisolated static func groupedRows(from candidates: [RecognizedTextCandidate]) -> [[RecognizedTextCandidate]] {
    let sorted = candidates.sorted { lhs, rhs in
      if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > rowThreshold(for: [lhs, rhs]) {
        return lhs.boundingBox.midY > rhs.boundingBox.midY
      }
      return lhs.boundingBox.minX < rhs.boundingBox.minX
    }

    return sorted.reduce(into: [[RecognizedTextCandidate]]()) { rows, candidate in
      guard let lastIndex = rows.indices.last else {
        rows.append([candidate])
        return
      }

      if belongsToRow(candidate, row: rows[lastIndex]) {
        rows[lastIndex].append(candidate)
      } else {
        rows.append([candidate])
      }
    }
  }

  private nonisolated static func belongsToRow(
    _ candidate: RecognizedTextCandidate,
    row: [RecognizedTextCandidate]
  ) -> Bool {
    let rowMidY = row.reduce(CGFloat(0)) { $0 + $1.boundingBox.midY } / CGFloat(row.count)
    let threshold = rowThreshold(for: row + [candidate])
    return abs(candidate.boundingBox.midY - rowMidY) <= threshold
  }

  private nonisolated static func rowThreshold(for candidates: [RecognizedTextCandidate]) -> CGFloat {
    let maxHeight = candidates.map(\.boundingBox.height).max() ?? 0
    return max(0.018, min(0.06, maxHeight * 0.7))
  }

  private nonisolated static func joinedRowText(_ row: [RecognizedTextCandidate]) -> String {
    let sorted = row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
    var line = ""
    var previous: RecognizedTextCandidate?

    for candidate in sorted {
      if let previous,
         shouldInsertSpace(
           after: previous.text,
           before: candidate.text,
           horizontalGap: candidate.boundingBox.minX - previous.boundingBox.maxX
         )
      {
        line += " "
      }
      line += candidate.text
      previous = candidate
    }

    return line.trimmedForQuery
  }

  private nonisolated static func shouldInsertSpace(
    after previousText: String,
    before nextText: String,
    horizontalGap: CGFloat
  ) -> Bool {
    guard horizontalGap > 0.006 else {
      return false
    }

    if let next = nextText.first, Set<Character>(".,:;!?)]}").contains(next) {
      return false
    }
    if let previous = previousText.last, Set<Character>("([{").contains(previous) {
      return false
    }
    if let previous = previousText.last,
       let next = nextText.first,
       isCJK(previous),
       isCJK(next),
       horizontalGap < 0.02
    {
      return false
    }

    return true
  }

  private nonisolated static func sanitizeRecognizedLine(_ line: String) -> String {
    line
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmedForQuery
  }

  private nonisolated static func describe(_ rect: CGRect) -> String {
    "x:\(Int(rect.origin.x)) y:\(Int(rect.origin.y)) w:\(Int(rect.width)) h:\(Int(rect.height))"
  }

  private nonisolated static func isCJK(_ character: Character) -> Bool {
    character.unicodeScalars.contains { scalar in
      (0x4E00 ... 0x9FFF).contains(scalar.value)
        || (0x3400 ... 0x4DBF).contains(scalar.value)
        || (0xF900 ... 0xFAFF).contains(scalar.value)
    }
  }
}
