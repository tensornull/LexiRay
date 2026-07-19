import AppKit
import CoreGraphics
import Darwin
import Foundation

public enum Installer {
  private static let destination = URL(fileURLWithPath: "/Applications/LexiRay.app", isDirectory: true)

  @discardableResult
  public static func install(
    repository: Repository,
    source: URL?,
    retryOf: String?,
    rootCause: String?
  ) throws -> URL {
    let source = (source ?? repository.root.appendingPathComponent("build/DerivedData/Build/Products/Debug/LexiRay.app"))
      .standardizedFileURL
    let relativeSource = source.path.hasPrefix(repository.root.path + "/")
      ? String(source.path.dropFirst(repository.root.path.count + 1))
      : source.path
    let command = "install --source \(relativeSource)"
    let evidence = EvidenceStore(repository: repository)
    do {
      try validateApp(source)
      _ = try SigningIdentityVerifier.verify(
        app: source, repository: repository, allowed: SigningIdentityContract.installable
      )
      try stopInstalledApp(repository: repository)

      let suffix = UUID().uuidString.lowercased()
      let stage = URL(fileURLWithPath: "/Applications/.LexiRay.install-\(suffix).app", isDirectory: true)
      let manager = FileManager.default
      defer { try? manager.removeItem(at: stage) }

      try manager.copyItem(at: source, to: stage)
      try validateApp(stage)
      _ = try SigningIdentityVerifier.verify(
        app: stage, repository: repository, allowed: SigningIdentityContract.installable
      )
      if manager.fileExists(atPath: destination.path) {
        try atomicExchange(stage, destination)
        do {
          try validateApp(destination)
          _ = try SigningIdentityVerifier.verify(
            app: destination, repository: repository, allowed: SigningIdentityContract.installable
          )
        } catch {
          do {
            try atomicExchange(stage, destination)
          } catch let rollbackError {
            throw OpsError.failed("install validation failed and atomic rollback failed: \(error); \(rollbackError)")
          }
          throw error
        }
      } else {
        try atomicMove(stage, destination)
        do {
          try validateApp(destination)
          _ = try SigningIdentityVerifier.verify(
            app: destination, repository: repository, allowed: SigningIdentityContract.installable
          )
        } catch {
          try? manager.removeItem(at: destination)
          throw error
        }
      }

      let identity = try appIdentity(destination, repository: repository)
      return try evidence.write(
        command: command,
        scenarios: ["install-identity"],
        result: "passed",
        rootCause: rootCause,
        retryOf: retryOf,
        log: identity
      )
    } catch {
      let message = String(describing: error)
      if let failureURL = try? evidence.write(
        command: command,
        scenarios: ["install-identity"],
        result: "failed",
        rootCause: rootCause,
        retryOf: retryOf,
        log: message
      ) {
        throw OpsError.failed("\(message)\ninstall failure evidence: \(failureURL.path)")
      }
      throw error
    }
  }

  public static func validateInstalledApp(repository: Repository) throws -> String {
    try validateApp(destination)
    _ = try SigningIdentityVerifier.verify(
      app: destination,
      repository: repository,
      allowed: SigningIdentityContract.installable
    )
    return try appIdentity(destination, repository: repository)
  }

  static func atomicExchange(_ first: URL, _ second: URL) throws {
    let status = first.path.withCString { firstPath in
      second.path.withCString { secondPath in
        renameatx_np(AT_FDCWD, firstPath, AT_FDCWD, secondPath, UInt32(RENAME_SWAP))
      }
    }
    guard status == 0 else {
      throw OpsError.failed("atomic app exchange failed: \(String(cString: strerror(errno)))")
    }
  }

  static func atomicMove(_ source: URL, _ destination: URL) throws {
    let status = source.path.withCString { sourcePath in
      destination.path.withCString { destinationPath in rename(sourcePath, destinationPath) }
    }
    guard status == 0 else {
      throw OpsError.failed("atomic app move failed: \(String(cString: strerror(errno)))")
    }
  }

