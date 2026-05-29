import Foundation

struct TranslationHistoryFile: Codable, Equatable {
  var version: Int
  var entries: [TranslationHistoryItem]

  init(version: Int = 1, entries: [TranslationHistoryItem]) {
    self.version = version
    self.entries = entries
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
    entries = try container.decodeIfPresent([TranslationHistoryItem].self, forKey: .entries) ?? []
  }
}

final class TranslationHistoryStore {
  let fileURL: URL

  private let fileManager: FileManager

  init(
    fileURL: URL = TranslationHistoryStore.defaultFileURL(),
    fileManager: FileManager = .default
  ) {
    self.fileURL = fileURL
    self.fileManager = fileManager
  }

  static func defaultFileURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
    homeDirectory
      .appendingPathComponent(".lexiray", isDirectory: true)
      .appendingPathComponent("history.json", isDirectory: false)
  }

  func load(limit: Int) -> [TranslationHistoryItem] {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return []
    }

    do {
      let data = try Data(contentsOf: fileURL)
      let file = try JSONDecoder().decode(TranslationHistoryFile.self, from: data)
      let entries = pruned(file.entries, limit: limit)
      if entries.count != file.entries.count {
        save(entries, limit: limit)
      }
      return entries
    } catch {
      AppLog.settings.error("Failed to load translation history file: \(error.localizedDescription, privacy: .public)")
      return []
    }
  }

  @discardableResult
  func append(_ item: TranslationHistoryItem, to entries: [TranslationHistoryItem], limit: Int) -> [TranslationHistoryItem] {
    let updatedEntries = pruned(entries + [item], limit: limit)
    save(updatedEntries, limit: limit)
    return updatedEntries
  }

  @discardableResult
  func prune(_ entries: [TranslationHistoryItem], limit: Int) -> [TranslationHistoryItem] {
    let updatedEntries = pruned(entries, limit: limit)
    if updatedEntries.count != entries.count {
      save(updatedEntries, limit: limit)
    }
    return updatedEntries
  }

  func save(_ entries: [TranslationHistoryItem], limit: Int) {
    do {
      let directoryURL = fileURL.deletingLastPathComponent()
      try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
      try setPermissions(0o700, at: directoryURL)

      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(TranslationHistoryFile(entries: pruned(entries, limit: limit)))
      try data.write(to: fileURL, options: .atomic)
      try setPermissions(0o600, at: fileURL)
    } catch {
      AppLog.settings.error("Failed to save translation history file: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func pruned(_ entries: [TranslationHistoryItem], limit: Int) -> [TranslationHistoryItem] {
    let limit = SettingsStore.normalizedTranslationHistoryLimit(limit)
    guard entries.count > limit else {
      return entries
    }

    return Array(entries.suffix(limit))
  }

  private func setPermissions(_ permissions: Int, at url: URL) throws {
    try fileManager.setAttributes(
      [.posixPermissions: NSNumber(value: permissions)],
      ofItemAtPath: url.path
    )
  }
}
