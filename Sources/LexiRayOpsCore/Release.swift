import Darwin
import Foundation

public enum ReleaseContract {
  public static let repository = "tensornull/LexiRay"
  public static let bundleID = "io.github.tensornull.lexiray"
  public static let identityName = SigningIdentityContract.release.name
  public static let certificateSHA1 = SigningIdentityContract.release.certificateSHA1
  public static let certificateSHA256 = SigningIdentityContract.release.certificateSHA256
}

public struct ReleaseArtifacts: Sendable {
  public let dmg: URL
  public let checksum: URL
}

private enum GitHubAPI {
  static func required(_ endpoint: String, repository: Repository) throws -> Data {
    let output = try ProcessRunner.capture(
      "/usr/bin/env", ["gh", "api", endpoint], cwd: repository.root
    )
    guard let data = output.data(using: .utf8) else {
      throw OpsError.failed("GitHub API returned non-UTF-8 data for \(endpoint)")
    }
    return data
  }

  static func optional(
    _ endpoint: String,
    jq: String? = nil,
    repository: Repository
  ) throws -> String? {
    var arguments = ["gh", "api", endpoint]
    if let jq { arguments += ["--jq", jq] }
    let result = try ProcessRunner.run(
      "/usr/bin/env", arguments, cwd: repository.root,
      capture: true, allowedExitCodes: [0, 1]
    )
    if result.status == 0 {
      return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if result.output.localizedCaseInsensitiveContains("not found") || result.output.contains("HTTP 404") {
      return nil
    }
    throw OpsError.failed("GitHub API lookup failed for \(endpoint):\n\(result.output)")
  }
}

public enum ReleasePRAttemptGate {
  private struct PullRequest: Decodable {
    struct Branch: Decodable {
      let ref: String
      let sha: String
    }

    let state: String
    let createdAt: String
    let head: Branch
    let base: Branch

    enum CodingKeys: String, CodingKey {
      case state
      case createdAt = "created_at"
      case head
      case base
    }
  }

  struct WorkflowRuns: Decodable {
    struct Run: Decodable {
      struct PullRequestReference: Decodable { let number: Int }

      let id: Int64
      let createdAt: String
      let pullRequests: [PullRequestReference]

      enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case pullRequests = "pull_requests"
      }
    }

    let workflowRuns: [Run]

    enum CodingKeys: String, CodingKey {
      case workflowRuns = "workflow_runs"
    }
  }

  public static func authorize(
    repository: Repository,
    pullRequestNumber: Int,
    headSHA: String
  ) throws {
    let runID = try requireActionsContext()
    let pullRequest = try decodePullRequest(repository: repository, number: pullRequestNumber)
    guard pullRequest.state == "open",
          pullRequest.base.ref == "main",
          pullRequest.head.ref == "dev",
          pullRequest.head.sha == headSHA
    else { throw OpsError.failed("release-ci accepts only the current open dev to main pull request head") }
    let count = try attemptCount(
      repository: repository,
      pullRequestNumber: pullRequestNumber,
      pullRequestCreatedAt: pullRequest.createdAt,
      currentRunID: runID
    )
    guard count <= 2 else {
      throw OpsError.failed("release PR has exhausted its initial run and one diagnosed retry")
    }
  }

  public static func closeIfExhausted(
    repository: Repository,
    pullRequestNumber: Int
  ) throws {
    let runID = try requireActionsContext()
    let pullRequest = try decodePullRequest(repository: repository, number: pullRequestNumber)
    let count = try attemptCount(
      repository: repository,
      pullRequestNumber: pullRequestNumber,
      pullRequestCreatedAt: pullRequest.createdAt,
      currentRunID: runID
    )
    guard count >= 2 else { return }
    guard pullRequest.state == "open" else { return }
    try ProcessRunner.run(
      "/usr/bin/env",
      [
        "gh", "api", "--method", "PATCH",
        "repos/\(ReleaseContract.repository)/pulls/\(pullRequestNumber)",
        "-f", "state=closed"
      ],
      cwd: repository.root
    )
  }

