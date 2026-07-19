import Foundation
import LexiRayOpsCore

@main
struct LexiRayOpsMain {
  static func main() {
    do {
      try run()
    } catch let error as OpsError {
      FileHandle.standardError.write(Data("lexiray-ops: \(error)\n".utf8))
      switch error {
      case .usage: exit(2)
      case .failed: exit(1)
      }
    } catch {
      FileHandle.standardError.write(Data("lexiray-ops: \(error)\n".utf8))
      exit(1)
    }
  }

  private static func run() throws {
    var arguments = Array(CommandLine.arguments.dropFirst())
    let repository: Repository
    if let index = arguments.firstIndex(of: "--root") {
      guard arguments.indices.contains(index + 1) else { throw OpsError.usage("--root requires a path") }
      repository = Repository(root: URL(fileURLWithPath: arguments[index + 1], isDirectory: true))
      arguments.removeSubrange(index ... index + 1)
    } else {
      repository = try Repository.discover()
    }
    guard let command = arguments.first else { throw OpsError.usage(usage) }
    let rest = Array(arguments.dropFirst())
    switch command {
    case "verify": try verify(rest, repository: repository)
    case "gui": try gui(rest, repository: repository)
    case "install": try install(rest, repository: repository)
    case "accept": try accept(rest, repository: repository)
    case "release": try release(rest, repository: repository)
    case "help", "--help", "-h": print(usage)
    default: throw OpsError.usage("unknown command: \(command)\n\n\(usage)")
    }
  }

  private static func verify(_ arguments: [String], repository: Repository) throws {
    guard let mode = arguments.first else { throw OpsError.usage(usage) }
    switch mode {
    case "changed":
      let base = arguments.optionalValue(after: "--base") ?? "HEAD"
      _ = try ValidationExecutor.verifyChanged(repository: repository, base: base)
    case "release-pr":
      let pullRequestNumber = arguments.optionalValue(after: "--pr-number").flatMap(Int.init)
      try ValidationExecutor.verifyReleasePR(
        repository: repository,
        base: arguments.value(after: "--base"),
        head: arguments.value(after: "--head"),
        pullRequestNumber: pullRequestNumber
      )
    default: throw OpsError.usage("verify requires changed or release-pr")
    }
  }

  private static func gui(_ arguments: [String], repository: Repository) throws {
    guard let mode = arguments.first else { throw OpsError.usage(usage) }
    if mode == "list" {
      GUIRunner.scenarioOrder.forEach { print($0) }
      return
    }
    guard mode == "run" else { throw OpsError.usage("gui requires list or run") }
    let options = Array(arguments.dropFirst())
    let full = options.contains("--all")
    let reason = options.optionalValue(after: "--reason")
    let retryOf = options.optionalValue(after: "--retry-of")
    let cause = options.optionalValue(after: "--cause")
    let valueFlags = Set(["--reason", "--retry-of", "--cause"])
    var scenarios: [String] = []
    var skipNext = false
    for value in options {
      if skipNext { skipNext = false; continue }
      if valueFlags.contains(value) { skipNext = true; continue }
      if value == "--all" { continue }
      if value.hasPrefix("-") { throw OpsError.usage("unknown gui option: \(value)") }
      scenarios.append(value)
    }
    try GUIRunner.run(
      repository: repository,
      scenarios: full ? GUIRunner.scenarioOrder : scenarios,
      allReason: reason,
      retryOf: retryOf,
      rootCause: cause
    )
  }

  private static func install(_ arguments: [String], repository: Repository) throws {
    let source = arguments.optionalValue(after: "--source").map { URL(fileURLWithPath: $0) }
    let evidence = try Installer.install(
      repository: repository,
      source: source,
      retryOf: arguments.optionalValue(after: "--retry-of"),
      rootCause: arguments.optionalValue(after: "--cause")
    )
    print("install evidence: \(evidence.path)")
  }

