import Foundation

struct ServerSentEvent: Equatable, Sendable {
  let event: String?
  let data: String
}

struct ServerSentEventParser {
  private var eventName: String?
  private var dataLines: [String] = []

  mutating func consume(_ rawLine: String) -> ServerSentEvent? {
    let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
    guard !line.isEmpty else {
      return flush()
    }

    guard !line.hasPrefix(":") else {
      return nil
    }

    let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    let field = String(parts[0])
    var value = parts.count > 1 ? String(parts[1]) : ""
    if value.hasPrefix(" ") {
      value.removeFirst()
    }

    switch field {
    case "event":
      eventName = value.isEmpty ? nil : value
    case "data":
      dataLines.append(value)
    default:
      break
    }

    return nil
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
}
