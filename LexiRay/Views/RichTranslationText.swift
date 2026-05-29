import AppKit
import Markdown
import SwiftUI

struct RichTranslationText: View {
  let text: String
  var font: Font
  var lineLimit: Int?

  var body: some View {
    RichTranslationContentView(text: text, font: font, lineLimit: lineLimit)
  }
}

struct RichTranslationContentView: View {
  let text: String
  var font: Font
  var lineLimit: Int?

  private var blocks: [RichTranslationBlock] {
    RichTranslationRenderer.blocks(for: text)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
        blockView(block)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  @ViewBuilder
  private func blockView(_ block: RichTranslationBlock) -> some View {
    switch block {
    case let .text(content):
      RichInlineTextView(content: content, font: font, lineLimit: lineLimit)
    case let .heading(level, content):
      RichInlineTextView(content: content, font: headingFont(level: level), lineLimit: nil)
    case let .listItem(index, content):
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(index.map { "\($0)." } ?? "•")
          .font(font)
          .foregroundStyle(Color.accentColor)
          .frame(width: index == nil ? 12 : 24, alignment: .trailing)
        RichInlineTextView(content: content, font: font, lineLimit: nil)
      }
      .padding(.vertical, 1)
    case let .quote(content):
      HStack(alignment: .top, spacing: 10) {
        Rectangle()
          .fill(Color.accentColor.opacity(0.65))
          .frame(width: 3)
        RichInlineTextView(content: content, font: font, lineLimit: nil)
          .foregroundStyle(.secondary)
      }
      .padding(.vertical, 5)
      .padding(.horizontal, 8)
      .background(Color.accentColor.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
    case let .code(language, code):
      TranslationCodeBlockView(language: language, code: code)
    }
  }

  private func headingFont(level: Int) -> Font {
    switch level {
    case 1:
      .title3.weight(.semibold)
    case 2:
      .headline.weight(.semibold)
    default:
      font.weight(.semibold)
    }
  }
}

private struct RichInlineTextView: View {
  let content: RichInlineContent
  let font: Font
  let lineLimit: Int?

  var body: some View {
    Group {
      if content.segments.contains(where: \.isCode) {
        RichInlineFlowTextView(content: content, font: font)
      } else {
        Text(content.attributed)
          .font(font)
          .lineLimit(lineLimit)
      }
    }
    .textSelection(.enabled)
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }
}

private struct RichInlineFlowTextView: View {
  let content: RichInlineContent
  let font: Font

  private var tokens: [RichInlineToken] {
    content.segments.flatMap { segment -> [RichInlineToken] in
      switch segment {
      case let .text(attributed):
        textTokens(from: attributed).map { RichInlineToken.text($0) }
      case let .code(text):
        [.code(text)]
      }
    }
  }

  var body: some View {
    InlineFlowLayout(verticalSpacing: 5) {
      ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
        switch token {
        case let .text(attributed):
          Text(attributed)
            .font(font)
        case let .code(text):
          InlineCodeChip(text: text)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private func textTokens(from attributed: AttributedString) -> [AttributedString] {
    guard !attributed.characters.isEmpty else {
      return []
    }

    var tokens: [AttributedString] = []
    var tokenStart = attributed.startIndex
    var tokenIsWhitespace: Bool?
    var index = attributed.startIndex

    while index < attributed.endIndex {
      let character = attributed.characters[index]
      let isWhitespace = character.isInlineWhitespace
      if tokenIsWhitespace == nil {
        tokenIsWhitespace = isWhitespace
        tokenStart = index
      } else if tokenIsWhitespace != isWhitespace {
        tokens.append(AttributedString(attributed[tokenStart ..< index]))
        tokenStart = index
        tokenIsWhitespace = isWhitespace
      }
      index = attributed.characters.index(after: index)
    }

    tokens.append(AttributedString(attributed[tokenStart ..< attributed.endIndex]))
    return tokens.filter { !$0.characters.isEmpty }
  }
}

private enum RichInlineToken {
  case text(AttributedString)
  case code(String)
}

private struct InlineCodeChip: View {
  @Environment(\.colorScheme) private var colorScheme

  let text: String

  var body: some View {
    Text(text)
      .font(.system(.body, design: .monospaced).weight(.medium))
      .foregroundStyle(.primary)
      .lineLimit(1)
      .padding(.horizontal, 5)
      .padding(.vertical, 1.5)
      .background(backgroundColor, in: RoundedRectangle(cornerRadius: 4))
      .overlay {
        RoundedRectangle(cornerRadius: 4)
          .stroke(borderColor, lineWidth: 1)
      }
  }

  private var backgroundColor: Color {
    colorScheme == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.075)
  }

  private var borderColor: Color {
    colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.12)
  }
}

private struct InlineFlowLayout: Layout {
  var verticalSpacing: CGFloat

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache _: inout ()
  ) -> CGSize {
    let maxWidth = proposal.width ?? .greatestFiniteMagnitude
    var lineWidth: CGFloat = 0
    var lineHeight: CGFloat = 0
    var totalWidth: CGFloat = 0
    var totalHeight: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if lineWidth > 0, lineWidth + size.width > maxWidth {
        totalWidth = max(totalWidth, lineWidth)
        totalHeight += lineHeight + verticalSpacing
        lineWidth = 0
        lineHeight = 0
      }
      lineWidth += size.width
      lineHeight = max(lineHeight, size.height)
    }