  static func attemptCount(
    from data: Data,
    pullRequestNumber: Int,
    pullRequestCreatedAt: String,
    currentRunID: Int64
  ) throws -> Int {
    let response = try JSONDecoder().decode(WorkflowRuns.self, from: data)
    var runIDs = Set(
      response.workflowRuns.filter { run in
        run.createdAt >= pullRequestCreatedAt
          && run.pullRequests.contains(where: { $0.number == pullRequestNumber })
      }.map(\.id)
    )
    runIDs.insert(currentRunID)
    return runIDs.count
  }

  private static func attemptCount(
    repository: Repository,
    pullRequestNumber: Int,
    pullRequestCreatedAt: String,
    currentRunID: Int64
  ) throws -> Int {
    let data = try GitHubAPI.required(
      "repos/\(ReleaseContract.repository)/actions/workflows/release.yml/runs?event=pull_request&branch=dev&per_page=100",
      repository: repository
    )
    return try attemptCount(
      from: data,
      pullRequestNumber: pullRequestNumber,
      pullRequestCreatedAt: pullRequestCreatedAt,
      currentRunID: currentRunID
    )
  }

  private static func decodePullRequest(repository: Repository, number: Int) throws -> PullRequest {
    try JSONDecoder().decode(
      PullRequest.self,
      from: GitHubAPI.required(
        "repos/\(ReleaseContract.repository)/pulls/\(number)",
        repository: repository
      )
    )
  }

  private static func requireActionsContext() throws -> Int64 {
    guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
          ProcessInfo.processInfo.environment["GH_TOKEN"]?.isEmpty == false,
          let rawRunID = ProcessInfo.processInfo.environment["GITHUB_RUN_ID"],
          let runID = Int64(rawRunID)
    else { throw OpsError.failed("release PR attempt control requires GitHub Actions, GH_TOKEN, and GITHUB_RUN_ID") }
    return runID
  }
}

public enum ReleaseAuthorization {
  public static func validate(repository: Repository, version: String, sha: String) throws {
    guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
          ProcessInfo.processInfo.environment["GH_TOKEN"]?.isEmpty == false,
          version.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil,
          sha.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil
    else { throw OpsError.failed("release authorization requires GitHub Actions, GH_TOKEN, x.y.z, and an exact SHA") }

    let mainSHA = try ProcessRunner.capture(
      "/usr/bin/env", ["gh", "api", "repos/\(ReleaseContract.repository)/commits/main", "--jq", ".sha"],
      cwd: repository.root
    )
    let tag = "v\(version)"
    if let tagSHA = try GitHubAPI.optional(
      "repos/\(ReleaseContract.repository)/commits/\(tag)", jq: ".sha", repository: repository
    ) {
      guard tagSHA == sha else { throw OpsError.failed("existing tag \(tag) does not match the requested SHA") }
      let comparison = try ProcessRunner.capture(
        "/usr/bin/env",
        ["gh", "api", "repos/\(ReleaseContract.repository)/compare/\(sha)...\(mainSHA)", "--jq", ".status"],
        cwd: repository.root
      )
      guard comparison == "ahead" || comparison == "identical" else {
        throw OpsError.failed("existing tag \(tag) is not reachable from main")
      }
    } else {
      guard sha == mainSHA else { throw OpsError.failed("a new release must use the exact current main SHA") }
    }
  }
}

