import Foundation
import XCTest

/// In-memory UserDefaults for tests. Every typed NSUserDefaults accessor
/// funnels through the overridden primitives, so test values never reach
/// cfprefsd or ~/Library/Preferences — per-suite teardown cannot win the
/// race against cfprefsd's post-exit flush, which used to leak one plist per
/// test run. Leftovers from older runs are removed by
/// the test target's own teardown.
final class InMemoryScratchDefaults: UserDefaults, @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [String: Any] = [:]

  init() {
    // Bind to a sentinel scratch suite so an accessor that bypassed the
    // overridden primitives could never touch the real
    // io.github.tensornull.lexiray domain. The sentinel matches the
    // legacy scratch-file pattern in case it ever materializes on disk.
    super.init(suiteName: "LexiRayTestScratch-00000000-0000-0000-0000-000000000000")!
  }

  override func object(forKey defaultName: String) -> Any? {
    lock.lock()
    defer { lock.unlock() }
    return storage[defaultName]
  }

  override func set(_ value: Any?, forKey defaultName: String) {
    lock.lock()
    defer { lock.unlock() }
    if let value {
      storage[defaultName] = value
    } else {
      storage.removeValue(forKey: defaultName)
    }
  }

  override func removeObject(forKey defaultName: String) {
    lock.lock()
    defer { lock.unlock() }
    storage.removeValue(forKey: defaultName)
  }
}

/// Shared scratch-state helpers. Unit tests must not leave UserDefaults
/// domains in ~/Library/Preferences or directories in the temporary
/// directory behind.
extension XCTestCase {
  func makeScratchDefaults() -> UserDefaults {
    InMemoryScratchDefaults()
  }

  func makeScratchDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("LexiRayTestScratch-\(UUID().uuidString)", isDirectory: true)
    addTeardownBlock { @MainActor in
      // Let in-flight main-actor work finish first: a controller translation
      // task completing after the test can append history and recreate the
      // directory after it was removed.
      for _ in 0 ..< 20 {
        await Task.yield()
      }
      try? FileManager.default.removeItem(at: url)
    }
    return url
  }
}