  private static func accept(_ arguments: [String], repository: Repository) throws {
    guard arguments.count >= 2 else { throw OpsError.usage("accept requires launch|record and a scenario") }
    let mode = arguments[0]
    let scenario = arguments[1]
    switch mode {
    case "launch":
      let launch = try AcceptanceRecorder.launch(repository: repository, scenario: scenario)
      print("acceptance_pid=\(launch.processIdentifier)")
      print("record with: swift run lexiray-ops accept record \(scenario) --pid \(launch.processIdentifier) --result passed|failed|blocked")
    case "record":
      guard let processIdentifier = Int32(try arguments.value(after: "--pid")) else {
        throw OpsError.usage("accept record --pid must be an integer")
      }
      let evidence = try AcceptanceRecorder.record(
        repository: repository,
        scenario: scenario,
        result: arguments.value(after: "--result"),
        processIdentifier: processIdentifier,
        retryOf: arguments.optionalValue(after: "--retry-of"),
        rootCause: arguments.optionalValue(after: "--cause")
      )
      print("acceptance evidence: \(evidence.path)")
    default:
      throw OpsError.usage("accept requires launch or record")
    }
  }

  private static func release(_ arguments: [String], repository: Repository) throws {
    guard let mode = arguments.first else { throw OpsError.usage(usage) }
    switch mode {
    case "authorize-pr":
      guard let number = Int(try arguments.value(after: "--pr-number")) else {
        throw OpsError.usage("--pr-number must be an integer")
      }
      try ReleasePRAttemptGate.authorize(
        repository: repository,
        pullRequestNumber: number,
        headSHA: try arguments.value(after: "--head")
      )
    case "authorize":
      try ReleaseAuthorization.validate(
        repository: repository,
        version: arguments.value(after: "--version"),
        sha: arguments.value(after: "--sha")
      )
    case "preflight":
      let metadata = try ValidationExecutor.releasePreflight(
        repository: repository,
        requestedVersion: arguments.optionalValue(after: "--version")
      )
      print("release preflight passed: \(metadata.version) (\(metadata.build))")
    case "build":
      let version = try arguments.value(after: "--version")
      let sha = try arguments.value(after: "--sha")
      let artifacts = try ReleaseBuilder.build(repository: repository, version: version, sha: sha)
      print("dmg=\(artifacts.dmg.path)")
      print("checksum=\(artifacts.checksum.path)")
    case "publish":
      let version = try arguments.value(after: "--version")
      let sha = try arguments.value(after: "--sha")
      try ReleasePublisher.publish(
        repository: repository,
        version: version,
        sha: sha,
        dmg: URL(fileURLWithPath: arguments.value(after: "--dmg")),
        checksum: URL(fileURLWithPath: arguments.value(after: "--checksum"))
      )
    case "close-failed-pr":
      guard let number = Int(try arguments.value(after: "--pr-number")) else {
        throw OpsError.usage("--pr-number must be an integer")
      }
      try ReleasePRAttemptGate.closeIfExhausted(
        repository: repository,
        pullRequestNumber: number
      )
    default: throw OpsError.usage("release requires authorize-pr, authorize, preflight, build, publish, or close-failed-pr")
    }
  }

  private static let usage = """
    usage: lexiray-ops [--root PATH] <command>

      verify changed [--base SHA]
      verify release-pr --base SHA --head SHA [--pr-number N]
      gui list
      gui run <scenario>... [--retry-of ID --cause TEXT]
      gui run --all --reason shared-ui|runner-change|explicit
      install [--source PATH] [--retry-of ID --cause TEXT]
      accept launch <scenario>
      accept record <scenario> --pid PID --result passed|failed|blocked [--retry-of ID --cause TEXT]
      release authorize-pr --pr-number N --head SHA
      release authorize --version X.Y.Z --sha SHA
      release preflight [--version X.Y.Z]
      release build --version X.Y.Z --sha SHA
      release publish --version X.Y.Z --sha SHA --dmg PATH --checksum PATH
      release close-failed-pr --pr-number N
    """
}
