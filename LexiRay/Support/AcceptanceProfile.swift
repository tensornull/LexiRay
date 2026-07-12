import Darwin
import Foundation

struct AcceptanceProfile: Equatable {
  enum ConfigurationError: Error, Equatable {
    case conflictingConfiguration(String)
    case missingWorkspaceRoot
    case workspaceRootMustBeAbsolute
    case missingDataRoot
    case dataRootMustBeAbsolute
    case unsafeDataRoot
    case missingDefaultsSuite
    case productionDefaultsSuite
    case unsafeDefaultsSuite
    case unsafeSelectionFixtureProcessIdentifier
  }

  static let enabledEnvironmentKey = "LEXIRAY_ACCEPTANCE_PROFILE"
  static let workspaceRootEnvironmentKey = "LEXIRAY_ACCEPTANCE_WORKSPACE_ROOT"
  static let dataRootEnvironmentKey = "LEXIRAY_ACCEPTANCE_ROOT"
  static let defaultsSuiteEnvironmentKey = "LEXIRAY_ACCEPTANCE_DEFAULTS_SUITE"
  static let selectionFixturePIDEnvironmentKey = "LEXIRAY_ACCEPTANCE_SELECTION_PID"
  static let enabledArgument = "--lexiray-acceptance-profile"
  static let workspaceRootArgument = "--lexiray-acceptance-workspace-root"
  static let dataRootArgument = "--lexiray-acceptance-root"
  static let defaultsSuiteArgument = "--lexiray-acceptance-defaults-suite"
  static let selectionFixturePIDArgument = "--lexiray-acceptance-selection-pid"
  static let markerFileName = ".lexiray-acceptance-root"
  static let markerContents = "LexiRay acceptance root v1\n"

  let dataRoot: URL
  let defaultsSuiteName: String
  let selectionFixtureProcessIdentifier: pid_t?

  var providerSettingsURL: URL {
    dataRoot.appending(path: "providers.json", directoryHint: .notDirectory)
  }

  var historyURL: URL {
    dataRoot.appending(path: "history.json", directoryHint: .notDirectory)
  }