    totalWidth = max(totalWidth, lineWidth)
    totalHeight += lineHeight

    return CGSize(
      width: proposal.width.map { min(max(totalWidth, 0), $0) } ?? totalWidth,
      height: totalHeight
    )
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal _: ProposedViewSize,
    subviews: Subviews,
    cache _: inout ()
  ) {
    let maxWidth = bounds.width
    var x = bounds.minX
    var y = bounds.minY
    var lineHeight: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x > bounds.minX, x + size.width > bounds.minX + maxWidth {
        x = bounds.minX
        y += lineHeight + verticalSpacing
        lineHeight = 0
      }
      subview.place(
        at: CGPoint(x: x, y: y),
        proposal: ProposedViewSize(width: size.width, height: size.height)
      )
      x += size.width
      lineHeight = max(lineHeight, size.height)
    }
  }
}

private extension Character {
  var isInlineWhitespace: Bool {
    unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
  }
}

struct TranslationCodeBlockView: View {
  @Environment(\.colorScheme) private var colorScheme

  let language: String?
  let code: String

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        Text((language?.nonEmptyTrimmed ?? "code").uppercased())
          .font(.system(.caption2, design: .monospaced).weight(.semibold))
          .foregroundStyle(.secondary)
        Spacer(minLength: 8)
      }
      .padding(.horizontal, 11)
      .padding(.vertical, 6)
      .background(headerBackground)

      ScrollView(.horizontal, showsIndicators: true) {
        Text(code)
          .font(.system(size: 13, weight: .regular, design: .monospaced))
          .lineSpacing(3)
          .foregroundStyle(.primary)
          .textSelection(.enabled)
          .fixedSize(horizontal: true, vertical: true)
          .padding(.horizontal, 12)
          .padding(.vertical, 11)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background(blockBackground, in: RoundedRectangle(cornerRadius: 7))
    .overlay {
      RoundedRectangle(cornerRadius: 7)
        .stroke(borderColor, lineWidth: 1)
    }
    .clipShape(RoundedRectangle(cornerRadius: 7))
  }

  private var blockBackground: Color {
    colorScheme == .dark ? Color.white.opacity(0.075) : Color.black.opacity(0.045)
  }

  private var headerBackground: Color {
    colorScheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.05)
  }

  private var borderColor: Color {
    colorScheme == .dark ? Color.white.opacity(0.13) : Color.black.opacity(0.11)
  }
}

enum RichTranslationBlock: Equatable {
  case text(RichInlineContent)
  case heading(Int, RichInlineContent)
  case listItem(Int?, RichInlineContent)
  case quote(RichInlineContent)
  case code(language: String?, code: String)
}

struct RichInlineContent: Equatable {
  let attributed: AttributedString
  let segments: [RichInlineSegment]

  var characters: AttributedString.CharacterView {
    attributed.characters
  }

  var plainString: String {
    segments.map(\.plainString).joined()
  }
}

enum RichInlineSegment: Equatable {
  case text(AttributedString)
  case code(String)

  var plainString: String {
    switch self {
    case let .text(attributed):
      String(attributed.characters)
    case let .code(text):
      text
    }
  }

  var isCode: Bool {
    if case .code = self {
      return true
    }
    return false
  }
}

