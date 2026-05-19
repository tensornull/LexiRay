import CoreGraphics
import Foundation
import ScreenCaptureKit
import Vision

@MainActor
final class OCRService {
  func captureAndRecognizeText(in rect: CGRect) async throws -> String {
    guard rect.width >= 8, rect.height >= 8 else {
      throw TranslationError.ocrUnavailable("Select a larger OCR region")
    }

    guard PermissionService.requestScreenCaptureIfNeeded() else {
      throw TranslationError.ocrUnavailable("Screen Recording permission is required for OCR")
    }

    let image = try await captureImage(in: rect)
    return try await recognizeText(in: image)
  }

  func recognizeText(in image: CGImage) async throws -> String {
    try await Task.detached(priority: .userInitiated) {
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      request.automaticallyDetectsLanguage = true

      let handler = VNImageRequestHandler(cgImage: image, options: [:])
      try handler.perform([request])

      let lines = (request.results ?? [])
        .sorted { lhs, rhs in
          if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.02 {
            return lhs.boundingBox.midY > rhs.boundingBox.midY
          }
          return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
        .compactMap { observation in
          observation.topCandidates(1).first?.string
        }

      guard let text = Self.normalizeRecognizedLines(lines).nonEmptyTrimmed else {
        throw TranslationError.ocrUnavailable("No text was recognized in the selected region")
      }

      return text
    }.value
  }

  nonisolated static func normalizeRecognizedLines(_ lines: [String]) -> String {
    lines
      .map(\.trimmedForQuery)
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
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
}
