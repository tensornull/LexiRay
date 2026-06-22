# LexiRay Agent Instructions

## Product Goal

LexiRay is a clean-room macOS selection translation app. The user wants the most pleasant macOS translation workflow, with lower UI weight and better UX than older selection-translation tools.

## Non-Negotiables

- Keep the project Swift-only unless the user explicitly approves another language.
- Use SwiftUI for app surfaces and small AppKit bridges for macOS-only edges.
- Do not copy EasyDict source code, assets, UI implementation, or Objective-C.
- Keep changes surgical and minimal.
- Every meaningful change must build or test before handoff.
- Do not commit local `.codex/`, build artifacts, DerivedData, generated Xcode
  projects, xcresults, or release outputs.

## Agent Assets

- Repo-local skills and reusable prompts live under `.agents/`.
- `.agents/skills/lexiray-install-applications/SKILL.md` is the canonical
  installed-app preview workflow.
- `.codex/skills` and `.codex/prompts` are compatibility symlinks only; edit
  `.agents/skills` and `.agents/prompts` first.

## Roadmap and Progress

- `ROADMAP.md` is the single source of truth for phases, tasks, status, known
  issues, and decisions. Conversation plans and session todo lists are
  ephemeral; if work matters beyond the current session, it must be reflected
  in `ROADMAP.md`.
- When starting or finishing a roadmap task, update its status in the same
  change. Newly discovered durable issues go to the Backlog section.
- Handoffs for non-trivial work must reference the roadmap items they touched.

## Operating Discipline

- Inspect the current files, diffs, and branch state before deciding. Do not rely
  on memory, stale assumptions, or prior conversation fragments when the repo can
  answer the question.
- Keep every task to the smallest complete loop the user asked for. Do not add
  speculative features, broad refactors, or unrelated cleanup while fixing one
  issue.
- Treat a dirty worktree as user-owned state. Preserve unrelated changes, mention
  them when relevant, and edit only the files required for the current request.
- When intent or facts are unclear, state the concrete assumption or ask one
  focused question. Do not silently choose between meaningful interpretations.
- For longer tasks, give short progress updates that say what is being checked,
  what changed, and what is blocking progress. Avoid vague status messages.

## Self-Iteration Loop

- Treat repeated friction, user corrections, avoidable rework, missed verification,
  or unclear handoffs as process bugs. Do not wait for the user to ask for a rule
  update after the same pattern has caused frustration.
- When a durable, project-specific lesson emerges during work, update `AGENTS.md`
  in the same turn if the change is small, directly related to the current work,
  and would prevent a repeat mistake. Mention the doc update separately in the
  handoff.
- If the lesson is broader than the current task, changes policy, or could slow
  future work, propose the exact `AGENTS.md` wording instead of silently editing.
- Keep self-iteration edits concrete and enforceable: name the trigger, the
  required behavior, and the verification or handoff expectation. Avoid vague
  reminders like "be careful" or duplicate rules that already exist.
- At the end of non-trivial tasks, do a brief internal retro before final handoff:
  what caused delay, confusion, user correction, or failed verification; whether
  an existing rule covered it; and whether `AGENTS.md` needs a minimal update.

## Architecture Defaults

- `App/`: entrypoint and app lifecycle.
- `Views/`: SwiftUI surfaces.
- `Models/`: value models.
- `Stores/`: persisted settings and lightweight app state.
- `Services/`: translation, text selection, hotkeys, panels, speech, permissions.
- `Support/`: helpers, logging, constants.

Use `XcodeGen` to regenerate `LexiRay.xcodeproj`; do not hand-edit the generated project.

## Verification

Build and unit tests are necessary but not sufficient. Do not treat a mock-only
test, a text-box-only script, or a successful compile as UI acceptance.
Do not describe a change as done until the verification evidence matches the
behavior that changed.

Use the verification ladder. Run the cheapest level that covers the change,
and never skip a level the change touches:

- L0 — `swiftformat --lint` plus an incremental build after every edit batch.
- L1 — the unit tests covering the changed types
  (`xcodebuild test ... -only-testing:LexiRayTests/<TestClass>`).
- L2 — the GUI scenarios covering the changed behavior, with screenshots
  (see GUI Scenario Verification below). Required for any change to visible
  UI, floating panel, window, hotkey, selection, OCR, permission, or
  streaming behavior.
- L3 — `./script/ci_local.sh` before every push, PR, or release tag. It
  performs cleanup, `xcodegen generate`, `swiftformat --lint`, and the
  CI-equivalent `xcodebuild test` with `SWIFT_COMPILATION_MODE=wholemodule`.