enum RichTranslationRenderer {
  static func blocks(for text: String) -> [RichTranslationBlock] {
    if looksLikeHTML(text), let html = htmlAttributedString(for: text) {
      return [.text(RichInlineContent(attributed: html, segments: [.text(html)]))]
    }

    if let language = SourceMarkdownPreparer.inferredCodeLanguage(for: text), !looksLikeMarkdown(text) {
      return [.code(language: language, code: text)]
    }

    let markdown = markdownPreparedForRendering(text)
    if looksLikeMarkdown(markdown) {
      let document = Document(parsing: markdownPreservingVisibleLineBreaks(markdown))
      let rendered = document.children.flatMap(renderBlock)
      if !rendered.isEmpty {
        return rendered
      }
    }

    let attributed = AttributedString(text)
    return [.text(RichInlineContent(attributed: attributed, segments: [.text(attributed)]))]
  }

  static func attributedString(for text: String) -> AttributedString {
    if looksLikeHTML(text), let html = htmlAttributedString(for: text) {
      return html
    }

    let renderableMarkdown = markdownPreparedForRendering(text)
    if looksLikeMarkdown(renderableMarkdown),
       let markdown = try? AttributedString(markdown: markdownPreservingVisibleLineBreaks(renderableMarkdown))
    {
      return styledInlineContent(markdown).attributed
    }

    return AttributedString(text)
  }

  static func plainString(for text: String) -> String {
    blocks(for: text).map { block in
      switch block {
      case let .text(content), let .heading(_, content), let .listItem(_, content), let .quote(content):
        content.plainString
      case let .code(_, code):
        code
      }
    }
    .joined(separator: "\n")
  }

  static func htmlString(for text: String) -> String {
    if looksLikeHTML(text) {
      return sanitizedHTML(text)
    }

    let attributed = NSAttributedString(attributedString(for: text))
    let range = NSRange(location: 0, length: attributed.length)
    guard let data = try? attributed.data(
      from: range,
      documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
    ), let html = String(data: data, encoding: .utf8) else {
      return "<p>\(escapeHTML(plainString(for: text)))</p>"
    }

    return sanitizedHTML(html)
  }

  static func sanitizedHTML(_ html: String) -> String {
    var sanitized = html
    sanitized = replacingMatches(
      in: sanitized,
      pattern: #"<(script|style|iframe|object|embed|img)\b[^>]*>.*?</\1>"#,
      options: [.caseInsensitive, .dotMatchesLineSeparators],
      with: ""
    )
    sanitized = replacingMatches(
      in: sanitized,
      pattern: #"<(script|style|iframe|object|embed|img)\b[^>]*?/?>"#,
      options: [.caseInsensitive, .dotMatchesLineSeparators],
      with: ""
    )
    sanitized = replacingMatches(
      in: sanitized,
      pattern: #"\s+on[a-z]+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)"#,
      options: [.caseInsensitive],
      with: ""
    )
    sanitized = replacingMatches(
      in: sanitized,
      pattern: #"\s+(href|src)\s*=\s*("javascript:[^"]*"|'javascript:[^']*'|javascript:[^\s>]+)"#,
      options: [.caseInsensitive],
      with: ""
    )
    return sanitized
  }

  static func markdownPreservingVisibleLineBreaks(_ markdown: String) -> String {
    let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var result: [String] = []
    var isInFence = false

    for index in lines.indices {
      let line = lines[index]
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      let isFenceLine = trimmed.hasPrefix("```")

      result.append(line)

      if isFenceLine {
        isInFence.toggle()
      }

      guard index < lines.index(before: lines.endIndex), !isInFence, !isFenceLine else {
        continue
      }

      let nextLine = lines[lines.index(after: index)]
      if shouldPreserveVisibleBreak(after: line, before: nextLine) {
        result[result.index(before: result.endIndex)] += "  "
      }
    }

    return result.joined(separator: "\n")
  }

  private static func markdownPreparedForRendering(_ text: String) -> String {
    guard looksLikeMarkdown(text), !looksLikeHTML(text), !containsCodeFence(text) else {
      return text
    }

    let restoredBlocks = restoreCollapsedMarkdownBlockBreaks(in: text)
    return splitCollapsedHeadingProse(in: restoredBlocks)
  }

