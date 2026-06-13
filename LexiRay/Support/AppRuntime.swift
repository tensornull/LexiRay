import Foundation

enum AppRuntime {
  static var isRunningTests: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
      || NSClassFromString("XCTestCase") != nil
  }

  static var isRunningUIScenarios: Bool {
    ProcessInfo.processInfo.environment["LEXIRAY_UI_SCENARIO"] == "1"
  }

  static var allowsMockProvider: Bool {
    isRunningUIScenarios
  }

  static var usesStreamingMockProvider: Bool {
    isRunningUIScenarios
  }
}