public enum ReleaseBuilder {
  public static func build(repository: Repository, version: String, sha: String) throws -> ReleaseArtifacts {
    try requireGitHubActions()
    let resolvedSHA = try repository.resolve(sha)
    let head = try repository.resolve("HEAD")
    guard resolvedSHA == head else { throw OpsError.failed("release checkout HEAD does not match --sha") }
    _ = try ValidationExecutor.releasePreflight(repository: repository, requestedVersion: version)
    let originalFingerprint = try repository.sourceFingerprint()

    guard let encoded = ProcessInfo.processInfo.environment["LEXIRAY_RELEASE_CERT_P12_BASE64"],
          let password = ProcessInfo.processInfo.environment["LEXIRAY_RELEASE_CERT_PASSWORD"],
          !encoded.isEmpty, !password.isEmpty,
          let p12Data = Data(base64Encoded: encoded, options: [.ignoreUnknownCharacters])
    else { throw OpsError.failed("release P12 secrets are missing or invalid") }
    unsetenv("LEXIRAY_RELEASE_CERT_P12_BASE64")
    unsetenv("LEXIRAY_RELEASE_CERT_PASSWORD")

    let runnerTemp = ProcessInfo.processInfo.environment["RUNNER_TEMP"].map(URL.init(fileURLWithPath:))
      ?? FileManager.default.temporaryDirectory
    let nonce = UUID().uuidString.lowercased()
    let keychain = runnerTemp.appendingPathComponent("lexiray-release-\(nonce).keychain-db")
    let p12 = runnerTemp.appendingPathComponent("lexiray-release-\(nonce).p12")
    let keychainPassword = UUID().uuidString
    let originalKeychains = try userKeychains(repository: repository)
    defer {
      try? restoreKeychains(originalKeychains, repository: repository)
      _ = try? ProcessRunner.run(
        "/usr/bin/security", ["delete-keychain", keychain.path],
        cwd: repository.root, capture: true, allowedExitCodes: [0, 44]
      )
      try? FileManager.default.removeItem(at: p12)
    }
    try p12Data.write(to: p12, options: [.atomic])
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: p12.path)
    try importIdentity(
      repository: repository,
      p12: p12,
      p12Password: password,
      keychain: keychain,
      keychainPassword: keychainPassword,
      originalKeychains: originalKeychains
    )

    try ValidationExecutor.generateProject(repository: repository)
    let buildDirectory = repository.root.appendingPathComponent("build/release", isDirectory: true)
    let app = buildDirectory.appendingPathComponent("LexiRay.app", isDirectory: true)
    if FileManager.default.fileExists(atPath: buildDirectory.path) { try FileManager.default.removeItem(at: buildDirectory) }
    try FileManager.default.createDirectory(at: buildDirectory, withIntermediateDirectories: true)
    try ProcessRunner.run(
      "/usr/bin/xcodebuild",
      [
        "build", "-project", "LexiRay.xcodeproj", "-scheme", "LexiRay",
        "-configuration", "Release", "-destination", "platform=macOS",
        "-derivedDataPath", "build/ReleaseDerivedData",
        "CONFIGURATION_BUILD_DIR=\(buildDirectory.path)", "CODE_SIGNING_ALLOWED=NO",
        "SWIFT_COMPILATION_MODE=wholemodule"
      ],
      cwd: repository.root
    )
    let metadata = try ValidationExecutor.releasePreflight(repository: repository, requestedVersion: version)
    let attestation = app.appendingPathComponent("Contents/Resources/LexiRayRelease.plist")
    let attestationObject: [String: Any] = [
      "schema_version": 1,
      "source_commit": resolvedSHA,
      "source_fingerprint": originalFingerprint,
      "version": version,
      "build": metadata.build
    ]
    let attestationData = try PropertyListSerialization.data(fromPropertyList: attestationObject, format: .xml, options: 0)
    try attestationData.write(to: attestation, options: [.atomic])

    try ProcessRunner.run(
      "/usr/bin/codesign",
      [
        "--force", "--deep", "--options", "runtime", "--timestamp=none",
        "--entitlements", repository.root.appendingPathComponent("LexiRay/Resources/LexiRay.entitlements").path,
        "--sign", ReleaseContract.certificateSHA1, "--keychain", keychain.path, app.path
      ],
      cwd: repository.root
    )
    try verifySignedApp(
      app, repository: repository, version: version, build: metadata.build,
      sha: resolvedSHA, fingerprint: originalFingerprint
    )
    guard try repository.sourceFingerprint() == originalFingerprint else {
      throw OpsError.failed("release source changed during build")
    }