  private static func restoreCollapsedMarkdownBlockBreaks(in text: String) -> String {
    var restored = text
    restored = replacingMatches(
      in: restored,
      pattern: #"([^\n])\s+(#{1,6}\s+)"#,
      options: [],
      with: "$1\n$2"
    )

    if hasMarkdownBlockHeading(restored) || countMatches(in: restored, pattern: #"(?m)(?:^|\s)(?:[-*+]\s+(?!\d{4}-\d{2}-\d{2})|\d+\.\s+)\S"#) >= 2 {
      restored = replacingMatches(
        in: restored,
        pattern: #"([^\n])\s+((?:[-*+]\s+(?!\d{4}-\d{2}-\d{2})|\d+\.\s+)(?=\S))"#,
        options: [],
        with: "$1\n$2"
      )
    }

    if hasMarkdownBlockHeading(restored) || countMatches(in: restored, pattern: #"\s>\s+\S"#) >= 1 {
      restored = replacingMatches(
        in: restored,
        pattern: #"([^\n])\s+(>\s+(?=\S))"#,
        options: [],
        with: "$1\n$2"
      )
    }

    return restored
  }

  private static func splitCollapsedHeadingProse(in text: String) -> String {
    text
      .split(separator: "\n", omittingEmptySubsequences: false)
      .flatMap { splitCollapsedHeadingLine(String($0)) }
      .joined(separator: "\n")
  }

