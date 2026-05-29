@testable import LexiRay
import XCTest

final class TranslationHistoryStoreTests: XCTestCase {
  func testAppendLoadAndPruneKeepsNewestEntries() {
    let store = makeStore()
    let first = makeHistoryItem(text: "one")
    let second = makeHistoryItem(text: "two")
    let third = makeHistoryItem(text: "three")

    var entries = store.append(first, to: [], limit: 2)
    entries = store.append(second, to: entries, limit: 2)
    entries = store.append(third, to: entries, limit: 2)

    let reloaded = store.load(limit: 2)
    XCTAssertEqual(reloaded.map(\.request.text), ["two", "three"])
  }

  func testCorruptedHistoryFileFallsBackToEmptyHistory() throws {
    let store = makeStore()
    try FileManager.default.createDirectory(
      at: store.fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("{".utf8).write(to: store.fileURL)

    XCTAssertEqual(store.load(limit: 100), [])
  }

  func testHistoryFilePermissions() throws {
    let store = makeStore()

    store.save([makeHistoryItem(text: "hello")], limit: 100)

    XCTAssertEqual(try permission(at: store.fileURL.deletingLastPathComponent()), 0o700)
    XCTAssertEqual(try permission(at: store.fileURL), 0o600)
  }

  private func makeStore() -> TranslationHistoryStore {
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("LexiRayHistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("history.json", isDirectory: false)
    return TranslationHistoryStore(fileURL: fileURL)
  }

  private func makeHistoryItem(text: String) -> TranslationHistoryItem {
    let request = TranslationHistoryRequest(
      text: text,
      sourceLanguage: "en",
      targetLanguage: "zh-Hans",
      selectionSource: .manual
    )
    return TranslationHistoryItem(
      request: request,
      entries: [
        TranslationHistoryEntry(
          providerConfigurationID: ProviderID.mock.rawValue,
          providerID: .mock,
          providerName: "Mock",
          status: .success(TranslationHistoryResult(translatedText: "translated \(text)"))
        )
      ]
    )
  }

  private func permission(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return try XCTUnwrap(attributes[.posixPermissions] as? Int) & 0o777
  }
}
