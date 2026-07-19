import CryptoKit
import Foundation

public enum OpsError: Error, CustomStringConvertible, Sendable {
  case usage(String)
  case failed(String)

  public var description: String {
    switch self {
    case let .usage(message), let .failed(message): message
    }
  }
}

public struct ProcessResult: Sendable {
  public let status: Int32
  public let output: String
}

public struct PinnedSigningIdentity: Equatable, Sendable {
  public let name: String
  public let certificateSHA1: String
  public let certificateSHA256: String
}

public enum SigningIdentityContract {
  public static let development = PinnedSigningIdentity(
    name: "LexiRay Local Development",
    certificateSHA1: "B665AB9A2956DDD3C2712669E4DA0DBE30DA084D",
    certificateSHA256: "77C74E4D76C7A7AE0D0FF77D5C4AA928E0FE75CA463BF7B5FC6D0C9E08F6D356"
  )
  public static let release = PinnedSigningIdentity(
    name: "LexiRay Release Self-Signed",
    certificateSHA1: "C4407C14D31AA9397CD21829E9F26C9AF7AA925B",
    certificateSHA256: "5A54594CFDFB1827E3A097EA43BF4674A6FCBFA2563D60DE178566AE860229F5"
  )
  public static let installable = [development, release]
}

public enum SigningIdentityVerifier {
  @discardableResult
  public static func verify(
    app: URL,
    repository: Repository,
    allowed: [PinnedSigningIdentity]
  ) throws -> PinnedSigningIdentity {
    try ProcessRunner.run(
      "/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path],
      cwd: repository.root,
      capture: true
    )
    let details = try ProcessRunner.capture(
      "/usr/bin/codesign", ["-dvvv", app.path], cwd: repository.root
    )
    guard details.contains("Identifier=io.github.tensornull.lexiray") else {
      throw OpsError.failed("LexiRay code signature has an unexpected bundle identifier")
    }
    let identity = allowed.first { details.contains("Authority=\($0.name)") }
    guard let identity else {
      throw OpsError.failed("LexiRay is not signed by an allowed pinned identity")
    }

    let certificateDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "lexiray-signing-certificate-\(UUID().uuidString.lowercased())",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: certificateDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: certificateDirectory) }
    try ProcessRunner.run(
      "/usr/bin/codesign", ["-d", "--extract-certificates", app.path],
      cwd: certificateDirectory,
      capture: true
    )
    let certificate = certificateDirectory.appendingPathComponent("codesign0")
    guard FileManager.default.fileExists(atPath: certificate.path),
          try Data(contentsOf: certificate).sha256.uppercased() == identity.certificateSHA256
    else { throw OpsError.failed("LexiRay signing certificate fingerprint is not pinned") }

    let requirement = try ProcessRunner.capture(
      "/usr/bin/codesign", ["-d", "-r-", app.path], cwd: repository.root
    )
    let expected = "identifier \"io.github.tensornull.lexiray\" and certificate leaf = H\"\(identity.certificateSHA1.lowercased())\""
    guard requirement.contains("designated => \(expected)") else {
      throw OpsError.failed("LexiRay designated requirement does not match its pinned identity")
    }
    return identity
  }
}

public enum ProcessRunner {
  @discardableResult
  public static func run(
    _ executable: String,
    _ arguments: [String],
    cwd: URL,
    environment: [String: String] = [:],
    input: Data? = nil,
    capture: Bool = false,
    redactedArgumentIndexes: Set<Int> = [],
    allowedExitCodes: Set<Int32> = [0]
  ) throws -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = cwd
    process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

    let outputPipe = Pipe()
    if capture {
      process.standardOutput = outputPipe
      process.standardError = outputPipe
    } else {
      process.standardOutput = FileHandle.standardOutput
      process.standardError = FileHandle.standardError
    }

    var inputPipe: Pipe?
    if let input {
      let pipe = Pipe()
      inputPipe = pipe
      process.standardInput = pipe
      try process.run()
      try pipe.fileHandleForWriting.write(contentsOf: input)
      try pipe.fileHandleForWriting.close()
    } else {
      try process.run()
    }