  private static func validateApp(_ url: URL) throws {
    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values.isDirectory == true, values.isSymbolicLink != true else {
      throw OpsError.failed("app bundle is missing, not a directory, or symlinked: \(url.path)")
    }
    let plist = url.appendingPathComponent("Contents/Info.plist")
    let object = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), options: [], format: nil)
    guard let info = object as? [String: Any],
          info["CFBundleIdentifier"] as? String == "io.github.tensornull.lexiray",
          info["CFBundleExecutable"] as? String == "LexiRay"
    else { throw OpsError.failed("unexpected app identity at \(url.path)") }
    let executable = url.appendingPathComponent("Contents/MacOS/LexiRay")
    guard FileManager.default.isExecutableFile(atPath: executable.path) else {
      throw OpsError.failed("LexiRay executable is missing: \(executable.path)")
    }
  }

  private static func stopInstalledApp(repository: Repository) throws {
    let lookup = try ProcessRunner.run(
      "/usr/bin/pgrep", ["-x", "LexiRay"], cwd: repository.root,
      capture: true, allowedExitCodes: [0, 1]
    )
    guard lookup.status == 0 else { return }
    let expected = destination.appendingPathComponent("Contents/MacOS/LexiRay").path
    for line in lookup.output.split(separator: "\n") {
      guard let pid = Int32(line.trimmingCharacters(in: .whitespacesAndNewlines)) else { continue }
      let command = try ProcessRunner.run(
        "/bin/ps", ["-p", String(pid), "-o", "command="], cwd: repository.root,
        capture: true, allowedExitCodes: [0, 1]
      ).output.trimmingCharacters(in: .whitespacesAndNewlines)
      if command == expected || command.hasPrefix(expected + " ") {
        _ = try ProcessRunner.run("/bin/kill", [String(pid)], cwd: repository.root, capture: true, allowedExitCodes: [0, 1])
      }
    }
  }

  private static func appIdentity(_ url: URL, repository: Repository) throws -> String {
    let plist = url.appendingPathComponent("Contents/Info.plist")
    let object = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), options: [], format: nil)
    let info = object as? [String: Any] ?? [:]
    let executable = url.appendingPathComponent("Contents/MacOS/LexiRay")
    let digest = try Data(contentsOf: executable).sha256
    let signature = try ProcessRunner.capture("/usr/bin/codesign", ["-dvvv", url.path], cwd: repository.root)
    let signatureLines = signature.split(separator: "\n").filter {
      $0.hasPrefix("Identifier=") || $0.hasPrefix("Authority=") || $0.hasPrefix("CDHash=")
    }
    return [
      "path=\(url.path)",
      "bundle_id=\(info["CFBundleIdentifier"] ?? "")",
      "version=\(info["CFBundleShortVersionString"] ?? "")",
      "build=\(info["CFBundleVersion"] ?? "")",
      "executable_sha256=\(digest)"
    ].joined(separator: "\n") + "\n" + signatureLines.joined(separator: "\n")
  }
}

public struct AcceptanceLaunch: Sendable {
  public let processIdentifier: Int32
  public let scenario: String
}

private struct OwnedAcceptanceProcess {
  let processIdentifier: pid_t
  let arguments: [String]
  let dataRoot: URL
  let defaultsSuite: String
}

public enum AcceptanceRecorder {
  private static let destination = URL(fileURLWithPath: "/Applications/LexiRay.app", isDirectory: true)
  private static let executable = destination.appendingPathComponent("Contents/MacOS/LexiRay")
  private static let markerContents = "LexiRay acceptance root v1\n"