Do not claim a change is CI-ready until L3 passes locally, unless the only
blocker is a clearly documented local machine/toolchain problem.

## GUI Scenario Verification

GUI acceptance runs through `script/ui/run.sh`, which drives the real
workspace-built app over the Accessibility API in small, independently
runnable scenarios:

```bash
./script/ui/run.sh --list                      # available scenarios
./script/ui/run.sh panel_blank history_nav    # run the affected scenarios
./script/ui/run.sh                            # full suite (pre-push)
./script/ui/run.sh --skip-build ...           # reuse the existing app build
```

Rules for every UI-affecting iteration:

- Run the scenarios that cover the changed behavior after each iteration, and
  the full suite before handing off or pushing.
- Scenarios write screenshots to `build/ui-artifacts/<timestamp>/`. Open and
  visually inspect every screenshot from the run — check layout, alignment,
  spacing, truncation, and copy — before claiming the UI is correct. A green
  exit code without inspected screenshots is not acceptance.
- The handoff must name the scenarios run and the screenshot directory, and
  state what each screenshot confirmed.
- New visible UI behavior needs a new or extended scenario in
  `script/ui/scenarios/` in the same change. Keep scenarios small and give new
  interactive controls accessibility identifiers so scenarios can reach them.
- Exit code 2 means blocked: the runner process lacks Accessibility
  permission, the GUI session is shielded, or a non-workspace LexiRay copy is
  running (it steals hotkeys and AX targeting). Pass `--quit-other-copies` to
  quit and restore other copies around the run, or report the blocker for
  one-time manual authorization; do not work around it and do not claim
  success.
- Scenario failures capture a `FAIL-<scenario>.png` full-screen frame in the
  artifact directory; start debugging from that frame.
- Computer Use remains the final acceptance layer for behavior the scenarios
  cannot reach (drag interactions, visual styling judgment, multi-display).
  Capture and inspect multiple screenshots across the relevant states.
- This machine can have multiple displays. `screencapture -x <file>` captures
  only the main display, and the OCR overlay spans the union of all screens,
  so union-relative centering is not main-display centering. When screenshot
  evidence looks wrong (content missing, misplaced), check `NSScreen.screens`
  before concluding the UI failed, and prefer numeric pixel checks over
  eyeballing subtle effects like the 28% dim.

For permission, TCC, release, signing, or packaging changes, use the existing
repo scripts and the canonical workspace-built app paths below; do not substitute
ad hoc builds or hand-made artifacts.
If a required verification step fails or cannot be run, report the exact blocker,
the smallest useful output, and the remaining risk instead of implying success.

## Environment Isolation

- Never read, source, or copy `.env` files, API keys, or credentials from other
  repositories or projects (for example `docs-cometapi`, `CometChore`). LexiRay
  tests and tools must only use secrets explicitly provided for LexiRay.
- Live-provider smoke tests run only when the user explicitly provides the key
  for that run; never reuse a key found on disk outside this repo.
- `~/.lexiray` and the `io.github.tensornull.lexiray` defaults domain are real
  user data (provider configs with API keys, translation history). Only the
  harness in `script/ui/run.sh` may temporarily replace them, through its
  persistent backup at `~/.lexiray-ui-backup` with the `.pending` marker that
  self-heals interrupted runs. Never seed test fixtures into `~/.lexiray` by
  hand, never delete `~/.lexiray-ui-backup`, and never reimplement ad hoc
  backup/restore with temp dirs — a killed run must always be recoverable.

Development runs must use the workspace build at `build/DerivedData/Build/Products/Debug/LexiRay.app`.
Every build/run compile must remove stale LexiRay development `.app` bundles first; stale
bundles in Xcode's default `DerivedData/LexiRay-*` can keep old TCC identities alive and
make macOS permissions appear granted while the running app is still untrusted.
`./script/build_and_run.sh` performs this cleanup automatically before building.
Development run builds must also use the stable local signing identity
`LexiRay Local Development`; ad hoc signing changes the TCC code identity on rebuild and
will break Accessibility and Screen Recording again. The run script creates this local
identity when missing and fails the build if the app is still ad hoc signed. If running
any manual `xcodebuild` command for a runnable app, run `./script/clean_dev_apps.sh --apply`
immediately beforehand and pass `CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="LexiRay Local Development" ENABLE_DEBUG_DYLIB=NO`.
Do not launch any non-workspace LexiRay `.app`.
Do not run `tccutil reset` as part of the normal build/run loop. Reset TCC only when the
development signing identity or bundle identity has intentionally changed, then grant the
current canonical workspace app once in System Settings.
Do not copy, overwrite, kill, or otherwise manage `/Applications` or `~/Applications`
release builds during local iteration. Use `./script/clean_dev_apps.sh` to inspect stale
development bundles, and only use `./script/clean_dev_apps.sh --apply` when the listed
paths are under this repo's `build/` directory or Xcode's `DerivedData/LexiRay-*`.