  private static func splitCollapsedHeadingLine(_ line: String) -> [String] {
    guard let match = firstMatch(in: line, pattern: #"^(#{1,6})\s+(\S+)\s+(.+)$"#),
          let markerRange = Range(match.range(at: 1), in: line),
          let titleRange = Range(match.range(at: 2), in: line),
          let remainderRange = Range(match.range(at: 3), in: line)
    else {
      return [line]
    }

    let marker = String(line[markerRange])
    let title = String(line[titleRange])
    let remainder = String(line[remainderRange])
    guard title.count <= 32, looksLikeCollapsedHeadingRemainder(remainder) else {
      return [line]
    }

    return ["\(marker) \(title)", remainder]
  }

  private static func looksLikeCollapsedHeadingRemainder(_ text: String) -> Bool {
    text.range(of: #"^((?:[-*+]\s+(?!\d{4}-\d{2}-\d{2})|\d+\.\s+)|>\s+|#{1,6}\s+)"#, options: .regularExpression) != nil
      || text.range(of: #"\[[^\]\n]+\]\([^)]+\)"#, options: .regularExpression) != nil
      || text.range(of: #"[。！？.!?]"#, options: .regularExpression) != nil
      || text.count >= 60
  }

  private static func renderBlock(_ markup: Markup) -> [RichTranslationBlock] {
    switch markup {
    case let heading as Heading:
      [.heading(heading.level, inlineContent(for: heading))]
    case let paragraph as Paragraph:
      renderProseWithStructuredTail(
        paragraph.format().trimmedForQuery,
        textBlock: { .text($0) }
      )
    case let codeBlock as CodeBlock:
      [.code(language: codeBlock.language, code: codeBlock.code.trimmingSingleTrailingNewline)]
    case let unorderedList as UnorderedList:
      unorderedList.children.flatMap { renderListItem($0, index: nil) }
    case let orderedList as OrderedList:
      orderedList.children.enumerated().flatMap { offset, item in
        renderListItem(item, index: offset + 1)
      }
    case let blockQuote as BlockQuote:
      [.quote(inlineContent(for: blockQuote))]
    default:
      markup.children.flatMap(renderBlock)
    }
  }

  private static func renderListItem(_ item: Markup, index: Int?) -> [RichTranslationBlock] {
    let children = Array(item.children)
    if children.count >= 2,
       let paragraph = children[0] as? Paragraph,
       let codeBlock = children[1] as? CodeBlock
    {
      let prose = paragraph.format().trimmedForQuery.removingMarkdownListMarker
      if prose.hasSuffix("{") || prose.hasSuffix("[") {
        let marker = String(prose.suffix(1))
        let trimmedProse = String(prose.dropLast()).trimmedForQuery
        let code = [marker, codeBlock.code.trimmingSingleTrailingNewline]
          .joined(separator: "\n")
          .removingMarkdownContinuationIndent
        return [
          .listItem(index, inlineContent(forMarkdown: trimmedProse)),
          .code(language: SourceMarkdownPreparer.inferredCodeLanguage(for: code) ?? codeBlock.language, code: code)
        ]
      }
    }

    return renderProseWithStructuredTail(
      item.format().trimmedForQuery.removingMarkdownListMarker,
      textBlock: { .listItem(index, $0) }
    )
  }

  private static func renderProseWithStructuredTail(
    _ markdown: String,
    textBlock: (RichInlineContent) -> RichTranslationBlock
  ) -> [RichTranslationBlock] {
    guard let split = splitStructuredTail(in: markdown) else {
      return [textBlock(inlineContent(forMarkdown: markdown))]
    }

    var blocks: [RichTranslationBlock] = []
    if !split.prose.isEmpty {
      blocks.append(textBlock(inlineContent(forMarkdown: split.prose)))
    }
    blocks.append(.code(language: split.language, code: split.code))
    return blocks
  }

  private static func splitStructuredTail(in markdown: String) -> (prose: String, language: String, code: String)? {
    let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard lines.count >= 3 else {
      return nil
    }

    for index in lines.indices {
      if let sameLineSplit = splitStructuredTailStartingOnLine(lines: lines, index: index) {
        return sameLineSplit
      }

      let tail = lines[index...].joined(separator: "\n").trimmedForQuery.removingMarkdownContinuationIndent
      let code = tail.normalizingMarkdownSmartQuotesForCode
      guard let language = SourceMarkdownPreparer.inferredCodeLanguage(for: code) else {
        continue
      }

      var prose = lines[..<index].joined(separator: "\n").trimmedForQuery
      guard !prose.isEmpty else {
        return nil
      }

      var normalizedCode = code
      if prose.hasSuffix("{") || prose.hasSuffix("[") {
        let marker = String(prose.suffix(1))
        prose = String(prose.dropLast()).trimmedForQuery
        normalizedCode = [marker, normalizedCode].joined(separator: "\n")
      }

      return (prose: prose, language: language, code: normalizedCode)
    }

    return nil
  }

  private static func splitStructuredTailStartingOnLine(
    lines: [String],
    index: Int
  ) -> (prose: String, language: String, code: String)? {
    let line = lines[index]
    guard let markerRange = line.range(of: #"[\{\[]"#, options: .regularExpression),
          markerRange.lowerBound > line.startIndex
    else {
      return nil
    }

    let tailFirstLine = String(line[markerRange.lowerBound...])
    let tail = ([tailFirstLine] + Array(lines[(index + 1)...]))
      .joined(separator: "\n")
      .trimmedForQuery
      .removingMarkdownContinuationIndent
      .normalizingMarkdownSmartQuotesForCode
    guard let language = SourceMarkdownPreparer.inferredCodeLanguage(for: tail) else {
      return nil
    }

    let proseFirstLine = String(line[..<markerRange.lowerBound]).trimmedForQuery
    let prose = (Array(lines[..<index]) + [proseFirstLine])
      .joined(separator: "\n")
      .trimmedForQuery
    guard !prose.isEmpty else {
      return nil
    }

    return (prose: prose, language: language, code: tail)
  }

  private static func inlineContent(for markup: Markup) -> RichInlineContent {
    inlineContent(forMarkdown: markup.format().trimmedForQuery)
  }

  private static func inlineContent(forMarkdown markdown: String) -> RichInlineContent {
    if let attributed = try? AttributedString(markdown: markdownPreservingVisibleLineBreaks(markdown)) {
      return styledInlineContent(attributed)
    }
    return RichInlineContent(attributed: AttributedString(markdown), segments: [.text(AttributedString(markdown))])
  }

  static func inlineSegments(forMarkdown markdown: String) -> [RichInlineSegment] {
    inlineContent(forMarkdown: markdown).segments
  }

  private static func styledInlineContent(_ base: AttributedString) -> RichInlineContent {
    var attributed = base
    let segments = inlineSegments(from: attributed)
    let codeRanges = attributed.runs.compactMap { run -> Range<AttributedString.Index>? in
      guard run.inlinePresentationIntent?.contains(.code) == true else {
        return nil
      }
      return run.range
    }

    for range in codeRanges {
      attributed[range].font = .system(.body, design: .monospaced)
      attributed[range].backgroundColor = Color.accentColor.opacity(0.12)
      attributed[range].foregroundColor = Color.primary
    }

    return RichInlineContent(attributed: attributed, segments: segments)
  }

  private static func inlineSegments(from attributed: AttributedString) -> [RichInlineSegment] {
    var segments: [RichInlineSegment] = []

    for run in attributed.runs {
      let runText = AttributedString(attributed[run.range])
      if run.inlinePresentationIntent?.contains(.code) == true {
        segments.append(.code(String(runText.characters)))
      } else {
        segments.append(.text(runText))
      }
    }

    return coalescedInlineSegments(segments)
  }

  private static func coalescedInlineSegments(_ segments: [RichInlineSegment]) -> [RichInlineSegment] {
    var coalesced: [RichInlineSegment] = []

    for segment in segments {
      switch (coalesced.last, segment) {
      case let (.code(previous)?, .code(current)):
        coalesced[coalesced.index(before: coalesced.endIndex)] = .code(previous + current)
      case let (.text(previous)?, .text(current)):
        var merged = previous
        merged.append(current)
        coalesced[coalesced.index(before: coalesced.endIndex)] = .text(merged)
      default:
        coalesced.append(segment)
      }
    }

    return coalesced
  }

  private static func looksLikeHTML(_ text: String) -> Bool {
    htmlDetectionText(for: text).range(
      of: #"<[A-Za-z][A-Za-z0-9:-]*(\s|>|/)"#,
      options: .regularExpression
    ) != nil
  }

  private static func htmlDetectionText(for text: String) -> String {
    let withoutFences = replacingMatches(
      in: text,
      pattern: #"(?s)```.*?```"#,
      options: [],
      with: ""
    )
    return replacingMatches(
      in: withoutFences,
      pattern: #"`[^`\n]*`"#,
      options: [],
      with: ""
    )
  }

  private static func containsCodeFence(_ text: String) -> Bool {
    text.range(of: #"```"#, options: .regularExpression) != nil
  }

  private static func hasMarkdownBlockHeading(_ text: String) -> Bool {
    text.range(of: #"(?m)^\s{0,3}#{1,6}\s+"#, options: .regularExpression) != nil
  }

  private static func looksLikeMarkdown(_ text: String) -> Bool {
    let patterns = [
      #"(?m)^\s{0,3}#{1,6}\s+"#,
      #"(?m)^\s{0,3}([-*+]|\d+\.)\s+"#,
      #"(?m)^\s{0,3}>\s+"#,
      #"```"#,
      #"`[^`\n]+`"#,
      #"\*\*[^*\n]+\*\*"#,
      #"__[^_\n]+__"#,
      #"\[[^\]\n]+\]\([^)]+\)"#
    ]

    return patterns.contains { pattern in
      text.range(of: pattern, options: .regularExpression) != nil
    }
  }

  private static func shouldPreserveVisibleBreak(after line: String, before nextLine: String) -> Bool {
    if line.isEmpty || nextLine.isEmpty {
      return false
    }

    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.hasSuffix("  ") || trimmed.hasSuffix("\\") {
      return false
    }

    return true
  }

  private static func htmlAttributedString(for html: String) -> AttributedString? {
    let sanitized = sanitizedHTML(html)
    guard let data = sanitized.data(using: .utf8) else {
      return nil
    }

    guard let attributed = try? NSAttributedString(
      data: data,
      options: [
        .documentType: NSAttributedString.DocumentType.html,
        .characterEncoding: String.Encoding.utf8.rawValue
      ],
      documentAttributes: nil
    ) else {
      return nil
    }

    return AttributedString(attributed)
  }

  private static func replacingMatches(
    in text: String,
    pattern: String,
    options: NSRegularExpression.Options,
    with replacement: String
  ) -> String {
    guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
      return text
    }

    let range = NSRange(text.startIndex ..< text.endIndex, in: text)
    return expression.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
  }

  private static func countMatches(in text: String, pattern: String) -> Int {
    guard let expression = try? NSRegularExpression(pattern: pattern) else {
      return 0
    }

    let range = NSRange(text.startIndex ..< text.endIndex, in: text)
    return expression.numberOfMatches(in: text, range: range)
  }

  private static func firstMatch(in text: String, pattern: String) -> NSTextCheckingResult? {
    guard let expression = try? NSRegularExpression(pattern: pattern) else {
      return nil
    }

    let range = NSRange(text.startIndex ..< text.endIndex, in: text)
    return expression.firstMatch(in: text, range: range)
  }

  private static func escapeHTML(_ text: String) -> String {
    text
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&#39;")
  }
}
