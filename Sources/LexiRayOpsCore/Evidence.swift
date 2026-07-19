import Foundation

public struct EvidenceArtifact: Codable, Equatable, Sendable {
  public let path: String
  public let sha256: String
}

public struct EvidenceRecord: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let id: String
  public let createdAt: String
  public let sourceFingerprint: String
  public let command: String
  public let scenarios: [String]
  public let result: String
  public let rootCause: String?
  public let retryOf: String?
  public let log: String?
  public let artifacts: [EvidenceArtifact]
}

public final class EvidenceStore: @unchecked Sendable {
  private let repository: Repository
  private let baseURL: URL
  private let encoder: JSONEncoder
  private let decoder = JSONDecoder()

  public init(repository: Repository) {
    self.repository = repository
    baseURL = repository.root.appendingPathComponent("build/verification", isDirectory: true)
    encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  }

  @discardableResult
  public func write(
    command: String,
    scenarios: [String],
    result: String,
    rootCause: String? = nil,
    retryOf: String? = nil,
    log: String? = nil,
    artifactURLs: [URL] = []
  ) throws -> URL {
    let fingerprint = try repository.sourceFingerprint()
    let existingRecords = try allRecords()
    if let retryOf {
      try validateRetry(id: retryOf, command: command, rootCause: rootCause, records: existingRecords)
    } else if let existing = existingRecords.first(where: {
      $0.sourceFingerprint == fingerprint && $0.command == command
    }) {
      if existing.result == "passed" {
        throw OpsError.failed("command already passed for this source fingerprint: \(existing.id)")
      }
      throw OpsError.failed(
        "command already failed for this source fingerprint; retry with --retry-of \(existing.id) --cause <root-cause>"
      )
    } else if let latestFailure = existingRecords
      .filter({ $0.command == command })
      .max(by: { $0.createdAt < $1.createdAt }),
      latestFailure.result != "passed"
    {
      throw OpsError.failed(
        "the previous command failed; source changes still require --retry-of \(latestFailure.id) --cause <root-cause>"
      )
    }

    let id = UUID().uuidString.lowercased()
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let createdAt = formatter.string(from: Date())
    let buildRoot = repository.root.appendingPathComponent("build", isDirectory: true).standardizedFileURL.path + "/"
    let artifacts = try artifactURLs.map { url in
        let canonical = url.standardizedFileURL
        guard canonical.path.hasPrefix(buildRoot),
              FileManager.default.fileExists(atPath: canonical.path)
        else { throw OpsError.failed("evidence artifact must exist below the repository build directory: \(url.path)") }
        let values = try canonical.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
          throw OpsError.failed("evidence artifact must be a regular non-symlink file: \(url.path)")
        }
        let relative = relativePath(for: canonical)
        return EvidenceArtifact(path: relative, sha256: try Data(contentsOf: canonical).sha256)
      }
      .sorted { $0.path < $1.path }

    let record = EvidenceRecord(
      schemaVersion: 1,
      id: id,
      createdAt: createdAt,
      sourceFingerprint: fingerprint,
      command: command,
      scenarios: scenarios,
      result: result,
      rootCause: rootCause,
      retryOf: retryOf,
      log: log,
      artifacts: artifacts
    )
    let directory = baseURL.appendingPathComponent(fingerprint, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let safeStamp = createdAt.replacingOccurrences(of: ":", with: "-")
    let destination = directory.appendingPathComponent("\(safeStamp)-\(id).json")
    try encoder.encode(record).write(to: destination, options: [.atomic])
    return destination
  }

  public func artifacts(below directory: URL, extensions: Set<String> = ["png"]) -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
      options: [.skipsHiddenFiles]
    ) else { return [] }
    return enumerator.compactMap { item in
      guard let url = item as? URL,
            extensions.contains(url.pathExtension.lowercased()),
            (try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]).isRegularFile) == true,
            (try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]).isSymbolicLink) != true
      else { return nil }
      return url
    }.sorted { $0.path < $1.path }
  }

  private func validateRetry(
    id: String,
    command: String,
    rootCause: String?,
    records: [EvidenceRecord]
  ) throws {
    guard let rootCause, !rootCause.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw OpsError.failed("a retry requires a non-empty --cause")
    }
    guard let original = records.first(where: { $0.id == id }) else {
      throw OpsError.failed("retry evidence not found: \(id)")
    }
    guard original.result != "passed" else {
      throw OpsError.failed("successful evidence cannot be retried: \(id)")
    }
    guard original.command == command else {
      throw OpsError.failed("retry command differs from \(id); start a new run instead")
    }
    guard records.contains(where: { $0.retryOf == id }) == false else {
      throw OpsError.failed("the failure \(id) has already been retried once")
    }
  }

  private func allRecords() throws -> [EvidenceRecord] {
    guard FileManager.default.fileExists(atPath: baseURL.path) else { return [] }
    guard let enumerator = FileManager.default.enumerator(at: baseURL, includingPropertiesForKeys: nil) else { return [] }
    var records: [EvidenceRecord] = []
    for case let url as URL in enumerator where url.pathExtension == "json" {
      do {
        records.append(try decoder.decode(EvidenceRecord.self, from: Data(contentsOf: url)))
      } catch {
        throw OpsError.failed("invalid immutable evidence record at \(url.path): \(error)")
      }
    }
    return records
  }

  private func relativePath(for url: URL) -> String {
    let root = repository.root.standardizedFileURL.path + "/"
    let path = url.standardizedFileURL.path
    return path.hasPrefix(root) ? String(path.dropFirst(root.count)) : path
  }
}
