import Foundation

public struct ValidationPlan: Codable, Equatable, Sendable {
  public let changedFiles: [String]
  public let runOpsTests: Bool
  public let buildApp: Bool
  public let runUnitTests: Bool
  public let selectedUnitTests: [String]
  public let selectedGUIScenarios: [String]
  public let fullGUIReason: String?
  public let systemAcceptanceScenarios: [String]

  public var requiresGUI: Bool { fullGUIReason != nil || !selectedGUIScenarios.isEmpty }
  public var requiresSystemAcceptance: Bool { !systemAcceptanceScenarios.isEmpty }
}

public enum ChangeClassifier {
  private struct MutablePlan {
    var ops = false
    var build = false
    var unit = false
    var unitTests = Set<String>()
    var gui = Set<String>()
    var fullGUIReason: String?
    var system = Set<String>()
  }

  public static func classify(_ paths: [String]) throws -> ValidationPlan {
    var plan = MutablePlan()
    var unknown: [String] = []

    for path in paths {
      if classify(path, into: &plan) == false { unknown.append(path) }
    }
    guard unknown.isEmpty else {
      throw OpsError.failed(
        "unclassified changed paths; add an explicit path-to-verification mapping:\n" +
          unknown.sorted().map { "  \($0)" }.joined(separator: "\n")
      )
    }

    if plan.fullGUIReason != nil { plan.gui.removeAll() }
    return ValidationPlan(
      changedFiles: paths.sorted(),
      runOpsTests: plan.ops,
      buildApp: plan.build,
      runUnitTests: plan.unit,
      selectedUnitTests: plan.unitTests.sorted(),
      selectedGUIScenarios: plan.gui.sorted(),
      fullGUIReason: plan.fullGUIReason,
      systemAcceptanceScenarios: plan.system.sorted()
    )
  }

  private static func classify(_ path: String, into plan: inout MutablePlan) -> Bool {
    if path == "AGENTS.md" || path == ".gitignore" || path == ".swiftformat" ||
      path == "README.md" || path == "CONTRIBUTING.md" || path == "ROADMAP.md" || path == "CHANGELOG.md" ||
      path == "LICENSE" || path.hasPrefix(".agents/") || path.hasPrefix(".github/")
    {
      plan.ops = true
      return true
    }

    if path == "Package.swift" || path == "Package.resolved" || path == "project.yml" {
      plan.ops = true
      plan.build = true
      plan.unit = true
      return true
    }

    if path.hasPrefix("Tests/LexiRayOpsCoreTests/") || path == "Sources/LexiRayOps/main.swift" {
      plan.ops = true
      return true
    }

    if path.hasPrefix("Sources/LexiRayOpsCore/") {
      plan.ops = true
      if path.hasSuffix("GUIRunner.swift") {
        plan.fullGUIReason = "runner-change"
      }
      if path.hasSuffix("Installer.swift") {
        plan.system.formUnion(["install-identity", "launch"])
      }
      return true
    }

    if path.hasPrefix("Tools/LexiRayGUI/") {
      plan.ops = true
      if path.hasPrefix("Tools/LexiRayGUI/scenarios/"), path.hasSuffix(".swift") {
        plan.gui.insert(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
      } else {
        plan.fullGUIReason = "runner-change"
      }
      return true
    }

    if path.hasPrefix("LexiRayTests/") {
      plan.build = true
      plan.unit = true
      if path.hasSuffix("Tests.swift") {
        plan.unitTests.insert(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
      }
      return true
    }

    guard path.hasPrefix("LexiRay/") else { return false }
    plan.build = true

    if path == "LexiRay/Resources/Info.plist" {
      plan.ops = true
      return true
    }
    if path == "LexiRay/Resources/LexiRay.entitlements" {
      plan.unit = true
      plan.system.insert("signing-install-lifecycle")
      return true
    }
    if path.hasPrefix("LexiRay/Resources/") {
      plan.gui.insert("launch")
      return true
    }

    plan.unit = true
    addMatchingUnitTest(for: path, to: &plan)

    let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    if containsAny(name, ["FloatingPanel", "WindowReporting", "PanelPosition", "PanelSize"]) {
      plan.fullGUIReason = "shared-ui"
      return true
    }
    if containsAny(name, ["LoginItem", "AppRuntime", "AppDelegate"]) {
      plan.system.formUnion(["install-identity", "launch"])
      plan.gui.insert("launch")
      return true
    }
    if containsAny(name, ["GlobalHotKey", "TextSelection", "Selection"]) {
      plan.system.formUnion(["global-hotkey", "selection"])
      plan.gui.insert("selection_translate")
      return true
    }
    if name.contains("OCR") {
      plan.system.insert("ocr")
      plan.gui.formUnion(["ocr_permission_gate", "ocr_multi_display"])
      return true
    }
    if name.contains("Speech") {
      plan.system.insert("speech")
      plan.gui.formUnion(["speech_controls", "rich_result_wrap"])
      return true
    }
    if name.contains("History") {
      plan.gui.insert("history_nav")
      return true
    }
    if containsAny(name, ["Provider", "TranslationPipeline", "HTTPClient", "Streaming"]) {
      plan.gui.formUnion(["providers", "streaming_growth"])
      return true
    }
    if containsAny(name, ["Language", "SourceTextEditor"]) {
      plan.gui.formUnion(["source_editor", "language_direction_input"])
      return true
    }
    if containsAny(name, ["RichTranslation", "Markdown"]) {
      plan.gui.insert("rich_result_wrap")
      return true
    }
    if path.hasPrefix("LexiRay/Views/") || path.hasPrefix("LexiRay/App/") {
      plan.gui.formUnion(["launch", "panel_blank"])
      return true
    }
    if path.hasPrefix("LexiRay/Models/") || path.hasPrefix("LexiRay/Stores/") ||
      path.hasPrefix("LexiRay/Services/") || path.hasPrefix("LexiRay/Support/")
    {
      return true
    }
    return false
  }

  private static func addMatchingUnitTest(for path: String, to plan: inout MutablePlan) {
    let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    plan.unitTests.insert("\(name)Tests")
    if containsAny(name, ["Controller", "FloatingPanel", "TextSelection", "GlobalHotKey", "Speech"]) {
      plan.unitTests.insert("ControllerInteractionTests")
    }
    if name.contains("AppIdentity") { plan.unitTests.insert("AppIdentityTests") }
    if containsAny(name, ["OpenAICompatibleProvider", "HTTPClient", "TranslationProvider", "ProviderTranslationTaskCoordinator"]) {
      plan.unitTests.insert("LLMProviderTests")
    }
    if containsAny(name, ["RichTranslation", "SourceMarkdown"]) {
      plan.unitTests.insert("RichTranslationRendererTests")
    }
    if name.contains("Language") {
      plan.unitTests.formUnion(["LanguageDetectorTests", "TranslationPipelineTests"])
    }
    if name.contains("Settings") { plan.unitTests.insert("SettingsStoreTests") }
    if name.contains("OCR") { plan.unitTests.insert("OCRServiceTests") }
  }

  private static func containsAny(_ value: String, _ needles: [String]) -> Bool {
    needles.contains { value.contains($0) }
  }
}
