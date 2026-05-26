import Foundation

extension String {
  var trimmedForQuery: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var nonEmptyTrimmed: String? {
    let value = trimmedForQuery
    return value.isEmpty ? nil : value
  }

  var lineCount: Int {
    max(1, components(separatedBy: .newlines).count)
  }

  var trimmingSingleTrailingNewline: String {
    if hasSuffix("\r\n") {
      return String(dropLast(2))
    }
    if hasSuffix("\n") || hasSuffix("\r") {
      return String(dropLast())
    }
    return self
  }

  var removingMarkdownListMarker: String {
    replacingOccurrences(
      of: #"(?m)^\s{0,3}(?:[-*+]|\d+\.)\s+"#,
      with: "",
      options: .regularExpression
    )
  }

  var removingMarkdownContinuationIndent: String {
    components(separatedBy: .newlines)
      .map { line in
        if line.hasPrefix("    ") {
          return String(line.dropFirst(4))
        }
        if line.hasPrefix("  ") {
          return String(line.dropFirst(2))
        }
        return line
      }
      .joined(separator: "\n")
  }

  var normalizingMarkdownSmartQuotesForCode: String {
    replacingOccurrences(of: "“", with: "\"")
      .replacingOccurrences(of: "”", with: "\"")
      .replacingOccurrences(of: "‘", with: "'")
      .replacingOccurrences(of: "’", with: "'")
  }

  var fourCharCodeValue: FourCharCode {
    utf8.reduce(0) { result, character in
      (result << 8) + FourCharCode(character)
    }
  }
}