    let data = capture ? outputPipe.fileHandleForReading.readDataToEndOfFile() : Data()
    process.waitUntilExit()
    _ = inputPipe
    let output = String(decoding: data, as: UTF8.self)
    guard allowedExitCodes.contains(process.terminationStatus) else {
      let displayedArguments = arguments.enumerated().map { index, value in
        redactedArgumentIndexes.contains(index) ? "<redacted>" : value
      }
      let command = ([executable] + displayedArguments).joined(separator: " ")
      throw OpsError.failed("command failed (\(process.terminationStatus)): \(command)\n\(output)")
    }
    return ProcessResult(status: process.terminationStatus, output: output)
  }

  public static func capture(
    _ executable: String,
    _ arguments: [String],
    cwd: URL,
    environment: [String: String] = [:]
  ) throws -> String {
    try run(executable, arguments, cwd: cwd, environment: environment, capture: true).output
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

public struct Repository: Sendable {
  public let root: URL

  public init(root: URL) {
    self.root = root.standardizedFileURL
  }

  public static func discover(from directory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) throws -> Repository {
    let root = try ProcessRunner.capture("/usr/bin/git", ["rev-parse", "--show-toplevel"], cwd: directory)
    guard !root.isEmpty else { throw OpsError.failed("not inside a Git worktree") }
    return Repository(root: URL(fileURLWithPath: root, isDirectory: true))
  }

  public func git(_ arguments: [String]) throws -> String {
    try ProcessRunner.capture("/usr/bin/git", arguments, cwd: root)
  }

  public func resolve(_ revision: String) throws -> String {
    let value = try git(["rev-parse", "--verify", "\(revision)^{commit}"])
    guard value.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil else {
      throw OpsError.failed("invalid Git revision: \(revision)")
    }
    return value
  }

  public func changedFiles(base: String) throws -> [String] {
    let resolvedBase = try resolve(base)
    var paths = Set<String>()
    let commands = [
      ["diff", "--name-only", "--diff-filter=ACDMRTUXB", "\(resolvedBase)...HEAD"],
      ["diff", "--name-only", "--diff-filter=ACDMRTUXB", "HEAD"],
      ["ls-files", "--others", "--exclude-standard"]
    ]
    for command in commands {
      for line in try git(command).split(separator: "\n") {
        let path = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty { paths.insert(path) }
      }
    }
    return paths.sorted()
  }

  public func sourceFingerprint() throws -> String {
    let scopes = [
      "LexiRay", "LexiRayTests", "project.yml", "Package.swift",
      "Sources/LexiRayOps", "Sources/LexiRayOpsCore", "Tools/LexiRayGUI"
    ]
    let output = try git(["ls-files", "-z", "--cached", "--others", "--exclude-standard", "--"] + scopes)
    let paths = Set(output.split(separator: "\0").map(String.init)).sorted()
    var hasher = SHA256()
    for path in paths {
      let url = root.appendingPathComponent(path)
      hasher.update(data: Data(path.utf8))
      hasher.update(data: Data([0]))
      if FileManager.default.fileExists(atPath: url.path) {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
          throw OpsError.failed("fingerprinted source must be a regular non-symlink file: \(path)")
        }
        hasher.update(data: try Data(contentsOf: url))
      } else {
        hasher.update(data: Data("<deleted>".utf8))
      }
      hasher.update(data: Data([0]))
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }
}

public extension Array where Element == String {
  func value(after flag: String) throws -> String {
    guard let index = firstIndex(of: flag), indices.contains(index + 1) else {
      throw OpsError.usage("missing required option \(flag)")
    }
    return self[index + 1]
  }

  func optionalValue(after flag: String) -> String? {
    guard let index = firstIndex(of: flag), indices.contains(index + 1) else { return nil }
    return self[index + 1]
  }
}

public extension Data {
  var sha256: String {
    SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
  }
}