    let dmg = repository.root.appendingPathComponent("build/LexiRay-\(version).dmg")
    let checksum = repository.root.appendingPathComponent("build/LexiRay-\(version).dmg.sha256")
    try? FileManager.default.removeItem(at: dmg)
    try? FileManager.default.removeItem(at: checksum)
    try ProcessRunner.run(
      "/usr/bin/hdiutil",
      ["create", "-volname", "LexiRay", "-srcfolder", app.path, "-ov", "-format", "UDZO", dmg.path],
      cwd: repository.root
    )
    try verifyDMG(
      dmg, repository: repository, version: version, build: metadata.build,
      sha: resolvedSHA, fingerprint: originalFingerprint
    )
    let digest = try Data(contentsOf: dmg).sha256
    try "\(digest)  \(dmg.lastPathComponent)\n".write(to: checksum, atomically: true, encoding: .utf8)
    return ReleaseArtifacts(dmg: dmg, checksum: checksum)
  }

  private static func requireGitHubActions() throws {
    guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" else {
      throw OpsError.failed("release build is restricted to GitHub Actions")
    }
  }

  private static func userKeychains(repository: Repository) throws -> [String] {
    let output = try ProcessRunner.capture("/usr/bin/security", ["list-keychains", "-d", "user"], cwd: repository.root)
    return output.split(separator: "\n").map {
      $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"") )
    }.filter { !$0.isEmpty }
  }

  private static func restoreKeychains(_ paths: [String], repository: Repository) throws {
    try ProcessRunner.run(
      "/usr/bin/security", ["list-keychains", "-d", "user", "-s"] + paths,
      cwd: repository.root
    )
  }

  private static func importIdentity(
    repository: Repository,
    p12: URL,
    p12Password: String,
    keychain: URL,
    keychainPassword: String,
    originalKeychains: [String]
  ) throws {
    try ProcessRunner.run(
      "/usr/bin/security", ["create-keychain", "-p", keychainPassword, keychain.path],
      cwd: repository.root, redactedArgumentIndexes: [2]
    )
    try ProcessRunner.run("/usr/bin/security", ["set-keychain-settings", "-lut", "1200", keychain.path], cwd: repository.root)
    try ProcessRunner.run(
      "/usr/bin/security", ["unlock-keychain", "-p", keychainPassword, keychain.path],
      cwd: repository.root, redactedArgumentIndexes: [2]
    )
    try ProcessRunner.run(
      "/usr/bin/security", ["list-keychains", "-d", "user", "-s", keychain.path] + originalKeychains,
      cwd: repository.root
    )
    try ProcessRunner.run(
      "/usr/bin/security",
      ["import", p12.path, "-k", keychain.path, "-P", p12Password, "-T", "/usr/bin/codesign", "-T", "/usr/bin/security"],
      cwd: repository.root, redactedArgumentIndexes: [5]
    )
    try ProcessRunner.run(
      "/usr/bin/security",
      ["set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", keychainPassword, keychain.path],
      cwd: repository.root, redactedArgumentIndexes: [5]
    )
    let identities = try ProcessRunner.capture(
      "/usr/bin/security", ["find-identity", "-v", "-p", "codesigning", keychain.path],
      cwd: repository.root
    )
    guard identities.contains(ReleaseContract.certificateSHA1), identities.contains(ReleaseContract.identityName) else {
      throw OpsError.failed("fixed release signing identity was not imported")
    }
  }

  private static func verifySignedApp(
    _ app: URL,
    repository: Repository,
    version: String,
    build: String,
    sha: String,
    fingerprint: String
  ) throws {
    try ProcessRunner.run(
      "/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=4", app.path],
      cwd: repository.root
    )
    let details = try ProcessRunner.capture("/usr/bin/codesign", ["-dvvv", app.path], cwd: repository.root)
    guard details.contains("Authority=\(ReleaseContract.identityName)"),
          details.contains("Identifier=\(ReleaseContract.bundleID)"),
          details.contains("runtime"),
          !details.contains("Signature=adhoc")
    else { throw OpsError.failed("release signature does not match the fixed identity") }
    guard try certificateFingerprint(app: app, repository: repository) == ReleaseContract.certificateSHA256 else {
      throw OpsError.failed("release certificate SHA-256 mismatch")
    }
    let requirement = try ProcessRunner.capture(
      "/usr/bin/codesign", ["-d", "-r-", app.path], cwd: repository.root
    )
    let expectedRequirement = "identifier \"\(ReleaseContract.bundleID)\" and certificate leaf = H\"\(ReleaseContract.certificateSHA1.lowercased())\""
    guard requirement.contains("designated => \(expectedRequirement)") else {
      throw OpsError.failed("release designated requirement mismatch")
    }
    let entitlementOutput = try ProcessRunner.capture(
      "/usr/bin/codesign", ["-d", "--entitlements", ":-", app.path], cwd: repository.root
    )
    guard let plistStart = entitlementOutput.range(of: "<?xml"),
          let plistEnd = entitlementOutput.range(of: "</plist>", options: .backwards),
          let entitlementData = String(entitlementOutput[plistStart.lowerBound ..< plistEnd.upperBound]).data(using: .utf8),
          let signedEntitlements = try PropertyListSerialization.propertyList(
            from: entitlementData, options: [], format: nil
          ) as? [String: Any],
          let expectedEntitlements = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: repository.root.appendingPathComponent("LexiRay/Resources/LexiRay.entitlements")),
            options: [], format: nil
          ) as? [String: Any],
          NSDictionary(dictionary: signedEntitlements).isEqual(to: expectedEntitlements)
    else { throw OpsError.failed("release signed entitlements mismatch") }
    let info = try plist(app.appendingPathComponent("Contents/Info.plist"))
    guard info["CFBundleIdentifier"] as? String == ReleaseContract.bundleID,
          info["CFBundleShortVersionString"] as? String == version,
          info["CFBundleVersion"] as? String == build
    else { throw OpsError.failed("release app metadata mismatch") }
    let attestation = try plist(app.appendingPathComponent("Contents/Resources/LexiRayRelease.plist"))
    guard attestation["source_commit"] as? String == sha,
          attestation["source_fingerprint"] as? String == fingerprint
    else { throw OpsError.failed("release source attestation mismatch") }
  }

  private static func verifyDMG(
    _ dmg: URL,
    repository: Repository,
    version: String,
    build: String,
    sha: String,
    fingerprint: String
  ) throws {
    try ProcessRunner.run("/usr/bin/hdiutil", ["verify", dmg.path], cwd: repository.root)
    let mountRoot = FileManager.default.temporaryDirectory.appendingPathComponent("lexiray-dmg-\(UUID().uuidString)")
    let mount = mountRoot.appendingPathComponent("mnt", isDirectory: true)
    try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
    defer {
      _ = try? ProcessRunner.run(
        "/usr/bin/hdiutil", ["detach", mount.path, "-quiet"],
        cwd: repository.root, capture: true, allowedExitCodes: [0, 1]
      )
      try? FileManager.default.removeItem(at: mountRoot)
    }
    try ProcessRunner.run(
      "/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-mountpoint", mount.path, "-quiet"],
      cwd: repository.root
    )
    try verifySignedApp(
      mount.appendingPathComponent("LexiRay.app"), repository: repository,
      version: version, build: build, sha: sha, fingerprint: fingerprint
    )
  }

  private static func certificateFingerprint(app: URL, repository: Repository) throws -> String {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lexiray-cert-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try ProcessRunner.run("/usr/bin/codesign", ["-d", "--extract-certificates", app.path], cwd: directory)
    return try Data(contentsOf: directory.appendingPathComponent("codesign0")).sha256.uppercased()
  }

  private static func plist(_ url: URL) throws -> [String: Any] {
    let object = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), options: [], format: nil)
    guard let dictionary = object as? [String: Any] else { throw OpsError.failed("invalid plist: \(url.path)") }
    return dictionary
  }
}

