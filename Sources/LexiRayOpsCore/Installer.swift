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
      try stopInstalledApp(repository: repository)

      let suffix = UUID().uuidString.lowercased()
      let stage = URL(fileURLWithPath: "/Applications/.LexiRay.install-\(suffix).app", isDirectory: true)
      let backup = URL(fileURLWithPath: "/Applications/.LexiRay.backup-\(suffix).app", isDirectory: true)
      let manager = FileManager.default
      defer {
        try? manager.removeItem(at: stage)
        try? manager.removeItem(at: backup)
      }

      try manager.copyItem(at: source, to: stage)
      try validateApp(stage)
      var movedOld = false
      do {
        if manager.fileExists(atPath: destination.path) {
          try manager.moveItem(at: destination, to: backup)
          movedOld = true
        }
        try manager.moveItem(at: stage, to: destination)
        try validateApp(destination)
        try ProcessRunner.run(
          "/usr/bin/codesign", ["--verify", "--deep", "--strict", destination.path],
          cwd: repository.root
        )
        if movedOld { try manager.removeItem(at: backup) }
      } catch {
        if manager.fileExists(atPath: destination.path) { try? manager.removeItem(at: destination) }
        if movedOld, manager.fileExists(atPath: backup.path) { try? manager.moveItem(at: backup, to: destination) }
        throw error
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
    try ProcessRunner.run(
      "/usr/bin/codesign", ["--verify", "--deep", "--strict", destination.path],
      cwd: repository.root
    )
    return try appIdentity(destination, repository: repository)
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

public enum AcceptanceRecorder {
  @discardableResult
  public static func record(
    repository: Repository,
    scenario: String,
    result: String,
    screenshots: [URL],
    retryOf: String?,
    rootCause: String?
  ) throws -> URL {
    guard ["passed", "failed", "blocked"].contains(result) else {
      throw OpsError.usage("accept --result must be passed, failed, or blocked")
    }
    if result == "passed", screenshots.isEmpty {
      throw OpsError.usage("a passed Computer Use acceptance requires at least one --screenshot")
    }
    let store = EvidenceStore(repository: repository)
    let command = "accept \(scenario)"
    do {
      let identity = try Installer.validateInstalledApp(repository: repository)
      return try store.write(
        command: command,
        scenarios: [scenario],
        result: result,
        rootCause: rootCause,
        retryOf: retryOf,
        log: identity,
        artifactURLs: screenshots
      )
    } catch {
      let message = String(describing: error)
      if let failureURL = try? store.write(
        command: command,
        scenarios: [scenario],
        result: "failed",
        rootCause: rootCause,
        retryOf: retryOf,
        log: message,
        artifactURLs: screenshots
      ) {
        throw OpsError.failed("\(message)\nacceptance failure evidence: \(failureURL.path)")
      }
      throw error
    }
  }
}
