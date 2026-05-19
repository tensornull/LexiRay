import Foundation

struct ServerSentEvent: Equatable, Sendable {
  let event: String?
  let data: String
}

struct ServerSentEventParser {
  private var eventName: String?
  private var dataLines: [String] = []

  mutating func consume(_ rawLine: String) -> ServerSentEvent? {
    consumeEvents(rawLine).first
  }

  mutating func consumeEvents(_ rawLine: String) -> [ServerSentEvent] {
    let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
    guard !line.isEmpty else {
      return flush().map { [$0] } ?? []
    }

    guard !line.hasPrefix(":") else {
      return []
    }

    let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    let field = String(parts[0])
    var value = parts.count > 1 ? String(parts[1]) : ""
    if value.hasPrefix(" ") {
      value.removeFirst()
    }

    let flushed = shouldFlushBeforeProcessing(field: field, value: value) ? flush() : nil

    switch field {
    case "event":
      eventName = value.isEmpty ? nil : value
    case "data":
      dataLines.append(value)
    default:
      break
    }

    return flushed.map { [$0] } ?? []
  }

  mutating func finish() -> ServerSentEvent? {
    flush()
  }

  private mutating func flush() -> ServerSentEvent? {
    defer {
      eventName = nil
      dataLines = []
    }

    guard eventName != nil || !dataLines.isEmpty else {
      return nil
    }

    return ServerSentEvent(event: eventName, data: dataLines.joined(separator: "\n"))
  }

  private func shouldFlushBeforeProcessing(field: String, value: String) -> Bool {
    guard eventName != nil || !dataLines.isEmpty else {
      return false
    }

    if field == "event" {
      return !dataLines.isEmpty
    }

    if field == "data" {
      return isStandaloneEventData(dataLines.joined(separator: "\n")) && isStandaloneEventData(value)
    }

    return false
  }

  private func isStandaloneEventData(_ value: String) -> Bool {
    let trimmed = value.trimmedForQuery
    guard !trimmed.isEmpty else {
      return false
    }

    if trimmed == "[DONE]" {
      return true
    }

    guard let data = trimmed.data(using: .utf8) else {
      return false
    }

    return (try? JSONSerialization.jsonObject(with: data)) != nil
  }
}