  static func resolve(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    arguments: [String] = ProcessInfo.processInfo.arguments,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) throws -> AcceptanceProfile? {
    let hasEnabledArgument = arguments.contains(enabledArgument)
    if hasEnabledArgument,
       let environmentValue = environment[enabledEnvironmentKey],
       environmentValue != "1"
    {
      throw ConfigurationError.conflictingConfiguration(enabledArgument)
    }

    guard environment[enabledEnvironmentKey] == "1" || hasEnabledArgument else {
      return nil
    }

    guard let rawWorkspaceRoot = try resolvedValue(
      environmentKey: workspaceRootEnvironmentKey,
      argument: workspaceRootArgument,
      environment: environment,
      arguments: arguments
    ) else {
      throw ConfigurationError.missingWorkspaceRoot
    }
    guard rawWorkspaceRoot.hasPrefix("/") else {
      throw ConfigurationError.workspaceRootMustBeAbsolute
    }

    guard let rawDataRoot = try resolvedValue(
      environmentKey: dataRootEnvironmentKey,
      argument: dataRootArgument,
      environment: environment,
      arguments: arguments
    ) else {
      throw ConfigurationError.missingDataRoot
    }
    guard rawDataRoot.hasPrefix("/") else {
      throw ConfigurationError.dataRootMustBeAbsolute
    }

    guard fileType(atPath: rawDataRoot) == S_IFDIR else {
      throw ConfigurationError.unsafeDataRoot
    }

    let workspaceRoot = URL(fileURLWithPath: rawWorkspaceRoot, isDirectory: true)
      .standardizedFileURL
      .resolvingSymlinksInPath()
    let dataRoot = URL(fileURLWithPath: rawDataRoot, isDirectory: true)
      .standardizedFileURL
      .resolvingSymlinksInPath()
    let acceptanceBase = workspaceRoot
      .appending(path: "build/acceptance-data", directoryHint: .isDirectory)
      .standardizedFileURL
      .resolvingSymlinksInPath()
    let productionDataRoot = homeDirectory
      .appending(path: ".lexiray", directoryHint: .isDirectory)
      .standardizedFileURL
    let normalizedRoot = dataRoot.path
    let normalizedAcceptanceBase = acceptanceBase.path
    let productionRoot = productionDataRoot.path
    let homeRoot = homeDirectory.standardizedFileURL.path

    guard workspaceRoot.path != "/",
          normalizedRoot != "/",
          normalizedRoot.hasPrefix(normalizedAcceptanceBase + "/"),
          normalizedRoot != productionRoot,
          normalizedRoot != homeRoot,
          !normalizedRoot.hasPrefix(productionRoot + "/"),
          !productionRoot.hasPrefix(normalizedRoot + "/")
    else {
      throw ConfigurationError.unsafeDataRoot
    }

    let markerURL = dataRoot.appending(path: markerFileName, directoryHint: .notDirectory)
    let providerURL = dataRoot.appending(path: "providers.json", directoryHint: .notDirectory)
    let historyURL = dataRoot.appending(path: "history.json", directoryHint: .notDirectory)
    guard fileType(atPath: markerURL.path) == S_IFREG,
          fileType(atPath: providerURL.path) == S_IFREG,
          fileType(atPath: historyURL.path) == S_IFREG,
          (try? String(contentsOf: markerURL, encoding: .utf8)) == markerContents
    else {
      throw ConfigurationError.unsafeDataRoot
    }

    guard let defaultsSuiteName = try resolvedValue(
      environmentKey: defaultsSuiteEnvironmentKey,
      argument: defaultsSuiteArgument,
      environment: environment,
      arguments: arguments
    ) else {
      throw ConfigurationError.missingDefaultsSuite
    }
    guard defaultsSuiteName != AppConstants.bundleID else {
      throw ConfigurationError.productionDefaultsSuite
    }
    guard defaultsSuiteName.hasPrefix(AppConstants.bundleID + ".acceptance.") else {
      throw ConfigurationError.unsafeDefaultsSuite
    }

    let rawSelectionPID = try resolvedValue(
      environmentKey: selectionFixturePIDEnvironmentKey,
      argument: selectionFixturePIDArgument,
      environment: environment,
      arguments: arguments
    )
    let selectionFixtureProcessIdentifier: pid_t?
    if let rawSelectionPID {
      guard let value = pid_t(rawSelectionPID), value > 0 else {
        throw ConfigurationError.unsafeSelectionFixtureProcessIdentifier
      }
      selectionFixtureProcessIdentifier = value
    } else {
      selectionFixtureProcessIdentifier = nil
    }

    return AcceptanceProfile(
      dataRoot: dataRoot,
      defaultsSuiteName: defaultsSuiteName,
      selectionFixtureProcessIdentifier: selectionFixtureProcessIdentifier
    )
  }

  private static func fileType(atPath path: String) -> mode_t? {
    var metadata = stat()
    guard lstat(path, &metadata) == 0 else {
      return nil
    }
    return metadata.st_mode & S_IFMT
  }

  private static func resolvedValue(
    environmentKey: String,
    argument: String,
    environment: [String: String],
    arguments: [String]
  ) throws -> String? {
    let parsedArgument = argumentValue(argument, in: arguments)
    guard parsedArgument.isPresent else {
      return environment[environmentKey]?.nonEmptyTrimmed
    }

    let argumentValue = parsedArgument.value?.nonEmptyTrimmed
    if let rawEnvironmentValue = environment[environmentKey],
       rawEnvironmentValue.nonEmptyTrimmed != argumentValue
    {
      throw ConfigurationError.conflictingConfiguration(argument)
    }
    return argumentValue
  }

  private static func argumentValue(_ name: String, in arguments: [String]) -> (isPresent: Bool, value: String?) {
    if let inline = arguments.first(where: { $0.hasPrefix(name + "=") }) {
      return (true, String(inline.dropFirst(name.count + 1)))
    }

    guard let index = arguments.firstIndex(of: name) else {
      return (false, nil)
    }
    guard arguments.indices.contains(index + 1), !arguments[index + 1].hasPrefix("--") else {
      return (true, nil)
    }
    return (true, arguments[index + 1])
  }
}
