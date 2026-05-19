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

  var fourCharCodeValue: FourCharCode {
    utf8.reduce(0) { result, character in
      (result << 8) + FourCharCode(character)
    }
  }
}
