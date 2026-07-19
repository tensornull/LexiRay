import Foundation

public enum ValidationExecutor {
  public static func verifyChanged(repository: Repository, base: String) throws -> ValidationPlan {
    let paths = try repository.changedFiles(base: base)
    guard !paths.isEmpty else { throw OpsError.failed("no changed files to verify") }
    let plan = try ChangeClassifier.classify(paths)
    printPlan(plan)

    if plan.runOpsTests { try runOpsTests(repository: repository) }
    try lintControlPlane(repository: repository)
    if plan.buildApp { try buildApp(repository: repository) }
    if plan.runUnitTests { try runTargetedUnitTests(repository: repository, requested: plan.selectedUnitTests) }

    if let reason = plan.fullGUIReason {
      try GUIRunner.run(
        repository: repository,
        scenarios: GUIRunner.scenarioOrder,
        allReason: reason,
        retryOf: nil,
        rootCause: nil
      )
    } else if !plan.selectedGUIScenarios.isEmpty {
      try GUIRunner.run(
        repository: repository,
        scenarios: plan.selectedGUIScenarios,
        allReason: nil,
        retryOf: nil,
        rootCause: nil
      )
    }

    if plan.requiresSystemAcceptance {
      let list = plan.systemAcceptanceScenarios.joined(separator: ", ")
      throw OpsError.failed(
        "system-boundary acceptance is required: \(list)\n" +
          "run lexiray-ops install, then record each result with lexiray-ops accept"
      )
    }
    return plan
  }

