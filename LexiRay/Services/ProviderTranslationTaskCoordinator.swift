import Foundation

@MainActor
final class ProviderTranslationTaskCoordinator {
  private var tasks: [String: Task<Void, Never>] = [:]
  private var generations: [String: UUID] = [:]

  func start(
    configurationID: String,
    operation: @escaping @MainActor @Sendable () async -> Void
  ) {
    cancel(configurationID)

    let generation = UUID()
    generations[configurationID] = generation
    tasks[configurationID] = Task { @MainActor [weak self] in
      await operation()
      self?.clearTask(configurationID, generation: generation)
    }
  }

  func cancel(_ configurationID: String) {
    tasks[configurationID]?.cancel()
    tasks[configurationID] = nil
    generations[configurationID] = nil
  }

  func cancelAll() {
    tasks.values.forEach { $0.cancel() }
    tasks = [:]
    generations = [:]
  }

  private func clearTask(_ configurationID: String, generation: UUID) {
    guard generations[configurationID] == generation else {
      return
    }

    tasks[configurationID] = nil
    generations[configurationID] = nil
  }
}
