@testable import LexiRay
import XCTest

final class RichTranslationRendererTests: XCTestCase {
  func testMarkdownRendersToExpectedPlainString() {
    let rendered = RichTranslationRenderer.plainString(for: "**Bold**\n\n- one\n- `two`")

    XCTAssertTrue(rendered.contains("Bold"))
    XCTAssertTrue(rendered.contains("one"))
    XCTAssertTrue(rendered.contains("two"))
  }

  func testPlainTextPreservesLineBreaks() {
    let text = "First line\nSecond line\n\nFourth line"

    XCTAssertEqual(RichTranslationRenderer.plainString(for: text), text)
  }

  func testMarkdownPreservesVisibleLineBreaks() {
    let rendered = RichTranslationRenderer.plainString(for: "**Bold**\nNext line")

    XCTAssertEqual(rendered, "Bold\nNext line")
  }

  func testMarkdownRendersInlineFormatting() {
    let rendered = RichTranslationRenderer.attributedString(for: "**Bold** and `code` [link](https://example.test)")

    XCTAssertEqual(String(rendered.characters), "Bold and code link")
    XCTAssertTrue(rendered.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
    XCTAssertTrue(rendered.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
    XCTAssertTrue(rendered.runs.contains { $0.link?.absoluteString == "https://example.test" })
  }

  func testMarkdownInlineCodeBuildsCodeSegments() {
    let segments = RichTranslationRenderer.inlineSegments(
      forMarkdown: "For `<content>` and `POST /v1/videos`, use `input_reference`."
    )
    let codes = segments.compactMap { segment in
      if case let .code(text) = segment {
        return text
      }
      return nil
    }

    XCTAssertEqual(codes, ["<content>", "POST /v1/videos", "input_reference"])
    XCTAssertEqual(
      RichTranslationRenderer.plainString(for: "For `<content>` and `POST /v1/videos`, use `input_reference`."),
      "For <content> and POST /v1/videos, use input_reference."
    )
  }

  func testMarkdownInlineCodeSegmentsAppearInParagraphListAndQuote() {
    let blocks = RichTranslationRenderer.blocks(for: """
    Paragraph `POST /v1/videos`

    - List `input_reference`

    > Quote `<content>`
    """)

    XCTAssertTrue(blocks.contains { block in
      if case let .text(content) = block {
        return content.segments.contains(.code("POST /v1/videos"))
      }
      return false
    })
    XCTAssertTrue(blocks.contains { block in
      if case let .listItem(_, content) = block {
        return content.segments.contains(.code("input_reference"))
      }
      return false
    })
    XCTAssertTrue(blocks.contains { block in
      if case let .quote(content) = block {
        return content.segments.contains(.code("<content>"))
      }
      return false
    })
  }

  func testMarkdownBuildsBlockModel() {
    let blocks = RichTranslationRenderer.blocks(for: """
    ## Title

    - one
    - two

    > quoted

    ```json
    {"ok": true}
    ```
    """)

    XCTAssertTrue(blocks.contains { if case .heading(2, _) = $0 { true } else { false } })
    XCTAssertEqual(blocks.count(where: { if case .listItem = $0 { true } else { false } }), 2)
    XCTAssertTrue(blocks.contains { if case .quote = $0 { true } else { false } })
    XCTAssertTrue(blocks.contains { if case .code("json", #"{"ok": true}"#) = $0 { true } else { false } })
  }

  func testCollapsedChangelogMarkdownBuildsBlockModel() {
    let markdown = "# 更新日志 本项目的所有显著变更都将记录在此文件中。 格式基于 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)，并且本项目遵循 [语义化版本控制](https://semver.org/spec/v2.0.0.html)。 ## [0.3.0] - 2026-05-26 ### 新增 - `models` 现在默认读取公共模型目录。 - `model info` 显示模型的详细目录元数据。"

    let blocks = RichTranslationRenderer.blocks(for: markdown)
    let plain = RichTranslationRenderer.plainString(for: markdown)

    XCTAssertTrue(blocks.contains { if case let .heading(1, text) = $0 { String(text.characters) == "更新日志" } else { false } })
    XCTAssertTrue(blocks.contains { if case .heading(2, _) = $0 { true } else { false } })
    XCTAssertTrue(blocks.contains { if case .heading(3, _) = $0 { true } else { false } })
    XCTAssertEqual(blocks.count(where: { if case .listItem = $0 { true } else { false } }), 2)
    XCTAssertTrue(plain.contains("Keep a Changelog"))
    XCTAssertTrue(plain.contains("models 现在默认读取公共模型目录。"))
    XCTAssertFalse(plain.contains("# 更新日志"))
    XCTAssertFalse(plain.contains("[Keep a Changelog]("))
    XCTAssertFalse(plain.contains("`models`"))
  }

  func testCometAPIMarkdownFixtureBuildsReadableBlocks() {
    let markdown = """
    Hello,

    For `doubao-seedance-2-0` on CometAPI, the current public `POST /v1/videos` reference-file support is:

    - Image references: use multipart field `input_reference`
    - Multiple image references: repeat the same `input_reference` field in upload order
    - Video references: not currently exposed as a multipart reference field on this Seedance route
    - Audio references: not currently exposed as a multipart reference field on this Seedance route

    Uploaded files are mapped by order, not by the local filename or by a separate marker field.

    ```bash
    export COMETAPI_KEY="YOUR_COMETAPI_KEY"

    curl -sS https://api.cometapi.com/v1/videos \\
      -H "Authorization: Bearer $COMETAPI_KEY"
    ```

    Poll the returned `id` / `task_id`:

    ```bash
    curl -sS "https://api.cometapi.com/v1/videos/TASK_ID" \\
      -H "Authorization: Bearer $COMETAPI_KEY"
    ```
    """

    let blocks = RichTranslationRenderer.blocks(for: markdown)
    let plain = RichTranslationRenderer.plainString(for: markdown)

    XCTAssertEqual(blocks.count(where: { if case .listItem = $0 { true } else { false } }), 4)
    XCTAssertEqual(blocks.count(where: { if case .code("bash", _) = $0 { true } else { false } }), 2)
    XCTAssertTrue(plain.contains("doubao-seedance-2-0"))
    XCTAssertTrue(plain.contains("POST /v1/videos"))
    XCTAssertTrue(plain.contains("curl -sS"))
    XCTAssertFalse(plain.contains("`doubao-seedance-2-0`"))
    XCTAssertFalse(plain.contains("- Image references"))
    XCTAssertFalse(plain.contains("```bash"))
  }

  func testStructuredPlainTextBuildsCodeBlock() {
    let blocks = RichTranslationRenderer.blocks(for: """
    {
      "type": "error",
      "message": "failed"
    }
    """)

    XCTAssertEqual(blocks, [
      .code(language: "json", code: """
      {
        "type": "error",
        "message": "failed"
      }
      """)
    ])
  }

  func testListItemWithJSONTailBuildsCodeBlock() {
    let blocks = RichTranslationRenderer.blocks(for: """
    - Message is: {
        "type": "error",
        "message": "failed"
      }
    """)

    XCTAssertTrue(blocks.contains { if case .listItem = $0 { true } else { false } })
    XCTAssertTrue(blocks.contains { if case let .code("json", code) = $0 { code.contains(#""type": "error""#) } else { false } })
  }

  func testMarkdownFenceContentIsNotHardBreakRewritten() {
    let markdown = """
    ```swift
    let first = 1
    let second = 2
    ```
    Done
    """

    let prepared = RichTranslationRenderer.markdownPreservingVisibleLineBreaks(markdown)

    XCTAssertTrue(prepared.contains("let first = 1\nlet second = 2"))
    XCTAssertFalse(prepared.contains("let first = 1  \nlet second = 2"))
    XCTAssertEqual(RichTranslationRenderer.plainString(for: markdown), "let first = 1\nlet second = 2\nDone")
  }

  func testHTMLRendersToExpectedPlainString() {
    let rendered = RichTranslationRenderer.plainString(for: "<p>Hello <strong>world</strong></p><a href=\"https://example.test\">Link</a>")

    XCTAssertTrue(rendered.contains("Hello world"))
    XCTAssertTrue(rendered.contains("Link"))
  }

  func testUnsafeHTMLIsRemovedBeforeRendering() {
    let sanitized = RichTranslationRenderer.sanitizedHTML(
      #"<p onclick="alert(1)">Safe</p><script>alert(1)</script><img src="https://example.test/a.png"><a href="javascript:alert(1)">bad</a>"#
    )

    XCTAssertFalse(sanitized.localizedCaseInsensitiveContains("<script"))
    XCTAssertFalse(sanitized.localizedCaseInsensitiveContains("<img"))
    XCTAssertFalse(sanitized.localizedCaseInsensitiveContains("onclick"))
    XCTAssertFalse(sanitized.localizedCaseInsensitiveContains("javascript:"))
    XCTAssertTrue(sanitized.contains("Safe"))
  }

  func testPlainTextFallsBackWithoutChangingContent() {
    let text = "Plain < text without an HTML tag"

    XCTAssertEqual(RichTranslationRenderer.plainString(for: text), text)
  }
}
