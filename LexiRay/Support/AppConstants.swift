import Foundation
import OSLog

enum AppConstants {
  static let appName = "LexiRay"
  static let bundleID = "io.github.tensornull.lexiray"

  static var defaultHotKeyDescription: String {
    HotKeyConfiguration.defaultTranslate.displayString
  }

  static var defaultOCRHotKeyDescription: String {
    HotKeyConfiguration.defaultOCR.displayString
  }
}

enum AppLog {
  static var app: Logger {
    Logger(subsystem: AppConstants.bundleID, category: "App")
  }

  static var hotKey: Logger {
    Logger(subsystem: AppConstants.bundleID, category: "HotKey")
  }

  static var selection: Logger {
    Logger(subsystem: AppConstants.bundleID, category: "Selection")
  }

  static var translation: Logger {
    Logger(subsystem: AppConstants.bundleID, category: "Translation")
  }

  static var settings: Logger {
    Logger(subsystem: AppConstants.bundleID, category: "Settings")
  }

  static var panel: Logger {
    Logger(subsystem: AppConstants.bundleID, category: "Panel")
  }

  static var ocr: Logger {
    Logger(subsystem: AppConstants.bundleID, category: "OCR")
  }
}
