# LexiRay Agent Contract

## Authority and Default Behavior

- This file is the canonical, agent-independent contract. Detailed procedures
  live in `.agents/runbooks/`; reusable capabilities live in `.agents/skills/`.
- Inspect the worktree, current branch, source, tests, and relevant history
  before deciding. Treat memory and conversation summaries as hints only.
- Default to autonomous completion: understand, implement, verify, install when
  applicable, and accept the installed app. Ask only for a real product
  ambiguity, missing credential/authority, destructive action, or hard blocker.
- Keep the requested loop small. Put unrelated findings in `ROADMAP.md` Backlog;
  do not turn a narrow request into an unsolicited refactor.
- Preserve dirty user-owned changes. Never discard, overwrite, or reformat
  unrelated work.

## Product and Code Boundaries

- LexiRay is a clean-room macOS selection translation app: dense, calm, native,
  fast, and keyboard-friendly.
- Keep product code Swift-only unless the user explicitly approves otherwise.
  Use SwiftUI for surfaces and narrow AppKit bridges for macOS-only edges.
- Never copy EasyDict source, assets, UI implementation, Objective-C, or private
  reverse-engineered behavior.
- Prefer system symbols, semantic colors, materials, and native macOS controls.
- Follow the existing ownership layout: `App/`, `Views/`, `Models/`, `Stores/`,
  `Services/`, and `Support/`.
- Regenerate with XcodeGen; never hand-edit `LexiRay.xcodeproj`.
- Do not commit generated projects, `.codex/`, build products, DerivedData,
  xcresults, archives, DMGs, or other release output.

## Default Delivery Loop

1. Run `./script/preflight.sh change` and define a concrete acceptance matrix.
2. Implement the smallest complete change in small edit batches.
3. During debugging, run the narrowest affected tests and explicit GUI
   scenarios. Run `./script/verify.sh changed` only after a stable edit batch;
   do not use it as the reproduction loop.
4. Run `./script/verify.sh candidate` when the change is ready.
5. For app-binary changes, install only through the canonical install skill.
6. Use Computer Use on `/Applications/LexiRay.app` with the same acceptance
   profile and acceptance matrix; then record the result in the receipt.
7. Run `./script/verify.sh pr` before push, PR, or release work.

Use evidence states exactly: `compiled`, `unit verified`, `GUI verified`,
`installed verified`, `Computer Use verified`, and `released verified`.
Never replace missing evidence with “perfect”, “done”, or “fully fixed”.

### Verification Loop Discipline

- Full suites are gates, not debuggers. Reproduce with the smallest unit/GUI scenario and inspect its screenshot first.
- Before `verify.sh changed`, inspect its selected scenarios. If a `script/ui/`,
  project, or harness edit expands it to the full suite, iterate with explicit
  `script/ui/run.sh <scenario>...` and run `changed` once when stable.
- Complete P0/P1 adversarial review before candidate, install, or Computer Use,
  then freeze fingerprinted inputs; a source-changing review means not final.
- Run at most one full automated GUI suite per fingerprint. If `changed` already
  covers the exact candidate bundle, candidate must reuse it through
  `LEXIRAY_REUSE_GUI_ARTIFACT_DIR`; rerun only after a recorded rejection.
- Computer Use is resumable per scenario. Read the fingerprint, install
  transaction, and sealed captures, then execute only missing or failed states;
  an interruption never justifies reinstalling or recapturing passed states.
- Keep fixture and acceptance-PID cleanup separate. While the receipt PID is
  live, write and inspect the manifest, mark Computer Use, and require handoff;
  only then quit it, even when cleanup is requested.
- Make transient states survive capture and confirm AX semantics; retry only that scenario.
- On a GUI defect, stop broad gates and return to the failing scenario. Call a
  run final only after freeze/review, naming its layer and remaining matrix.

## Data and Credential Safety

- Automated tests, GUI scenarios, and Computer Use acceptance must use the
  explicit acceptance profile with an isolated data root, UserDefaults suite,
  and mock provider.
- Never read, replace, back up, restore, seed, or write real `~/.lexiray`, the
  `io.github.tensornull.lexiray` defaults domain, or real provider/history data.
  This boundary applies on success, ordinary failure, SIGINT, and SIGKILL.
- Automated checks must use named pasteboards and PID-owned window captures;
  never clear the general pasteboard or persist unrelated desktop pixels.
- Never read `.env` files, API keys, certificates, or credentials from another
  project. Live-provider tests require a key explicitly supplied for that run.
- Do not run `tccutil reset` in the normal loop. Never unlock or probe a stale
  release keychain in a way that can display a password prompt.

See `.agents/runbooks/data-safety.md` for acceptance isolation and TCC rules.

## Verification and Installation

- Build/tests are necessary, not UI acceptance. Visible UI, panel, hotkey,
  selection, OCR, permission, speech, streaming, and window behavior require
  GUI scenarios, inspected screenshots/contact sheet, and installed-app
  Computer Use acceptance.
- New visible behavior needs a new or extended scenario and accessibility IDs.
- Candidate receipts are source-fingerprint-bound under ignored
  `build/acceptance/`; any source change invalidates prior evidence. Consume
  receipts through `script/acceptance_receipt.sh`, not ad hoc JSON parsing.
- Multi-display requirements must record the tested display count. Missing
  hardware is `blocked/not covered`, never a silent pass.
- `script/build_and_run.sh` is workspace-only and must never write
  `/Applications`. The install skill is the sole writer of
  `/Applications/LexiRay.app` and requires a current candidate receipt.
- App-binary changes install automatically after candidate verification.
  Docs/tests-only changes do not install. Installation must stage, verify,
  atomically replace, validate identity/version/CDHash, and roll back on failure.

See `.agents/runbooks/verification.md`, `gui-acceptance.md`, and
`installation.md` for the executable procedures.

## Git and Release

- Keep long-lived `dev`. Create normal work from latest `dev` as
  `feat/<task>`, `fix/<task>`, `chore/<task>`, or `docs/<task>`.
- Task PRs target `dev` and use squash merge. Release PRs go `dev` to `main`
  and use merge commits only. Immediately fast-forward/sync `main` back to
  `dev` after release, before starting another task.
- Emergency fixes alone branch from `main`; merge them to `main`, then sync
  them back to `dev` immediately.
- Do not commit, push, open a PR, merge, tag, or publish without user intent.
  The user's explicit “release/publish a new version” authorizes the complete
  release chain without repeated confirmation.
- Release packaging is local-first with GitHub Release Build as fallback when
  the fixed local identity is unavailable. Releases are fixed self-signed and
  non-notarized; never invent or replace signing material.

See `.agents/runbooks/git-workflow.md`, `ci.md`, and `release.md`.

## Planning, Review, and Handoff

- `ROADMAP.md` is a lightweight product horizon: `Now`, `Next`, `Backlog` with
  stable IDs. Put acceptance detail, logs, screenshots, and build evidence in
  the branch/PR/receipt, not the roadmap.
- Review for P0/P1 correctness first: data loss, signing/TCC identity, CI and
  packaging, SwiftUI state/lifecycle, concurrency/cancellation, permissions,
  hotkeys, panels, provider ordering, persistence, and clean-room violations.
- Before handing off non-trivial work, challenge false positives, untouched real
  user paths, stale evidence, interruption/rollback behavior, and installed-copy
  identity.
- Report changed scope, evidence states achieved, scenarios and artifact path,
  skipped/blocked checks, and residual risk. Reply to the user in Chinese;
  keep code, identifiers, branch names, and commit messages in English.
