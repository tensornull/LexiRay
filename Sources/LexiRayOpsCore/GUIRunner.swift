import ApplicationServices
import CoreGraphics
import Foundation

public enum GUIRunner {
  private static let developmentIdentityName = "LexiRay Local Development"
  private static let developmentCertificateSHA1 = "B665AB9A2956DDD3C2712669E4DA0DBE30DA084D"
  private static let developmentCertificateSHA256 = "77C74E4D76C7A7AE0D0FF77D5C4AA928E0FE75CA463BF7B5FC6D0C9E08F6D356"

  public static let scenarioOrder = [
    "launch", "providers", "settings_identity", "panel_blank", "source_editor",
    "language_direction_input", "speech_controls", "history_nav", "rich_result_wrap",
    "pin", "panel_visual_states", "selection_translate", "ocr_permission_gate",
    "ocr_multi_display", "manual_resize_preserved", "streaming_growth"
  ]

  public static func run(
    repository: Repository,
    scenarios: [String],
    allReason: String?,
    retryOf: String?,
    rootCause: String?
  ) throws {
    let requested = Array(Set(scenarios)).sorted { left, right in
      (scenarioOrder.firstIndex(of: left) ?? .max) < (scenarioOrder.firstIndex(of: right) ?? .max)
    }
    guard !requested.isEmpty else { throw OpsError.usage("gui run requires at least one scenario") }
    let unknown = requested.filter { !scenarioOrder.contains($0) }
    guard unknown.isEmpty else { throw OpsError.usage("unknown GUI scenarios: \(unknown.joined(separator: ", "))") }
    if requested.count == scenarioOrder.count {
      let validReasons = ["shared-ui", "runner-change", "explicit"]
      guard let allReason, validReasons.contains(allReason) else {
        throw OpsError.usage("full GUI requires --reason shared-ui|runner-change|explicit")
      }
    }

    let command = "gui run " + requested.joined(separator: " ")
    let store = EvidenceStore(repository: repository)
    var evidenceWritten = false
    do {
      try requirePermissions()
      try requireNoRunningLexiRay(repository: repository)
      let fingerprintBefore = try repository.sourceFingerprint()
      try buildWorkspaceApp(repository: repository)

      let runID = UUID().uuidString.lowercased()
      let artifactDirectory = repository.root.appendingPathComponent("build/ui-artifacts/\(runID)", isDirectory: true)
      let acceptanceRoot = repository.root.appendingPathComponent("build/acceptance-data/\(runID)", isDirectory: true)
      let workDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("lexiray-ui-\(runID)", isDirectory: true)
      try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
      try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
      defer {
        try? FileManager.default.removeItem(at: acceptanceRoot)
        try? FileManager.default.removeItem(at: workDirectory)
      }

      let app = repository.root.appendingPathComponent("build/DerivedData/Build/Products/Debug/LexiRay.app", isDirectory: true)
      var results: [String] = []
      var logs: [String] = []
      var finalResult = "passed"

      for scenario in requested {
        try requireNoRunningLexiRay(repository: repository)
        try seedAcceptanceData(repository: repository, acceptanceRoot: acceptanceRoot)
        let source = try scenarioSource(repository: repository, name: scenario)
        let suite = "io.github.tensornull.lexiray.acceptance.\(runID).\(scenario)"
        let result = try ProcessRunner.run(
          "/usr/bin/swift",
          [
            "-", app.path, workDirectory.path, artifactDirectory.path, scenario,
            repository.root.path, acceptanceRoot.path, suite
          ],
          cwd: repository.root,
          input: source,
          capture: true,
          allowedExitCodes: [0, 1, 2]
        )
        print(result.output, terminator: result.output.hasSuffix("\n") ? "" : "\n")
        logs.append("--- \(scenario) ---\n\(result.output)")
        switch result.status {
        case 0:
          results.append("PASS  \(scenario)")
        case 2:
          results.append("BLOCK \(scenario)")
          finalResult = "blocked"
        default:
          results.append("FAIL  \(scenario)")
          if finalResult != "blocked" { finalResult = "failed" }
        }
        if result.status != 0 { break }
      }

      if try repository.sourceFingerprint() != fingerprintBefore {
        results.append("FAIL  source changed during GUI verification")
        finalResult = "failed"
      }
      let resultsURL = artifactDirectory.appendingPathComponent("results.txt")
      try (results.joined(separator: "\n") + "\n").write(to: resultsURL, atomically: true, encoding: .utf8)
      let images = store.artifacts(below: artifactDirectory)
      let evidenceURL = try store.write(
        command: command,
        scenarios: requested,
        result: finalResult,
        rootCause: rootCause,
        retryOf: retryOf,
        log: logs.joined(separator: "\n"),
        artifactURLs: [resultsURL] + images
      )
      evidenceWritten = true
      print("GUI evidence: \(evidenceURL.path)")
      guard finalResult == "passed" else {
        throw OpsError.failed("GUI verification \(finalResult); debug only the affected scenario before another final run")
      }
    } catch {
      if !evidenceWritten {
        let message = String(describing: error)
        let result = message.localizedCaseInsensitiveContains("blocked") ? "blocked" : "failed"
        if let evidenceURL = try? store.write(
          command: command,
          scenarios: requested,
          result: result,
          rootCause: rootCause,
          retryOf: retryOf,
          log: message
        ) {
          print("GUI evidence: \(evidenceURL.path)")
        }
      }
      throw error
    }
  }