public enum ReleasePublisher {
  public static func publish(repository: Repository, version: String, sha: String, dmg: URL, checksum: URL) throws {
    guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
          ProcessInfo.processInfo.environment["GH_TOKEN"]?.isEmpty == false
    else { throw OpsError.failed("release publish is restricted to GitHub Actions with GH_TOKEN") }
    let resolvedSHA = try repository.resolve(sha)
    try verifyChecksum(dmg: dmg, checksum: checksum)
    let tag = "v\(version)"
    let existingTag = try remoteTagSHA(repository: repository, tag: tag)
    if let existingTag, existingTag != resolvedSHA {
      throw OpsError.failed("existing tag \(tag) points to \(existingTag), expected \(resolvedSHA)")
    }
    let existingRelease = try GitHubAPI.optional(
      "repos/\(ReleaseContract.repository)/releases/tags/\(tag)", jq: ".id", repository: repository
    )
    guard existingRelease == nil else { throw OpsError.failed("GitHub Release already exists for \(tag)") }

    var createdTag = false
    do {
      if existingTag == nil {
        try ProcessRunner.run(
          "/usr/bin/env",
          [
            "gh", "api", "--method", "POST", "repos/\(ReleaseContract.repository)/git/refs",
            "-f", "ref=refs/tags/\(tag)", "-f", "sha=\(resolvedSHA)"
          ],
          cwd: repository.root
        )
        createdTag = true
      }
      try ProcessRunner.run(
        "/usr/bin/env",
        [
          "gh", "release", "create", tag, dmg.path, checksum.path,
          "--repo", ReleaseContract.repository, "--title", "LexiRay \(tag)",
          "--generate-notes", "--draft"
        ],
        cwd: repository.root
      )
      try ProcessRunner.run(
        "/usr/bin/env",
        ["gh", "release", "edit", tag, "--repo", ReleaseContract.repository, "--draft=false", "--latest"],
        cwd: repository.root
      )
      let endpoint = "repos/\(ReleaseContract.repository)/releases/tags/\(tag)"
      let draft = try GitHubAPI.optional(endpoint, jq: ".draft", repository: repository)
      let assets = try GitHubAPI.optional(
        endpoint,
        jq: "[.assets[].name] | sort | join(\",\")",
        repository: repository
      )
      let expectedAssets = [dmg.lastPathComponent, checksum.lastPathComponent].sorted().joined(separator: ",")
      guard draft == "false", assets == expectedAssets else {
        throw OpsError.failed("published release state or asset set is incomplete")
      }
    } catch {
      let originalError = String(describing: error)
      var cleanupFailures: [String] = []
      do {
        if try GitHubAPI.optional(
          "repos/\(ReleaseContract.repository)/releases/tags/\(tag)", jq: ".id", repository: repository
        ) != nil {
          _ = try ProcessRunner.run(
            "/usr/bin/env", ["gh", "release", "delete", tag, "--repo", ReleaseContract.repository, "--yes"],
            cwd: repository.root, capture: true, allowedExitCodes: [0, 1]
          )
        }
        if try GitHubAPI.optional(
          "repos/\(ReleaseContract.repository)/releases/tags/\(tag)", jq: ".id", repository: repository
        ) != nil {
          cleanupFailures.append("GitHub Release \(tag) still exists")
        }
      } catch {
        cleanupFailures.append("release cleanup lookup/delete failed: \(error)")
      }
      if createdTag {
        do {
          _ = try ProcessRunner.run(
            "/usr/bin/env",
            ["gh", "api", "--method", "DELETE", "repos/\(ReleaseContract.repository)/git/refs/tags/\(tag)"],
            cwd: repository.root, capture: true, allowedExitCodes: [0, 1]
          )
          if try remoteTagSHA(repository: repository, tag: tag) != nil {
            cleanupFailures.append("tag \(tag) still exists")
          }
        } catch {
          cleanupFailures.append("tag cleanup failed: \(error)")
        }
      }
      if !cleanupFailures.isEmpty {
        throw OpsError.failed(
          "\(originalError)\nrelease cleanup was not verified:\n\(cleanupFailures.joined(separator: "\n"))"
        )
      }
      throw error
    }
  }

  private static func remoteTagSHA(repository: Repository, tag: String) throws -> String? {
    guard let value = try GitHubAPI.optional(
      "repos/\(ReleaseContract.repository)/commits/\(tag)", jq: ".sha", repository: repository
    ) else { return nil }
    guard value.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil else {
      throw OpsError.failed("GitHub returned an invalid SHA for \(tag)")
    }
    return value
  }

  private static func verifyChecksum(dmg: URL, checksum: URL) throws {
    let expected = try String(contentsOf: checksum, encoding: .utf8)
      .split(whereSeparator: \Character.isWhitespace).first.map(String.init)
    guard expected?.lowercased() == (try Data(contentsOf: dmg).sha256) else {
      throw OpsError.failed("release checksum does not match the DMG")
    }
  }
}
