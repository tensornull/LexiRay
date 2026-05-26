import Foundation

enum SourceMarkdownPreparer {
  static func prepare(_ rawText: String) -> String {
    guard let text = rawText.nonEmptyTrimmed else {
      return rawText
    }

    if containsFence(text) {
      return text
    }

    let blocks = paragraphBlocks(in: text)
    if blocks.count <= 1, let language = inferredCodeLanguage(for: text) {
      return fenced(text, language: language)
    }

    let preparedBlocks = blocks.map { block in
      guard let trimmed = block.nonEmptyTrimmed else {
        return block
      }
      guard let language = inferredCodeLanguage(for: trimmed) else {
        return block
      }
      return fenced(trimmed, language: language)
    }

    return preparedBlocks.joined(separator: "\n\n")
  }

  private static func containsFence(_ text: String) -> Bool {
    text.range(of: #"(?m)^\s*```"#, options: .regularExpression) != nil
  }

  private static func paragraphBlocks(in text: String) -> [String] {
    var blocks: [String] = []
    var currentLines: [String] = []

    for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
      if line.trimmedForQuery.isEmpty {
        if !currentLines.isEmpty {
          blocks.append(currentLines.joined(separator: "\n"))
          currentLines = []
        }
      } else {
        currentLines.append(line)
      }
    }

    if !currentLines.isEmpty {
      blocks.append(currentLines.joined(separator: "\n"))
    }

    return blocks
  }

  static func inferredCodeLanguage(for text: String) -> String? {
    let trimmed = text.trimmedForQuery
    if isValidJSON(trimmed) {
      return "json"
    }

    if looksLikeJSONFragment(trimmed) {
      return "json"
    }

    if looksLikeCodeOrLogBlock(trimmed) {
      return "text"
    }

    return nil
  }

  private static func isValidJSON(_ text: String) -> Bool {
    guard let data = text.data(using: .utf8),
          text.hasPrefix("{") && text.hasSuffix("}") || text.hasPrefix("[") && text.hasSuffix("]")
    else {
      return false
    }

    return (try? JSONSerialization.jsonObject(with: data)) != nil
  }

  private static func looksLikeJSONFragment(_ text: String) -> Bool {
    let lines = text.components(separatedBy: .newlines).filter { !$0.trimmedForQuery.isEmpty }
    guard lines.count >= 3 else {
      return false
    }

    let jsonishLines = lines.filter { line in
      let trimmed = line.trimmedForQuery
      return trimmed == "{"
        || trimmed == "}"
        || trimmed == "["
        || trimmed == "]"
        || trimmed.hasSuffix("{")
        || trimmed.hasSuffix("[")
        || trimmed.range(of: #"^"?[A-Za-z0-9_\- ]+"?\s*:"#, options: .regularExpression) != nil
    }

    return Double(jsonishLines.count) / Double(lines.count) >= 0.55
  }

  private static func looksLikeCodeOrLogBlock(_ text: String) -> Bool {
    let lines = text.components(separatedBy: .newlines).filter { !$0.trimmedForQuery.isEmpty }
    guard lines.count >= 3 else {
      return false
    }

    let structuredLines = lines.filter { line in
      let trimmed = line.trimmedForQuery
      return line.hasPrefix("  ")
        || line.hasPrefix("\t")
        || trimmed.hasPrefix("{")
        || trimmed.hasPrefix("}")
        || trimmed.hasPrefix("[")
        || trimmed.hasPrefix("]")
        || trimmed.contains("://")
        || trimmed.contains(" = ")
        || trimmed.contains(" -> ")
        || trimmed.range(of: #"^[A-Za-z0-9_.-]+:"#, options: .regularExpression) != nil
    }

    return Double(structuredLines.count) / Double(lines.count) >= 0.5
  }

  private static func fenced(_ text: String, language: String) -> String {
    """
    ```\(language)
    \(text)
    ```
    """
  }
}
