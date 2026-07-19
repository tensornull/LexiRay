import Foundation
import Testing
@testable import LexiRayOpsCore

@Test func metadataNeverSelectsGUI() throws {
  let plan = try ChangeClassifier.classify([
    "CHANGELOG.md",
    "CONTRIBUTING.md",
    "LexiRay/Resources/Info.plist",
    ".github/workflows/release.yml"
  ])
  #expect(plan.runOpsTests)
  #expect(plan.requiresGUI == false)
  #expect(plan.requiresSystemAcceptance == false)
}

@Test func ordinaryViewSelectsOnlyAffectedScenarios() throws {
  let plan = try ChangeClassifier.classify(["LexiRay/Views/LanguagePickerView.swift"])
  #expect(plan.fullGUIReason == nil)
  #expect(plan.selectedGUIScenarios.contains("language_direction_input"))
  #expect(plan.selectedGUIScenarios.contains("source_editor"))
}

@Test func sharedPanelAndRunnerSelectFullGUI() throws {
  let panel = try ChangeClassifier.classify(["LexiRay/Views/FloatingPanelView.swift"])
  #expect(panel.fullGUIReason == "shared-ui")
  let runner = try ChangeClassifier.classify(["Sources/LexiRayOpsCore/GUIRunner.swift"])
  #expect(runner.fullGUIReason == "runner-change")
}

@Test func systemBoundaryIsExplicit() throws {
  let plan = try ChangeClassifier.classify(["LexiRay/Services/OCRService.swift"])
  #expect(plan.systemAcceptanceScenarios == ["ocr"])
  #expect(Set(plan.selectedGUIScenarios) == Set(["ocr_multi_display", "ocr_permission_gate"]))
}

@Test func unknownPathFailsClosed() {
  #expect(throws: OpsError.self) {
    _ = try ChangeClassifier.classify(["Unmapped/new-control-plane.file"])
  }
}

@Test func evidenceIsImmutableAndAllowsOneDiagnosedRetry() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("lexiray-evidence-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root.appendingPathComponent("LexiRay"), withIntermediateDirectories: true)
  try Data("fixture".utf8).write(to: root.appendingPathComponent("LexiRay/file.swift"))
  _ = try ProcessRunner.run("/usr/bin/git", ["init"], cwd: root, capture: true)
  _ = try ProcessRunner.run("/usr/bin/git", ["add", "LexiRay/file.swift"], cwd: root, capture: true)

  let repository = Repository(root: root)
  let store = EvidenceStore(repository: repository)
  let firstURL = try store.write(command: "gui run launch", scenarios: ["launch"], result: "failed")
  let decoder = JSONDecoder()
  let firstData = try Data(contentsOf: firstURL)
  let first = try decoder.decode(EvidenceRecord.self, from: firstData)
  #expect(throws: OpsError.self) {
    _ = try store.write(command: "gui run launch", scenarios: ["launch"], result: "failed")
  }
  try Data("fixture-fixed".utf8).write(to: root.appendingPathComponent("LexiRay/file.swift"), options: .atomic)
  #expect(throws: OpsError.self) {
    _ = try store.write(command: "gui run launch", scenarios: ["launch"], result: "passed")
  }
  let retryURL = try store.write(
    command: "gui run launch", scenarios: ["launch"], result: "passed",
    rootCause: "window readiness race fixed", retryOf: first.id
  )
  #expect(firstURL != retryURL)
  #expect(try Data(contentsOf: firstURL) == firstData)
  #expect(throws: OpsError.self) {
    _ = try store.write(
      command: "gui run launch", scenarios: ["launch"], result: "passed",
      rootCause: "another retry", retryOf: first.id
    )
  }
}

@Test func sourceFingerprintIncludesUntrackedAndDeletedInputs() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("lexiray-fingerprint-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: root) }
  let sourceDirectory = root.appendingPathComponent("LexiRay", isDirectory: true)
  try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
  let tracked = sourceDirectory.appendingPathComponent("tracked.swift")
  try Data("tracked".utf8).write(to: tracked)
  _ = try ProcessRunner.run("/usr/bin/git", ["init"], cwd: root, capture: true)
  _ = try ProcessRunner.run("/usr/bin/git", ["add", "LexiRay/tracked.swift"], cwd: root, capture: true)
  let repository = Repository(root: root)
  let initial = try repository.sourceFingerprint()

  try Data("untracked".utf8).write(to: sourceDirectory.appendingPathComponent("new.swift"))
  let withUntracked = try repository.sourceFingerprint()
  #expect(withUntracked != initial)

  try FileManager.default.removeItem(at: tracked)
  let withDeletion = try repository.sourceFingerprint()
  #expect(withDeletion != withUntracked)
}