  public static func launch(repository: Repository, scenario: String) throws -> AcceptanceLaunch {
    try validateScenario(scenario)
    _ = try Installer.validateInstalledApp(repository: repository)
    guard NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.tensornull.lexiray")
      .allSatisfy(\.isTerminated)
    else { throw OpsError.failed("acceptance launch requires no running LexiRay instance") }

    let runID = UUID().uuidString.lowercased()
    let dataRoot = repository.root.appendingPathComponent("build/acceptance-data/\(runID)", isDirectory: true)
    let defaultsSuite = "io.github.tensornull.lexiray.acceptance.\(runID)"
    try seedAcceptanceData(repository: repository, dataRoot: dataRoot)

    let process = Process()
    process.executableURL = executable
    process.arguments = expectedArguments(
      repository: repository, dataRoot: dataRoot, defaultsSuite: defaultsSuite, scenario: scenario
    )
    process.currentDirectoryURL = repository.root
    process.environment = isolatedEnvironment(dataRoot: dataRoot)
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      RunLoop.current.run(until: Date().addingTimeInterval(0.25))
      guard process.isRunning else { throw OpsError.failed("installed acceptance app exited during launch") }
    } catch {
      try? FileManager.default.removeItem(at: dataRoot)
      throw error
    }
    return AcceptanceLaunch(processIdentifier: process.processIdentifier, scenario: scenario)
  }

  @discardableResult
  public static func record(
    repository: Repository,
    scenario: String,
    result: String,
    processIdentifier: Int32,
    retryOf: String?,
    rootCause: String?
  ) throws -> URL {
    try validateScenario(scenario)
    guard ["passed", "failed", "blocked"].contains(result) else {
      throw OpsError.usage("accept record --result must be passed, failed, or blocked")
    }
    guard processIdentifier > 0 else { throw OpsError.usage("accept record --pid must be a positive integer") }

    let store = EvidenceStore(repository: repository)
    let command = "accept \(scenario)"
    var ownership: OwnedAcceptanceProcess?
    var captures: [URL] = []
    do {
      let validated = try validateOwnership(
        repository: repository,
        scenario: scenario,
        processIdentifier: pid_t(processIdentifier)
      )
      ownership = validated
      let identity = try Installer.validateInstalledApp(repository: repository)
      if result == "passed" {
        captures = try captureOwnedWindows(repository: repository, ownership: validated, scenario: scenario)
        guard !captures.isEmpty else {
          throw OpsError.failed("passed acceptance requires at least one live PID-owned window capture")
        }
      } else if CGPreflightScreenCaptureAccess() {
        captures = (try? captureOwnedWindows(
          repository: repository, ownership: validated, scenario: scenario
        )) ?? []
      }
      try terminate(ownership: validated)
      try cleanup(ownership: validated)
      ownership = nil
      let profileLog = [
        identity,
        "acceptance_profile=isolated",
        "data_root=build/acceptance-data/<ephemeral>",
        "defaults_suite=io.github.tensornull.lexiray.acceptance.<ephemeral>",
        "pasteboard=named-from-acceptance-suite",
        "window_captures=\(captures.count)"
      ].joined(separator: "\n")
      return try store.write(
        command: command,
        scenarios: [scenario],
        result: result,
        rootCause: rootCause,
        retryOf: retryOf,
        log: profileLog,
        artifactURLs: captures
      )
    } catch {
      if let ownership {
        try? terminate(ownership: ownership)
        try? cleanup(ownership: ownership)
      }
      let message = String(describing: error)
      if let failureURL = try? store.write(
        command: command,
        scenarios: [scenario],
        result: "failed",
        rootCause: rootCause,
        retryOf: retryOf,
        log: message,
        artifactURLs: captures
      ) {
        throw OpsError.failed("\(message)\nacceptance failure evidence: \(failureURL.path)")
      }
      throw error
    }
  }

  private static func validateScenario(_ scenario: String) throws {
    guard !scenario.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          scenario.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil
    else { throw OpsError.usage("acceptance scenario must use lowercase letters, digits, and hyphens") }
  }

  private static func expectedArguments(
    repository: Repository,
    dataRoot: URL,
    defaultsSuite: String,
    scenario: String
  ) -> [String] {
    [
      "--lexiray-system-acceptance",
      "--lexiray-acceptance-profile",
      "--lexiray-acceptance-workspace-root", repository.root.path,
      "--lexiray-acceptance-root", dataRoot.path,
      "--lexiray-acceptance-defaults-suite", defaultsSuite,
      "--lexiray-acceptance-scenario", scenario
    ]
  }

  private static func isolatedEnvironment(dataRoot: URL) -> [String: String] {
    let preferencesHome = dataRoot.appendingPathComponent("preferences-home", isDirectory: true).path
    return [
      "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
      "HOME": preferencesHome,
      "CFFIXED_USER_HOME": preferencesHome,
      "CFPREFERENCES_AVOID_DAEMON": "1",
      "LANG": "en_US.UTF-8",
      "TMPDIR": FileManager.default.temporaryDirectory.path
    ]
  }

  private static func seedAcceptanceData(repository: Repository, dataRoot: URL) throws {
    let manager = FileManager.default
    try manager.createDirectory(at: dataRoot, withIntermediateDirectories: true)
    try manager.createDirectory(
      at: dataRoot.appendingPathComponent("preferences-home", isDirectory: true),
      withIntermediateDirectories: true
    )
    try markerContents.write(
      to: dataRoot.appendingPathComponent(".lexiray-acceptance-root"),
      atomically: true,
      encoding: .utf8
    )
    for name in ["providers.json", "history.json"] {
      try manager.copyItem(
        at: repository.root.appendingPathComponent("Tools/LexiRayGUI/fixtures/\(name)"),
        to: dataRoot.appendingPathComponent(name)
      )
    }
  }

  private static func validateOwnership(
    repository: Repository,
    scenario: String,
    processIdentifier: pid_t
  ) throws -> OwnedAcceptanceProcess {
    let context = try processContext(processIdentifier: processIdentifier)
    guard let argumentZero = context.arguments.first,
          URL(fileURLWithPath: argumentZero).standardizedFileURL.resolvingSymlinksInPath().path
            == executable.standardizedFileURL.resolvingSymlinksInPath().path
    else { throw OpsError.failed("acceptance PID is not the installed LexiRay executable") }

    let appArguments = Array(context.arguments.dropFirst())
    let rawDataRoot = try appArguments.value(after: "--lexiray-acceptance-root")
    let defaultsSuite = try appArguments.value(after: "--lexiray-acceptance-defaults-suite")
    let dataRoot = URL(fileURLWithPath: rawDataRoot, isDirectory: true)
      .standardizedFileURL
      .resolvingSymlinksInPath()
    let expected = expectedArguments(
      repository: repository, dataRoot: dataRoot, defaultsSuite: defaultsSuite, scenario: scenario
    )
    guard appArguments == expected else {
      throw OpsError.failed("acceptance PID arguments do not match the requested isolated scenario")
    }

    let base = repository.root.appendingPathComponent("build/acceptance-data", isDirectory: true)
      .standardizedFileURL
      .resolvingSymlinksInPath()
    let preferencesHome = dataRoot.appendingPathComponent("preferences-home", isDirectory: true)
      .standardizedFileURL
      .resolvingSymlinksInPath()
    guard dataRoot.path.hasPrefix(base.path + "/"),
          defaultsSuite == "io.github.tensornull.lexiray.acceptance.\(dataRoot.lastPathComponent)",
          context.environment["HOME"] == preferencesHome.path,
          context.environment["CFFIXED_USER_HOME"] == preferencesHome.path,
          context.environment["CFPREFERENCES_AVOID_DAEMON"] == "1",
          try regularDirectory(dataRoot),
          try regularDirectory(preferencesHome),
          try regularFile(dataRoot.appendingPathComponent("providers.json")),
          try regularFile(dataRoot.appendingPathComponent("history.json")),
          try regularFile(dataRoot.appendingPathComponent(".lexiray-acceptance-root")),
          try String(
            contentsOf: dataRoot.appendingPathComponent(".lexiray-acceptance-root"), encoding: .utf8
          ) == markerContents
    else { throw OpsError.failed("acceptance PID does not own a safe isolated acceptance profile") }

    _ = try Installer.validateInstalledApp(repository: repository)
    return OwnedAcceptanceProcess(
      processIdentifier: processIdentifier,
      arguments: context.arguments,
      dataRoot: dataRoot,
      defaultsSuite: defaultsSuite
    )
  }

  private static func regularDirectory(_ url: URL) throws -> Bool {
    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    return values.isDirectory == true && values.isSymbolicLink != true
  }

  private static func regularFile(_ url: URL) throws -> Bool {
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    return values.isRegularFile == true && values.isSymbolicLink != true
  }

  private static func captureOwnedWindows(
    repository: Repository,
    ownership: OwnedAcceptanceProcess,
    scenario: String
  ) throws -> [URL] {
    guard CGPreflightScreenCaptureAccess() else {
      throw OpsError.failed("Computer Use capture requires Screen Recording permission")
    }
    guard let windows = CGWindowListCopyWindowInfo(
      [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
    ) as? [[String: Any]] else { throw OpsError.failed("could not enumerate installed acceptance windows") }
    let identifiers = windows.compactMap { window -> Int? in
      guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == ownership.processIdentifier,
            (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
            (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0
      else { return nil }
      return (window[kCGWindowNumber as String] as? NSNumber)?.intValue
    }.sorted()

    let directory = repository.root.appendingPathComponent(
      "build/acceptance-artifacts/\(UUID().uuidString.lowercased())", isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var captures: [URL] = []
    for (index, identifier) in identifiers.enumerated() {
      let output = directory.appendingPathComponent("\(scenario)-window-\(index + 1).png")
      try ProcessRunner.run(
        "/usr/sbin/screencapture", ["-x", "-o", "-l", String(identifier), output.path],
        cwd: repository.root
      )
      if try regularFile(output) { captures.append(output) }
    }
    return captures
  }

  private static func terminate(ownership: OwnedAcceptanceProcess) throws {
    let current = try processContext(processIdentifier: ownership.processIdentifier)
    guard current.arguments == ownership.arguments else {
      throw OpsError.failed("acceptance PID changed identity before termination")
    }
    guard kill(ownership.processIdentifier, SIGTERM) == 0 else {
      if errno == ESRCH { return }
      throw OpsError.failed("could not terminate the owned acceptance process")
    }
    for _ in 0 ..< 30 {
      if kill(ownership.processIdentifier, 0) != 0, errno == ESRCH { return }
      usleep(100_000)
    }
    let final = try processContext(processIdentifier: ownership.processIdentifier)
    guard final.arguments == ownership.arguments else {
      throw OpsError.failed("acceptance PID changed identity before forced termination")
    }
    guard kill(ownership.processIdentifier, SIGKILL) == 0 || errno == ESRCH else {
      throw OpsError.failed("could not force-terminate the owned acceptance process")
    }
  }

  private static func cleanup(ownership: OwnedAcceptanceProcess) throws {
    if FileManager.default.fileExists(atPath: ownership.dataRoot.path) {
      try FileManager.default.removeItem(at: ownership.dataRoot)
    }
    UserDefaults(suiteName: ownership.defaultsSuite)?
      .removePersistentDomain(forName: ownership.defaultsSuite)
  }

  private static func processContext(
    processIdentifier: pid_t
  ) throws -> (arguments: [String], environment: [String: String]) {
    var mib = [CTL_KERN, KERN_PROCARGS2, processIdentifier]
    var byteCount = 0
    guard sysctl(&mib, u_int(mib.count), nil, &byteCount, nil, 0) == 0,
          byteCount > MemoryLayout<Int32>.size
    else { throw OpsError.failed("acceptance PID is not live or inspectable") }

    var bytes = [UInt8](repeating: 0, count: byteCount)
    let result = bytes.withUnsafeMutableBytes { buffer in
      sysctl(&mib, u_int(mib.count), buffer.baseAddress, &byteCount, nil, 0)
    }
    guard result == 0 else { throw OpsError.failed("acceptance PID is not live or inspectable") }

    var argumentCount: Int32 = 0
    withUnsafeMutableBytes(of: &argumentCount) { destination in
      bytes.withUnsafeBytes { source in
        destination.copyBytes(from: source.prefix(MemoryLayout<Int32>.size))
      }
    }
    guard argumentCount > 0 else { throw OpsError.failed("acceptance PID has no inspectable arguments") }

    var index = MemoryLayout<Int32>.size
    while index < byteCount, bytes[index] != 0 { index += 1 }
    while index < byteCount, bytes[index] == 0 { index += 1 }
    var arguments: [String] = []
    while index < byteCount, arguments.count < Int(argumentCount) {
      let start = index
      while index < byteCount, bytes[index] != 0 { index += 1 }
      guard index > start else { throw OpsError.failed("acceptance PID arguments are malformed") }
      arguments.append(String(decoding: bytes[start ..< index], as: UTF8.self))
      while index < byteCount, bytes[index] == 0 { index += 1 }
    }
    guard arguments.count == Int(argumentCount) else {
      throw OpsError.failed("acceptance PID arguments are incomplete")
    }

    var environment: [String: String] = [:]
    while index < byteCount {
      while index < byteCount, bytes[index] == 0 { index += 1 }
      let start = index
      while index < byteCount, bytes[index] != 0 { index += 1 }
      guard index > start else { continue }
      let entry = String(decoding: bytes[start ..< index], as: UTF8.self)
      if let separator = entry.firstIndex(of: "=") {
        environment[String(entry[..<separator])] = String(entry[entry.index(after: separator)...])
      }
    }
    return (arguments, environment)
  }
}
