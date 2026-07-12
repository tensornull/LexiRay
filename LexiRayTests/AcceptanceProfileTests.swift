@testable import LexiRay
import XCTest

@MainActor
final class AcceptanceProfileTests: XCTestCase {
  func testDisabledProfileDoesNotRequireAcceptanceConfiguration() throws {
    let profile = try AcceptanceProfile.resolve(environment: [:], arguments: [])

    XCTAssertNil(profile)
  }

  func testProfileUsesIndependentDataAndDefaults() throws {
    let paths = try makeAcceptanceRoot()
    let profile = try XCTUnwrap(
      AcceptanceProfile.resolve(
        environment: acceptanceEnvironment(paths: paths),
        arguments: [],
        homeDirectory: paths.container.appending(path: "home", directoryHint: .isDirectory)
      )
    )

    XCTAssertEqual(profile.providerSettingsURL, paths.dataRoot.appending(path: "providers.json"))
    XCTAssertEqual(profile.historyURL, paths.dataRoot.appending(path: "history.json"))
    XCTAssertNotEqual(profile.defaultsSuiteName, AppConstants.bundleID)
    XCTAssertEqual(
      AppRuntime.makePasteboard(acceptanceProfile: profile).name.rawValue,
      "\(profile.defaultsSuiteName).pasteboard"
    )
  }

  func testInstalledAcceptanceProfilePresentsMainWindowButUIRunnerDoesNot() throws {
    let paths = try makeAcceptanceRoot(name: "main-window")
    let profile = try XCTUnwrap(
      AcceptanceProfile.resolve(
        environment: acceptanceEnvironment(paths: paths),
        arguments: [],
        homeDirectory: paths.container.appending(path: "home", directoryHint: .isDirectory)
      )
    )

    XCTAssertTrue(
      AppRuntime.shouldPresentMainWindowAtLaunch(
        acceptanceProfile: profile,
        isRunningUIScenarios: false
      )
    )
    XCTAssertFalse(
      AppRuntime.shouldPresentMainWindowAtLaunch(
        acceptanceProfile: profile,
        isRunningUIScenarios: true
      )
    )
    XCTAssertFalse(
      AppRuntime.shouldPresentMainWindowAtLaunch(
        acceptanceProfile: nil,
        isRunningUIScenarios: false
      )
    )
  }

  func testProfileRequiresWorkspaceRoot() throws {
    let paths = try makeAcceptanceRoot()

    XCTAssertThrowsError(
      try AcceptanceProfile.resolve(
        environment: [
          AcceptanceProfile.enabledEnvironmentKey: "1",
          AcceptanceProfile.dataRootEnvironmentKey: paths.dataRoot.path,
          AcceptanceProfile.defaultsSuiteEnvironmentKey: acceptanceSuite
        ],
        arguments: []
      )
    ) { error in
      XCTAssertEqual(error as? AcceptanceProfile.ConfigurationError, .missingWorkspaceRoot)
    }
  }