@Test func releasePRAttemptsCountCurrentRunOnce() throws {
  let data = Data(
    """
    {"workflow_runs":[
      {"id":11,"pull_requests":[{"number":7}]},
      {"id":12,"pull_requests":[{"number":8}]}
    ]}
    """.utf8
  )
  #expect(try ReleasePRAttemptGate.attemptCount(from: data, pullRequestNumber: 7, currentRunID: 11) == 1)
  #expect(try ReleasePRAttemptGate.attemptCount(from: data, pullRequestNumber: 7, currentRunID: 13) == 2)
}

@Test func failedInstallStillWritesImmutableEvidence() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("lexiray-install-evidence-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root.appendingPathComponent("LexiRay"), withIntermediateDirectories: true)
  try Data("fixture".utf8).write(to: root.appendingPathComponent("LexiRay/file.swift"))
  _ = try ProcessRunner.run("/usr/bin/git", ["init"], cwd: root, capture: true)
  _ = try ProcessRunner.run("/usr/bin/git", ["add", "LexiRay/file.swift"], cwd: root, capture: true)

  #expect(throws: OpsError.self) {
    _ = try Installer.install(
      repository: Repository(root: root),
      source: root.appendingPathComponent("missing.app"),
      retryOf: nil,
      rootCause: nil
    )
  }
  let evidenceRoot = root.appendingPathComponent("build/verification")
  let enumerator = FileManager.default.enumerator(at: evidenceRoot, includingPropertiesForKeys: nil)
  let recordURL = try #require(enumerator?.compactMap { $0 as? URL }.first(where: { $0.pathExtension == "json" }))
  let record = try JSONDecoder().decode(EvidenceRecord.self, from: Data(contentsOf: recordURL))
  #expect(record.result == "failed")
  #expect(record.command.contains("missing.app"))
}

@Test func failedCommandRedactsSensitiveArguments() throws {
  do {
    _ = try ProcessRunner.run(
      "/usr/bin/false", ["visible", "super-secret"],
      cwd: FileManager.default.temporaryDirectory,
      capture: true,
      redactedArgumentIndexes: [1]
    )
    Issue.record("false unexpectedly succeeded")
  } catch {
    let description = String(describing: error)
    #expect(description.contains("visible"))
    #expect(description.contains("<redacted>"))
    #expect(description.contains("super-secret") == false)
  }
}

@Test func releaseMetadataMustMatch() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("lexiray-release-preflight-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: root) }
  let resources = root.appendingPathComponent("LexiRay/Resources", isDirectory: true)
  try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
  let plist: [String: Any] = ["CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "7"]
  try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    .write(to: resources.appendingPathComponent("Info.plist"))
  try "## [1.2.3]\n".write(to: root.appendingPathComponent("CHANGELOG.md"), atomically: true, encoding: .utf8)
  let metadata = try ValidationExecutor.releasePreflight(repository: Repository(root: root), requestedVersion: "1.2.3")
  #expect(metadata.version == "1.2.3")
  #expect(metadata.build == "7")
  #expect(throws: OpsError.self) {
    _ = try ValidationExecutor.releasePreflight(repository: Repository(root: root), requestedVersion: "1.2.4")
  }
}

@Test func repositoryHasOneBoundedRemotePath() throws {
  let repository = try Repository.discover()
  try ValidationExecutor.lintControlPlane(repository: repository)
  let workflow = try String(
    contentsOf: repository.root.appendingPathComponent(".github/workflows/release.yml"),
    encoding: .utf8
  )
  #expect(workflow.contains("pull_request:"))
  #expect(workflow.contains("workflow_dispatch:"))
  #expect(workflow.contains("timeout-minutes: 10"))
  #expect(workflow.contains("timeout-minutes: 20"))
  #expect(workflow.contains("name: release-ci"))
  #expect(workflow.contains("--pr-number"))
  #expect(workflow.contains("close-failed-pr"))
  #expect(workflow.contains("gui run") == false)
  #expect(workflow.contains("lexiray-ops install") == false)
  #expect(workflow.contains("lexiray-ops accept") == false)
}
