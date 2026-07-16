import AppKit
import Darwin
import Foundation

enum AppRuntime {
  static let canonicalApplicationURL = URL(
    fileURLWithPath: "/Applications/LexiRay.app",
    isDirectory: true
  )

  static var acceptanceProfile: AcceptanceProfile? {
    do {
      return try AcceptanceProfile.resolve()
    } catch {
      let message = "Unsafe LexiRay acceptance profile configuration: \(error)\n"
      FileHandle.standardError.write(Data(message.utf8))
      Darwin.exit(78)
    }
  }

  static var isRunningTests: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
      || NSClassFromString("XCTestCase") != nil
  }

  static var isRunningUIScenarios: Bool {
    ProcessInfo.processInfo.environment["LEXIRAY_UI_SCENARIO"] == "1"
      || ProcessInfo.processInfo.arguments.contains("--lexiray-ui-scenario")
  }

  static func shouldPresentMainWindowAtLaunch(
    acceptanceProfile: AcceptanceProfile? = acceptanceProfile,
    isRunningUIScenarios: Bool = isRunningUIScenarios
  ) -> Bool {
    acceptanceProfile != nil && !isRunningUIScenarios
  }

  static var allowsMockProvider: Bool {
    acceptanceProfile != nil
  }

  static var usesStreamingMockProvider: Bool {
    isRunningUIScenarios
  }

  static func makePermissionChecker() -> PermissionChecking {
    guard acceptanceProfile != nil else {
      return SystemPermissionChecker()
    }

    let argumentPrefix = "--lexiray-acceptance-screen-capture="
    let argumentMode = ProcessInfo.processInfo.arguments
      .first(where: { $0.hasPrefix(argumentPrefix) })
      .map { String($0.dropFirst(argumentPrefix.count)) }
    let mode = argumentMode
      ?? ProcessInfo.processInfo.environment["LEXIRAY_ACCEPTANCE_SCREEN_CAPTURE"]

    switch mode?.lowercased() {
    case "system":
      return SystemPermissionChecker()
    case "denied":
      return AcceptancePermissionChecker(isScreenCaptureTrusted: false, grantsScreenCaptureOnRequest: false)
    case "grant-on-request":
      return AcceptancePermissionChecker(isScreenCaptureTrusted: false, grantsScreenCaptureOnRequest: true)
    default:
      return isRunningUIScenarios
        ? AcceptancePermissionChecker(isScreenCaptureTrusted: true, grantsScreenCaptureOnRequest: true)
        : SystemPermissionChecker()
    }
  }

  @MainActor
  static func makePasteboard(acceptanceProfile profile: AcceptanceProfile? = acceptanceProfile) -> NSPasteboard {
    guard let profile else {
      return .general
    }

    return NSPasteboard(
      name: NSPasteboard.Name("\(profile.defaultsSuiteName).pasteboard")
    )
  }

  static var acceptanceAppearance: String? {
    guard acceptanceProfile != nil else {
      return nil
    }
    let arguments = ProcessInfo.processInfo.arguments
    let name = "--lexiray-acceptance-appearance"
    if let inline = arguments.first(where: { $0.hasPrefix(name + "=") }) {
      return String(inline.dropFirst(name.count + 1)).lowercased()
    }
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
      return nil
    }
    return arguments[index + 1].lowercased()
  }

  @MainActor
  static func makeSettingsStore() -> SettingsStore {
    guard let profile = acceptanceProfile else {
      return SettingsStore()
    }

    guard let defaults = UserDefaults(suiteName: profile.defaultsSuiteName) else {
      fatalError("Could not create acceptance defaults suite \(profile.defaultsSuiteName)")
    }
    if defaults.data(forKey: "translateHotKey") == nil,
       let data = try? JSONEncoder().encode(HotKeyConfiguration.acceptanceTranslate)
    {
      defaults.set(data, forKey: "translateHotKey")
    }
    if defaults.data(forKey: "ocrHotKey") == nil,
       let data = try? JSONEncoder().encode(HotKeyConfiguration.acceptanceOCR)
    {
      defaults.set(data, forKey: "ocrHotKey")
    }

    return SettingsStore(
      defaults: defaults,
      providerFileStore: ProviderSettingsFileStore(fileURL: profile.providerSettingsURL),
      allowsMockProvider: true
    )
  }

  @MainActor
  static func makeHistoryStore() -> TranslationHistoryStore {
    guard let profile = acceptanceProfile else {
      return TranslationHistoryStore()
    }

    return TranslationHistoryStore(fileURL: profile.historyURL)
  }

  @MainActor
  static func makeLoginItemCoordinator(
    acceptanceProfile profile: AcceptanceProfile? = acceptanceProfile,
    runningTests: Bool = isRunningTests,
    bundleURL: URL = Bundle.main.bundleURL,
    systemServiceFactory: @MainActor () -> LoginItemSystemServicing = {
      SystemLoginItemService()
    },
    standardDefaults: UserDefaults = .standard,
    noncanonicalDefaults: UserDefaults? = nil
  ) -> LoginItemCoordinator {
    if let profile {
      guard let defaults = UserDefaults(suiteName: profile.defaultsSuiteName) else {
        fatalError("Could not create acceptance defaults suite \(profile.defaultsSuiteName)")
      }
      return LoginItemCoordinator(systemService: IsolatedLoginItemSystemService(), defaults: defaults)
    }

    if runningTests {
      let suiteName = "io.github.tensornull.lexiray.tests.login-item.\(UUID().uuidString)"
      guard let defaults = UserDefaults(suiteName: suiteName) else {
        fatalError("Could not create isolated test defaults suite")
      }
      return LoginItemCoordinator(systemService: IsolatedLoginItemSystemService(), defaults: defaults)
    }

    guard isCanonicalInstalledApplication(bundleURL: bundleURL) else {
      let defaults = noncanonicalDefaults ?? makeIsolatedLoginItemDefaults()
      return LoginItemCoordinator(
        systemService: UnavailableLoginItemSystemService(
          message: "Start at login is available only from /Applications/LexiRay.app."
        ),
        defaults: defaults
      )
    }

    return LoginItemCoordinator(
      systemService: systemServiceFactory(),
      defaults: standardDefaults
    )
  }

  static func isCanonicalInstalledApplication(bundleURL: URL = Bundle.main.bundleURL) -> Bool {
    bundleURL.standardizedFileURL.resolvingSymlinksInPath().path
      == canonicalApplicationURL.standardizedFileURL.resolvingSymlinksInPath().path
  }

  private static func makeIsolatedLoginItemDefaults() -> UserDefaults {
    let suiteName = "io.github.tensornull.lexiray.noncanonical.login-item.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      fatalError("Could not create isolated noncanonical login item defaults suite")
    }
    return defaults
  }
}
