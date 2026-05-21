import Foundation
import OSLog

enum AppConstants {
  static let appName = "LexiRay"
  static let bundleID = "io.github.tensornull.lexiray"
  static let defaultHotKeyDescription = HotKeyConfiguration.defaultTranslate.displayString
  static let defaultOCRHotKeyDescription = HotKeyConfiguration.defaultOCR.displayString
}

enum AppLog {
  static let app = Logger(subsystem: AppConstants.bundleID, category: "App")
  static let hotKey = Logger(subsystem: AppConstants.bundleID, category: "HotKey")
  static let selection = Logger(subsystem: AppConstants.bundleID, category: "Selection")
  static let translation = Logger(subsystem: AppConstants.bundleID, category: "Translation")
  static let settings = Logger(subsystem: AppConstants.bundleID, category: "Settings")
  static let panel = Logger(subsystem: AppConstants.bundleID, category: "Panel")
  static let ocr = Logger(subsystem: AppConstants.bundleID, category: "OCR")
}