  public static func verifyReleasePR(
    repository: Repository,
    base: String,
    head: String,
    pullRequestNumber: Int?
  ) throws {
    let resolvedBase = try repository.resolve(base)
    let resolvedHead = try repository.resolve(head)
    if ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" {
      guard let pullRequestNumber else {
        throw OpsError.failed("release-ci requires --pr-number in GitHub Actions")
      }
      try ReleasePRAttemptGate.authorize(
        repository: repository,
        pullRequestNumber: pullRequestNumber,
        headSHA: resolvedHead
      )
    }
    let ancestry = try ProcessRunner.run(
      "/usr/bin/git", ["merge-base", "--is-ancestor", resolvedBase, resolvedHead],
      cwd: repository.root, capture: true, allowedExitCodes: [0, 1]
    )
    guard ancestry.status == 0 else {
      throw OpsError.failed("release PR head is not descended from its main base")
    }
    try lintControlPlane(repository: repository)
    try runOpsTests(repository: repository)
    try generateProject(repository: repository)
    try ProcessRunner.run(
      "/usr/bin/xcodebuild",
      [
        "test", "-project", "LexiRay.xcodeproj", "-scheme", "LexiRay",
        "-configuration", "Debug", "-destination", "platform=macOS",
        "-derivedDataPath", "build/ReleaseCIDerivedData", "CODE_SIGNING_ALLOWED=NO"
      ],
      cwd: repository.root
    )
    let metadata = try releasePreflight(repository: repository, requestedVersion: nil)
    try packagePreflight(repository: repository, metadata: metadata)
  }

  public static func releasePreflight(repository: Repository, requestedVersion: String?) throws -> (version: String, build: String) {
    let infoURL = repository.root.appendingPathComponent("LexiRay/Resources/Info.plist")
    let object = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), options: [], format: nil)
    guard let info = object as? [String: Any],
          let version = info["CFBundleShortVersionString"] as? String,
          let build = info["CFBundleVersion"] as? String
    else { throw OpsError.failed("Info.plist is missing release version metadata") }
    guard version.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil else {
      throw OpsError.failed("invalid release version in Info.plist: \(version)")
    }
    guard Int(build).map({ $0 > 0 }) == true else {
      throw OpsError.failed("CFBundleVersion must be a positive integer")
    }
    if let requestedVersion, requestedVersion != version {
      throw OpsError.failed("requested version \(requestedVersion) does not match Info.plist \(version)")
    }
    let changelog = try String(contentsOf: repository.root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
    guard changelog.contains("## [\(version)]") else {
      throw OpsError.failed("CHANGELOG.md has no \(version) release section")
    }
    return (version, build)
  }

  public static func packagePreflight(
    repository: Repository,
    metadata: (version: String, build: String)
  ) throws {
    let packageDirectory = repository.root.appendingPathComponent("build/ReleaseCIPackage", isDirectory: true)
    let app = packageDirectory.appendingPathComponent("LexiRay.app", isDirectory: true)
    let dmg = repository.root.appendingPathComponent("build/ReleaseCIPreflight.dmg")
    let manager = FileManager.default
    if manager.fileExists(atPath: packageDirectory.path) { try manager.removeItem(at: packageDirectory) }
    if manager.fileExists(atPath: dmg.path) { try manager.removeItem(at: dmg) }
    try manager.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
    defer {
      try? manager.removeItem(at: packageDirectory)
      try? manager.removeItem(at: dmg)
    }

    try ProcessRunner.run(
      "/usr/bin/xcodebuild",
      [
        "build", "-project", "LexiRay.xcodeproj", "-scheme", "LexiRay",
        "-configuration", "Release", "-destination", "platform=macOS",
        "-derivedDataPath", "build/ReleaseCIDerivedData",
        "CONFIGURATION_BUILD_DIR=\(packageDirectory.path)",
        "CODE_SIGNING_ALLOWED=NO", "SWIFT_COMPILATION_MODE=wholemodule"
      ],
      cwd: repository.root
    )
    let infoURL = app.appendingPathComponent("Contents/Info.plist")
    let object = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), options: [], format: nil)
    guard let info = object as? [String: Any],
          info["CFBundleIdentifier"] as? String == ReleaseContract.bundleID,
          info["CFBundleShortVersionString"] as? String == metadata.version,
          info["CFBundleVersion"] as? String == metadata.build,
          !manager.fileExists(atPath: app.appendingPathComponent("Contents/_CodeSignature").path)
    else { throw OpsError.failed("unsigned release package preflight metadata is invalid") }

    try ProcessRunner.run(
      "/usr/bin/hdiutil",
      ["create", "-volname", "LexiRay", "-srcfolder", app.path, "-ov", "-format", "UDZO", dmg.path],
      cwd: repository.root
    )
    try ProcessRunner.run("/usr/bin/hdiutil", ["verify", dmg.path], cwd: repository.root)
  }

  public static func lintControlPlane(repository: Repository) throws {
    let trackedShell = try repository.git(["ls-files", "--", "*.sh"])
    guard trackedShell.isEmpty else {
      throw OpsError.failed("tracked shell files are forbidden:\n\(trackedShell)")
    }

    let workflowDirectory = repository.root.appendingPathComponent(".github/workflows", isDirectory: true)
    let workflows = (try? FileManager.default.contentsOfDirectory(at: workflowDirectory, includingPropertiesForKeys: nil))?
      .filter { ["yml", "yaml"].contains($0.pathExtension) } ?? []
    guard workflows.map(\.lastPathComponent).sorted() == ["release.yml"] else {
      throw OpsError.failed(".github/workflows must contain only release.yml")
    }

    let referenceCheck = try ProcessRunner.run(
      "/usr/bin/env",
      ["rg", "-n", "\\.sh\\b", "AGENTS.md", "README.md", ".agents", ".github"],
      cwd: repository.root,
      capture: true,
      allowedExitCodes: [0, 1]
    )
    guard referenceCheck.status == 1 else {
      throw OpsError.failed("stale shell references remain:\n\(referenceCheck.output)")
    }

    let workflow = try String(contentsOf: workflowDirectory.appendingPathComponent("release.yml"), encoding: .utf8)
    let forbidden = ["push:", "codeql", "request_ai_review", "script/"]
    let hits = forbidden.filter { workflow.localizedCaseInsensitiveContains($0) }
    guard hits.isEmpty else {
      throw OpsError.failed("release workflow contains forbidden legacy triggers or calls: \(hits.joined(separator: ", "))")
    }
  }

  public static func generateProject(repository: Repository) throws {
    try ProcessRunner.run("/usr/bin/env", ["xcodegen", "generate"], cwd: repository.root)
  }

  public static func buildApp(repository: Repository, configuration: String = "Debug") throws {
    try generateProject(repository: repository)
    try ProcessRunner.run(
      "/usr/bin/xcodebuild",
      [
        "build", "-project", "LexiRay.xcodeproj", "-scheme", "LexiRay",
        "-configuration", configuration, "-destination", "platform=macOS",
        "-derivedDataPath", "build/DerivedData", "CODE_SIGNING_ALLOWED=NO"
      ],
      cwd: repository.root
    )
  }

  public static func runOpsTests(repository: Repository) throws {
    try ProcessRunner.run("/usr/bin/swift", ["test", "--package-path", repository.root.path], cwd: repository.root)
  }

  public static func runTargetedUnitTests(repository: Repository, requested: [String]) throws {
    let available = try availableUnitTests(repository: repository)
    let selected = requested.filter { available.contains($0) }
    guard !selected.isEmpty else {
      print("unit tests: no directly mapped existing test class; build coverage only")
      return
    }
    try generateProject(repository: repository)
    var arguments = [
      "test", "-project", "LexiRay.xcodeproj", "-scheme", "LexiRay",
      "-configuration", "Debug", "-destination", "platform=macOS",
      "-derivedDataPath", "build/TestDerivedData", "CODE_SIGNING_ALLOWED=NO"
    ]
    arguments.append(contentsOf: selected.sorted().map { "-only-testing:LexiRayTests/\($0)" })
    try ProcessRunner.run("/usr/bin/xcodebuild", arguments, cwd: repository.root)
  }

  private static func availableUnitTests(repository: Repository) throws -> Set<String> {
    let directory = repository.root.appendingPathComponent("LexiRayTests", isDirectory: true)
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "swift" }
    let expression = try NSRegularExpression(pattern: #"(?:final\s+)?class\s+([A-Za-z0-9_]+Tests)\s*:"#)
    var result = Set<String>()
    for file in files {
      let source = try String(contentsOf: file, encoding: .utf8)
      let range = NSRange(source.startIndex..., in: source)
      for match in expression.matches(in: source, range: range) {
        guard let swiftRange = Range(match.range(at: 1), in: source) else { continue }
        result.insert(String(source[swiftRange]))
      }
    }
    return result
  }

  private static func printPlan(_ plan: ValidationPlan) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    if let data = try? encoder.encode(plan), let text = String(data: data, encoding: .utf8) {
      print(text)
    }
  }
}