  func testProfileRejectsProductionDataRoot() {
    XCTAssertThrowsError(
      try AcceptanceProfile.resolve(
        environment: [
          AcceptanceProfile.enabledEnvironmentKey: "1",
          AcceptanceProfile.workspaceRootEnvironmentKey: "/Users/tester/workspace/LexiRay",
          AcceptanceProfile.dataRootEnvironmentKey: "/Users/tester/.lexiray",
          AcceptanceProfile.defaultsSuiteEnvironmentKey: acceptanceSuite
        ],
        arguments: [],
        homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true)
      )
    ) { error in
      XCTAssertEqual(error as? AcceptanceProfile.ConfigurationError, .unsafeDataRoot)
    }
  }

  func testProfileRejectsFilesystemRoot() {
    XCTAssertThrowsError(
      try AcceptanceProfile.resolve(
        environment: [
          AcceptanceProfile.enabledEnvironmentKey: "1",
          AcceptanceProfile.workspaceRootEnvironmentKey: "/",
          AcceptanceProfile.dataRootEnvironmentKey: "/",
          AcceptanceProfile.defaultsSuiteEnvironmentKey: acceptanceSuite
        ],
        arguments: []
      )
    ) { error in
      XCTAssertEqual(error as? AcceptanceProfile.ConfigurationError, .unsafeDataRoot)
    }
  }

  func testProfileRejectsDataRootOutsideWorkspaceAcceptanceBase() throws {
    let paths = try makeAcceptanceRoot()
    let outside = paths.container.appending(path: "Documents", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try AcceptanceProfile.markerContents.write(
      to: outside.appending(path: AcceptanceProfile.markerFileName),
      atomically: true,
      encoding: .utf8
    )

    var environment = acceptanceEnvironment(paths: paths)
    environment[AcceptanceProfile.dataRootEnvironmentKey] = outside.path
    XCTAssertThrowsError(try AcceptanceProfile.resolve(environment: environment, arguments: [])) { error in
      XCTAssertEqual(error as? AcceptanceProfile.ConfigurationError, .unsafeDataRoot)
    }
  }

  func testProfileRejectsMissingAcceptanceMarker() throws {
    let paths = try makeAcceptanceRoot()
    try FileManager.default.removeItem(
      at: paths.dataRoot.appending(path: AcceptanceProfile.markerFileName)
    )

    XCTAssertThrowsError(
      try AcceptanceProfile.resolve(environment: acceptanceEnvironment(paths: paths), arguments: [])
    ) { error in
      XCTAssertEqual(error as? AcceptanceProfile.ConfigurationError, .unsafeDataRoot)
    }
  }

  func testProfileRejectsSymlinkedFixtureFile() throws {
    let paths = try makeAcceptanceRoot()
    let providerURL = paths.dataRoot.appending(path: "providers.json")
    let outside = paths.container.appending(path: "outside-providers.json")
    try Data("{}\n".utf8).write(to: outside)
    try FileManager.default.removeItem(at: providerURL)
    try FileManager.default.createSymbolicLink(at: providerURL, withDestinationURL: outside)

    XCTAssertThrowsError(
      try AcceptanceProfile.resolve(environment: acceptanceEnvironment(paths: paths), arguments: [])
    ) { error in
      XCTAssertEqual(error as? AcceptanceProfile.ConfigurationError, .unsafeDataRoot)
    }
  }

  func testProfileRejectsProductionDefaultsSuite() throws {
    let paths = try makeAcceptanceRoot()
    var environment = acceptanceEnvironment(paths: paths)
    environment[AcceptanceProfile.defaultsSuiteEnvironmentKey] = AppConstants.bundleID

    XCTAssertThrowsError(try AcceptanceProfile.resolve(environment: environment, arguments: [])) { error in
      XCTAssertEqual(error as? AcceptanceProfile.ConfigurationError, .productionDefaultsSuite)
    }
  }

  func testProfileRejectsArbitraryDefaultsSuite() throws {
    let paths = try makeAcceptanceRoot()
    var environment = acceptanceEnvironment(paths: paths)
    environment[AcceptanceProfile.defaultsSuiteEnvironmentKey] = "NSGlobalDomain"

    XCTAssertThrowsError(try AcceptanceProfile.resolve(environment: environment, arguments: [])) { error in
      XCTAssertEqual(error as? AcceptanceProfile.ConfigurationError, .unsafeDefaultsSuite)
    }
  }

  func testProfileRejectsDescendantOfProductionDataRoot() {
    XCTAssertThrowsError(
      try AcceptanceProfile.resolve(
        environment: [
          AcceptanceProfile.enabledEnvironmentKey: "1",
          AcceptanceProfile.workspaceRootEnvironmentKey: "/Users/tester/.lexiray",
          AcceptanceProfile.dataRootEnvironmentKey: "/Users/tester/.lexiray/build/acceptance-data/run",
          AcceptanceProfile.defaultsSuiteEnvironmentKey: acceptanceSuite
        ],
        arguments: [],
        homeDirectory: URL(fileURLWithPath: "/Users/tester", isDirectory: true)
      )
    ) { error in
      XCTAssertEqual(error as? AcceptanceProfile.ConfigurationError, .unsafeDataRoot)
    }
  }

  func testProfileRejectsSymlinkToProductionDataRoot() throws {
    let container = FileManager.default.temporaryDirectory
      .appending(path: "lexiray-acceptance-link-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let workspace = container.appending(path: "workspace", directoryHint: .isDirectory)
    let acceptanceBase = workspace.appending(path: "build/acceptance-data", directoryHint: .isDirectory)
    let home = container.appending(path: "home", directoryHint: .isDirectory)
    let production = home.appending(path: ".lexiray", directoryHint: .isDirectory)
    let alias = acceptanceBase.appending(path: "run", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: acceptanceBase, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: production, withIntermediateDirectories: true)
    try AcceptanceProfile.markerContents.write(
      to: production.appending(path: AcceptanceProfile.markerFileName),
      atomically: true,
      encoding: .utf8
    )
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: production)
    defer { try? FileManager.default.removeItem(at: container) }

    XCTAssertThrowsError(
      try AcceptanceProfile.resolve(
        environment: [
          AcceptanceProfile.enabledEnvironmentKey: "1",
          AcceptanceProfile.workspaceRootEnvironmentKey: workspace.path,
          AcceptanceProfile.dataRootEnvironmentKey: alias.path,
          AcceptanceProfile.defaultsSuiteEnvironmentKey: acceptanceSuite
        ],
        arguments: [],
        homeDirectory: home
      )
    ) { error in
      XCTAssertEqual(error as? AcceptanceProfile.ConfigurationError, .unsafeDataRoot)
    }
  }

  func testProfileRejectsProductionDataRootSymlinkToAcceptanceRoot() throws {
    let paths = try makeAcceptanceRoot(name: "production-link")
    let home = paths.container.appending(path: "home", directoryHint: .isDirectory)
    let production = home.appending(path: ".lexiray", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: production, withDestinationURL: paths.dataRoot)

    XCTAssertThrowsError(
      try AcceptanceProfile.resolve(
        environment: acceptanceEnvironment(paths: paths),
        arguments: [],
        homeDirectory: home
      )
    ) { error in
      XCTAssertEqual(error as? AcceptanceProfile.ConfigurationError, .unsafeDataRoot)
    }
  }

  func testProfileCanBeConfiguredWithLaunchArguments() throws {
    let paths = try makeAcceptanceRoot(name: "installed")
    let profile = try XCTUnwrap(
      AcceptanceProfile.resolve(
        environment: [:],
        arguments: [
          AcceptanceProfile.enabledArgument,
          AcceptanceProfile.workspaceRootArgument, paths.workspace.path,
          AcceptanceProfile.dataRootArgument, paths.dataRoot.path,
          AcceptanceProfile.defaultsSuiteArgument + "=io.github.tensornull.lexiray.acceptance.installed"
        ]
      )
    )

    XCTAssertEqual(profile.dataRoot, paths.dataRoot.resolvingSymlinksInPath())
    XCTAssertEqual(profile.defaultsSuiteName, "io.github.tensornull.lexiray.acceptance.installed")
  }

  func testProfileAcceptsMatchingEnvironmentAndLaunchArguments() throws {
    let paths = try makeAcceptanceRoot(name: "matching")
    let suite = "io.github.tensornull.lexiray.acceptance.matching"
    let profile = try XCTUnwrap(
      AcceptanceProfile.resolve(
        environment: [
          AcceptanceProfile.enabledEnvironmentKey: "1",
          AcceptanceProfile.workspaceRootEnvironmentKey: paths.workspace.path,
          AcceptanceProfile.dataRootEnvironmentKey: paths.dataRoot.path,
          AcceptanceProfile.defaultsSuiteEnvironmentKey: suite,
          AcceptanceProfile.selectionFixturePIDEnvironmentKey: "4321"
        ],
        arguments: [
          AcceptanceProfile.enabledArgument,
          AcceptanceProfile.workspaceRootArgument, paths.workspace.path,
          AcceptanceProfile.dataRootArgument, paths.dataRoot.path,
          AcceptanceProfile.defaultsSuiteArgument, suite,
          AcceptanceProfile.selectionFixturePIDArgument, "4321"
        ]
      )
    )

    XCTAssertEqual(profile.dataRoot, paths.dataRoot.resolvingSymlinksInPath())
    XCTAssertEqual(profile.defaultsSuiteName, suite)
    XCTAssertEqual(profile.selectionFixtureProcessIdentifier, 4321)
  }

  func testProfileRejectsConflictingEnvironmentAndLaunchArguments() throws {
    let current = try makeAcceptanceRoot(name: "current")
    let stale = try makeAcceptanceRoot(name: "stale")
    let suite = "io.github.tensornull.lexiray.acceptance.current"
    let arguments = [
      AcceptanceProfile.enabledArgument,
      AcceptanceProfile.workspaceRootArgument, current.workspace.path,
      AcceptanceProfile.dataRootArgument, current.dataRoot.path,
      AcceptanceProfile.defaultsSuiteArgument, suite,
      AcceptanceProfile.selectionFixturePIDArgument, "4321"
    ]
    let matchingEnvironment = [
      AcceptanceProfile.enabledEnvironmentKey: "1",
      AcceptanceProfile.workspaceRootEnvironmentKey: current.workspace.path,
      AcceptanceProfile.dataRootEnvironmentKey: current.dataRoot.path,
      AcceptanceProfile.defaultsSuiteEnvironmentKey: suite,
      AcceptanceProfile.selectionFixturePIDEnvironmentKey: "4321"
    ]
    let conflicts = [
      (AcceptanceProfile.workspaceRootEnvironmentKey, stale.workspace.path, AcceptanceProfile.workspaceRootArgument),
      (AcceptanceProfile.dataRootEnvironmentKey, stale.dataRoot.path, AcceptanceProfile.dataRootArgument),
      (
        AcceptanceProfile.defaultsSuiteEnvironmentKey,
        "io.github.tensornull.lexiray.acceptance.stale",
        AcceptanceProfile.defaultsSuiteArgument
      ),
      (AcceptanceProfile.selectionFixturePIDEnvironmentKey, "9876", AcceptanceProfile.selectionFixturePIDArgument)
    ]

    for (environmentKey, staleValue, expectedArgument) in conflicts {
      var environment = matchingEnvironment
      environment[environmentKey] = staleValue

      XCTAssertThrowsError(
        try AcceptanceProfile.resolve(environment: environment, arguments: arguments),
        "Expected a conflict for \(expectedArgument)"
      ) { error in
        XCTAssertEqual(
          error as? AcceptanceProfile.ConfigurationError,
          .conflictingConfiguration(expectedArgument)
        )
      }
    }
  }

  func testProfileRejectsConflictingEnablementSources() {
    XCTAssertThrowsError(
      try AcceptanceProfile.resolve(
        environment: [AcceptanceProfile.enabledEnvironmentKey: "0"],
        arguments: [AcceptanceProfile.enabledArgument]
      )
    ) { error in
      XCTAssertEqual(
        error as? AcceptanceProfile.ConfigurationError,
        .conflictingConfiguration(AcceptanceProfile.enabledArgument)
      )
    }
  }

  func testProfileAcceptsOnlyPositiveSelectionFixturePID() throws {
    let paths = try makeAcceptanceRoot()
    var environment = acceptanceEnvironment(paths: paths)
    environment[AcceptanceProfile.selectionFixturePIDEnvironmentKey] = "4321"

    let profile = try XCTUnwrap(AcceptanceProfile.resolve(environment: environment, arguments: []))
    XCTAssertEqual(profile.selectionFixtureProcessIdentifier, 4321)

    environment[AcceptanceProfile.selectionFixturePIDEnvironmentKey] = "0"
    XCTAssertThrowsError(try AcceptanceProfile.resolve(environment: environment, arguments: [])) { error in
      XCTAssertEqual(
        error as? AcceptanceProfile.ConfigurationError,
        .unsafeSelectionFixtureProcessIdentifier
      )
    }

    environment[AcceptanceProfile.selectionFixturePIDEnvironmentKey] = "not-a-pid"
    XCTAssertThrowsError(try AcceptanceProfile.resolve(environment: environment, arguments: [])) { error in
      XCTAssertEqual(
        error as? AcceptanceProfile.ConfigurationError,
        .unsafeSelectionFixtureProcessIdentifier
      )
    }
  }

  func testAcceptanceStoresWriteOnlyToIsolatedPaths() throws {
    let paths = try makeAcceptanceRoot()
    let home = paths.container.appending(path: "home", directoryHint: .isDirectory)
    let productionRoot = home.appending(path: ".lexiray", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: productionRoot, withIntermediateDirectories: true)

    let productionProviders = productionRoot.appending(path: "providers.json")
    let productionHistory = productionRoot.appending(path: "history.json")
    let providerSentinel = Data("real-provider-sentinel".utf8)
    let historySentinel = Data("real-history-sentinel".utf8)
    try providerSentinel.write(to: productionProviders)
    try historySentinel.write(to: productionHistory)

    let profile = try XCTUnwrap(
      AcceptanceProfile.resolve(
        environment: acceptanceEnvironment(paths: paths),
        arguments: [],
        homeDirectory: home
      )
    )
    let defaults = try XCTUnwrap(UserDefaults(suiteName: profile.defaultsSuiteName))
    defer { defaults.removePersistentDomain(forName: profile.defaultsSuiteName) }

    let settings = SettingsStore(
      defaults: defaults,
      providerFileStore: ProviderSettingsFileStore(fileURL: profile.providerSettingsURL),
      allowsMockProvider: true
    )
    settings.showsMenuBarIcon.toggle()
    TranslationHistoryStore(fileURL: profile.historyURL).save([], limit: 10)

    XCTAssertTrue(FileManager.default.fileExists(atPath: profile.providerSettingsURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: profile.historyURL.path))
    XCTAssertEqual(try Data(contentsOf: productionProviders), providerSentinel)
    XCTAssertEqual(try Data(contentsOf: productionHistory), historySentinel)
  }

  private let acceptanceSuite = "io.github.tensornull.lexiray.acceptance.tests"

  private func acceptanceEnvironment(
    paths: (container: URL, workspace: URL, dataRoot: URL)
  ) -> [String: String] {
    [
      AcceptanceProfile.enabledEnvironmentKey: "1",
      AcceptanceProfile.workspaceRootEnvironmentKey: paths.workspace.path,
      AcceptanceProfile.dataRootEnvironmentKey: paths.dataRoot.path,
      AcceptanceProfile.defaultsSuiteEnvironmentKey: acceptanceSuite + ".\(UUID().uuidString)"
    ]
  }

  private func makeAcceptanceRoot(
    name: String = "run"
  ) throws -> (container: URL, workspace: URL, dataRoot: URL) {
    let container = FileManager.default.temporaryDirectory
      .appending(path: "lexiray-acceptance-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let workspace = container.appending(path: "workspace", directoryHint: .isDirectory)
    let dataRoot = workspace
      .appending(path: "build/acceptance-data", directoryHint: .isDirectory)
      .appending(path: name, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
    try AcceptanceProfile.markerContents.write(
      to: dataRoot.appending(path: AcceptanceProfile.markerFileName),
      atomically: true,
      encoding: .utf8
    )
    try Data("{}\n".utf8).write(to: dataRoot.appending(path: "providers.json"))
    try Data("[]\n".utf8).write(to: dataRoot.appending(path: "history.json"))
    addTeardownBlock { try? FileManager.default.removeItem(at: container) }
    return (container, workspace, dataRoot)
  }
}