## CI Failure Discipline

- Do not blindly retry GitHub Actions. Inspect the failed run first:
  `gh run view <run-id> --log-failed`.
- Reproduce or isolate the smallest failing step before changing source when a
  local reproduction is practical.
- Separate workflow/toolchain failures from app regressions before changing
  source. Keep the smallest useful log snippet in the handoff.
- Fix the root cause. Do not make checks green by bypassing validation, weakening
  release/signing rules, deleting tests, or hiding errors unless the user
  explicitly requests that tradeoff.
- If CodeQL Swift fails during its manual build step, treat it as a build failure
  first; CodeQL analysis cannot be trusted until that build succeeds.
- The May 2026 repeated CI failures were caused by the GitHub `macos-15` runner
  using Xcode 16.4, where Swift 6.1.2 crashed while emitting the LexiRay module.
  The root fix was switching CI, CodeQL, and Release to `macos-26` and selecting
  `/Applications/Xcode.app`. Do not revert that runner/toolchain choice unless a
  fresh GitHub runner inspection proves a better supported replacement.
- The current recurrence-prevention rule is: local `./script/ci_local.sh` first,
  PR checks second, main checks third, release tag last.

## Review Guidelines

Codex review should focus on P0/P1 risks rather than style churn. Prioritize:

- Broken CI, release, signing, packaging, or XcodeGen assumptions.
- SwiftUI state, identity, observation, lifecycle, or main-actor mistakes that
  can make the app show stale data or behave inconsistently.
- Accessibility, Screen Recording, TCC, launch-at-login, hotkey, and app
  identity regressions.
- Translation concurrency, cancellation, provider ordering, copy behavior, and
  settings persistence bugs.
- Clean-room violations, non-Swift code, generated-project edits, committed
  `.codex/`, build artifacts, DerivedData, xcresults, or release outputs.

Do not treat AI review as a substitute for `./script/ci_local.sh`, GitHub
checks, or real UI acceptance when the changed behavior is visible.

## Dual Agent PR Review

- Manual dual review is the default. Do not enable automatic Codex or Copilot
  reviews unless the user explicitly asks.
- After `./script/ci_local.sh` passes and the PR is open, request both AI
  reviews:

```bash
./script/request_ai_review.sh <PR_NUMBER>
```

- The script requests GitHub Copilot with `gh pr edit --add-reviewer @copilot`
  and triggers Codex with the exact PR comment `@codex review`.
- If Codex does not react or post a review, confirm Code review is enabled for
  this repository in Codex settings and that the exact `@codex review` trigger
  was posted.
- If Copilot cannot be added as reviewer, confirm the repository and account
  have access to GitHub Copilot Code Review.
- Address actionable AI findings with the same discipline as human review:
  make the smallest fix, rerun the relevant local gate, and request a re-review
  only when needed. Use `./script/request_ai_review.sh <PR_NUMBER> --force-codex`
  to force a new Codex review comment.

## Branch and Release Discipline

- Work on `dev` by default. Do not switch to, commit on, or merge `main` unless
  the user explicitly asks for a main/release operation.
- Public releases use PR flow: prepare on `dev`, open PR to `main`, wait for
  `build-test` and `Analyze Swift`, merge only after checks pass, wait for main
  checks, then push `v<version>`. If GitHub checks are slow, report run URLs and
  resume commands instead of burning an interactive session on long polling.
- Before tagging a release, run `./script/release_check.sh <version>` from a
  clean worktree.
- Release artifacts are built, signed, verified, and uploaded from the local
  tagged checkout with `./script/publish_release.sh <version>`. The GitHub
  Release workflow only validates uploaded assets and checksums; do not rely on
  GitHub runners as the default DMG builder.
- Release artifacts are fixed self-signed, non-notarized DMGs. README and
  release notes must say that macOS Gatekeeper may warn and users should verify
  the `.sha256` file.

## Open Source Standards

- Keep `README.md`, `CHANGELOG.md`, release notes, and user-visible behavior in
  sync.
- Record every public release in `CHANGELOG.md` using SemVer and a dated section.
- Keep contributor, support, security, code-of-conduct, issue-template, and PR
  template docs current when process rules change.
- Preserve the MIT license and clean-room rule in user-facing docs.

## UI Direction

- Dense, calm, native macOS.
- No marketing landing page inside the app.
- Prefer system symbols, semantic colors, and materials.
- The floating panel should feel fast, lightweight, and keyboard-friendly.