  private static func requirePermissions() throws {
    guard AXIsProcessTrusted() else {
      throw OpsError.failed("GUI blocked: the runner lacks Accessibility permission")
    }
    guard CGPreflightScreenCaptureAccess() else {
      throw OpsError.failed("GUI blocked: the runner lacks Screen Recording permission")
    }
  }

  private static func requireNoRunningLexiRay(repository: Repository) throws {
    let result = try ProcessRunner.run(
      "/usr/bin/pgrep", ["-x", "LexiRay"], cwd: repository.root,
      capture: true, allowedExitCodes: [0, 1]
    )
    guard result.status == 1 else {
      throw OpsError.failed("GUI blocked: a LexiRay process is already running; the runner will not terminate it")
    }
  }

  private static func buildWorkspaceApp(repository: Repository) throws {
    try requireDevelopmentIdentity(repository: repository)
    try ValidationExecutor.generateProject(repository: repository)
    let app = repository.root.appendingPathComponent("build/DerivedData/Build/Products/Debug/LexiRay.app")
    if FileManager.default.fileExists(atPath: app.path) { try FileManager.default.removeItem(at: app) }
    try ProcessRunner.run(
      "/usr/bin/xcodebuild",
      [
        "build", "-project", "LexiRay.xcodeproj", "-scheme", "LexiRay",
        "-configuration", "Debug", "-destination", "platform=macOS",
        "-derivedDataPath", "build/DerivedData", "CODE_SIGN_STYLE=Manual",
        "CODE_SIGN_IDENTITY=\(developmentCertificateSHA1)", "DEVELOPMENT_TEAM=",
        "ENABLE_DEBUG_DYLIB=NO"
      ],
      cwd: repository.root
    )
    guard FileManager.default.fileExists(atPath: app.path) else {
      throw OpsError.failed("workspace app was not produced at \(app.path)")
    }
    try ProcessRunner.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path], cwd: repository.root)
    try verifyDevelopmentIdentity(app: app, repository: repository)
  }

  private static func requireDevelopmentIdentity(repository: Repository) throws {
    let identities = try ProcessRunner.run(
      "/usr/bin/security", ["find-identity", "-v", "-p", "codesigning"],
      cwd: repository.root, capture: true
    ).output
    guard identities.contains(developmentCertificateSHA1),
          identities.contains("\"\(developmentIdentityName)\"")
    else {
      throw OpsError.failed(
        "GUI blocked: fixed local development identity \(developmentCertificateSHA1) is unavailable"
      )
    }
  }

  private static func verifyDevelopmentIdentity(app: URL, repository: Repository) throws {
    let details = try ProcessRunner.run(
      "/usr/bin/codesign", ["-dvvv", app.path],
      cwd: repository.root, capture: true
    ).output
    guard details.contains("Authority=\(developmentIdentityName)") else {
      throw OpsError.failed("workspace app was not signed by \(developmentIdentityName)")
    }

    let certificateDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "lexiray-development-certificate-\(UUID().uuidString.lowercased())",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: certificateDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: certificateDirectory) }
    try ProcessRunner.run(
      "/usr/bin/codesign", ["-d", "--extract-certificates", app.path],
      cwd: certificateDirectory
    )
    let certificate = certificateDirectory.appendingPathComponent("codesign0")
    guard FileManager.default.fileExists(atPath: certificate.path) else {
      throw OpsError.failed("workspace app signing certificate could not be extracted")
    }
    let fingerprint = try ProcessRunner.run(
      "/usr/bin/openssl",
      ["x509", "-inform", "DER", "-in", certificate.path, "-noout", "-fingerprint", "-sha256"],
      cwd: repository.root, capture: true
    ).output
      .uppercased()
      .replacingOccurrences(of: ":", with: "")
    guard fingerprint.contains(developmentCertificateSHA256) else {
      throw OpsError.failed("workspace app development certificate fingerprint is unexpected")
    }

    let requirement = try ProcessRunner.run(
      "/usr/bin/codesign", ["-d", "-r-", app.path],
      cwd: repository.root, capture: true
    ).output
    let expectedRequirement = "identifier \"io.github.tensornull.lexiray\" and certificate leaf = H\"\(developmentCertificateSHA1.lowercased())\""
    guard requirement.contains("designated => \(expectedRequirement)") else {
      throw OpsError.failed("workspace app designated requirement is unexpected")
    }
  }

  private static func seedAcceptanceData(repository: Repository, acceptanceRoot: URL) throws {
    if FileManager.default.fileExists(atPath: acceptanceRoot.path) {
      try FileManager.default.removeItem(at: acceptanceRoot)
    }
    try FileManager.default.createDirectory(at: acceptanceRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: acceptanceRoot.appendingPathComponent("preferences-home", isDirectory: true),
      withIntermediateDirectories: true
    )
    let marker = acceptanceRoot.appendingPathComponent(".lexiray-acceptance-root")
    try Data("LexiRay acceptance root v1\n".utf8).write(to: marker, options: .atomic)
    for name in ["providers.json", "history.json"] {
      let source = repository.root.appendingPathComponent("Tools/LexiRayGUI/fixtures/\(name)")
      let destination = acceptanceRoot.appendingPathComponent(name)
      try FileManager.default.copyItem(at: source, to: destination)
    }
  }

  private static func scenarioSource(repository: Repository, name: String) throws -> Data {
    let paths = [
      "Tools/LexiRayGUI/panel_border_evidence.swift",
      "Tools/LexiRayGUI/lib.swift",
      "Tools/LexiRayGUI/scenarios/\(name).swift"
    ]
    var data = Data()
    for path in paths {
      data.append(try Data(contentsOf: repository.root.appendingPathComponent(path)))
      data.append(Data("\n".utf8))
    }
    return data
  }
}
