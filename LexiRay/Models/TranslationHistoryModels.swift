import Foundation

struct TranslationHistoryItem: Codable, Equatable, Identifiable {
  let id: UUID
  let createdAt: Date
  let request: TranslationHistoryRequest
  let entries: [TranslationHistoryEntry]

  init?(
    batch: TranslationBatch,
    id: UUID = UUID(),
    createdAt: Date = Date()
  ) {
    var entries: [TranslationHistoryEntry] = []
    for entry in batch.entries {
      guard let historyEntry = TranslationHistoryEntry(entry: entry) else {
        return nil
      }
      entries.append(historyEntry)
    }

    self.id = id
    self.createdAt = createdAt
    request = TranslationHistoryRequest(request: batch.request)
    self.entries = entries
  }

  init(
    id: UUID = UUID(),
    createdAt: Date = Date(),
    request: TranslationHistoryRequest,
    entries: [TranslationHistoryEntry]
  ) {
    self.id = id
    self.createdAt = createdAt
    self.request = request
    self.entries = entries
  }

  func restoredBatch() -> TranslationBatch {
    let restoredRequest = request.restoredRequest()
    return TranslationBatch(
      request: restoredRequest,
      entries: entries.map { $0.restoredEntry(request: restoredRequest) }
    )
  }
}

struct TranslationHistoryRequest: Codable, Equatable {
  let text: String
  let llmInputText: String
  let sourceLanguage: String?
  let targetLanguage: String
  let selectionSource: SelectionSource

  init(request: TranslationRequest) {
    text = request.text
    llmInputText = request.llmInputText
    sourceLanguage = request.sourceLanguage
    targetLanguage = request.targetLanguage
    selectionSource = request.selectionSource
  }

  init(
    text: String,
    llmInputText: String? = nil,
    sourceLanguage: String?,
    targetLanguage: String,
    selectionSource: SelectionSource
  ) {
    self.text = text
    self.llmInputText = llmInputText ?? text
    self.sourceLanguage = sourceLanguage
    self.targetLanguage = targetLanguage
    self.selectionSource = selectionSource
  }

  func restoredRequest() -> TranslationRequest {
    TranslationRequest(
      text: text,
      llmInputText: llmInputText,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      selectionSource: selectionSource
    )
  }
}

struct TranslationHistoryEntry: Codable, Equatable, Identifiable {
  let providerConfigurationID: String
  let providerID: ProviderID
  let providerName: String
  let status: TranslationHistoryEntryStatus

  var id: String {
    providerConfigurationID
  }

  init?(entry: ProviderTranslationEntry) {
    guard let status = TranslationHistoryEntryStatus(status: entry.status) else {
      return nil
    }

    providerConfigurationID = entry.providerConfigurationID
    providerID = entry.providerID
    providerName = entry.providerName
    self.status = status
  }

  init(
    providerConfigurationID: String,
    providerID: ProviderID,
    providerName: String,
    status: TranslationHistoryEntryStatus
  ) {
    self.providerConfigurationID = providerConfigurationID
    self.providerID = providerID
    self.providerName = providerName
    self.status = status
  }

  func restoredEntry(request: TranslationRequest) -> ProviderTranslationEntry {
    ProviderTranslationEntry(
      providerConfigurationID: providerConfigurationID,
      providerID: providerID,
      providerName: providerName,
      status: status.restoredStatus(
        request: request,
        providerConfigurationID: providerConfigurationID,
        providerID: providerID,
        providerName: providerName
      )
    )
  }
}

enum TranslationHistoryEntryStatus: Codable, Equatable {
  case disabled
  case success(TranslationHistoryResult)
  case failure(String)

  private enum CodingKeys: String, CodingKey {
    case type
    case result
    case message
  }

  private enum StatusType: String, Codable {
    case disabled
    case success
    case failure
  }

  init?(status: ProviderTranslationStatus) {
    switch status {
    case .disabled:
      self = .disabled
    case .translating, .streaming:
      return nil
    case let .success(result):
      self = .success(TranslationHistoryResult(result: result))
    case let .failure(message):
      self = .failure(message)
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(StatusType.self, forKey: .type)
    switch type {
    case .disabled:
      self = .disabled
    case .success:
      self = try .success(container.decode(TranslationHistoryResult.self, forKey: .result))
    case .failure:
      self = try .failure(container.decode(String.self, forKey: .message))
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .disabled:
      try container.encode(StatusType.disabled, forKey: .type)
    case let .success(result):
      try container.encode(StatusType.success, forKey: .type)
      try container.encode(result, forKey: .result)
    case let .failure(message):
      try container.encode(StatusType.failure, forKey: .type)
      try container.encode(message, forKey: .message)
    }
  }

  func restoredStatus(
    request: TranslationRequest,
    providerConfigurationID: String,
    providerID: ProviderID,
    providerName: String
  ) -> ProviderTranslationStatus {
    switch self {
    case .disabled:
      .disabled
    case let .success(result):
      .success(
        TranslationResult(
          request: request,
          providerConfigurationID: providerConfigurationID,
          providerID: providerID,
          providerName: providerName,
          translatedText: result.translatedText,
          detectedLanguage: result.detectedLanguage,
          createdAt: result.createdAt
        )
      )
    case let .failure(message):
      .failure(message)
    }
  }
}

struct TranslationHistoryResult: Codable, Equatable {
  let translatedText: String
  let detectedLanguage: String?
  let createdAt: Date

  init(result: TranslationResult) {
    translatedText = result.translatedText
    detectedLanguage = result.detectedLanguage
    createdAt = result.createdAt
  }

  init(
    translatedText: String,
    detectedLanguage: String? = nil,
    createdAt: Date = Date()
  ) {
    self.translatedText = translatedText
    self.detectedLanguage = detectedLanguage
    self.createdAt = createdAt
  }
}

extension ProviderTranslationStatus {
  var isTerminalHistoryStatus: Bool {
    switch self {
    case .disabled, .success, .failure:
      true
    case .translating, .streaming:
      false
    }
  }

  var isRecordedHistoryStatus: Bool {
    switch self {
    case .success, .failure:
      true
    case .disabled, .translating, .streaming:
      false
    }
  }
}
