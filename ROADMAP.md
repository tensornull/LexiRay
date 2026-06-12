# LexiRay Roadmap

Single source of truth for phases, tasks, and status. Agents must update task
status here in the same change that starts or finishes the work, and reference
roadmap items in handoffs. Newly discovered durable work goes into the Backlog
section instead of being silently dropped.

Status legend: `[ ]` todo · `[~]` in progress · `[x]` done (with evidence)

## Vision

A selection-translation app that beats Bob and EasyDict on feel: instant,
calm, native, keyboard-friendly, and reliable. Two-layer results: an instant
local translation first, streaming LLM results layered on top. Zero permission
surprises.

## Phase 0 — Stability (permissions never break again)

- [x] Land the App Identity work (AppIdentityService, identity gating of
      Selection/OCR, App Identity settings panel, release signing scripts +
      workflow). Evidence 2026-06-11: L0-L3 green (206 unit tests), 8/8 GUI
      scenarios PASS including the new `settings_identity` scenario, all
      screenshots inspected.
- [ ] Release 0.1.3 with the fixed release certificate; replace the
      `LexiRay Local Development`-signed copy currently in `/Applications`
      so the installed app has the long-term stable TCC identity.
- [ ] Replace 1s permission polling with event-driven refresh
      (`DistributedNotificationCenter` accessibility notification +
      app-activation refresh). Keep polling only as a slow fallback.
- [ ] Decide: Apple Developer Program ($99/yr) for Developer ID + notarization.
      Root-cause fix for TCC identity churn AND Gatekeeper warnings. Self-signed
      certificates remain a workaround; if the cert is ever lost/recreated, all
      users must re-grant permissions.
- [x] Fix unit tests leaking thousands of `LexiRayControllerTests-*` /
      `LexiRaySettingsStoreTests-*` UserDefaults domains and temp dirs.
      Tests now use in-memory scratch defaults (cfprefsd flushes leaked
      domains after process exit, so teardown deletion alone cannot win) and
      teardown-cleaned scratch directories; `script/clean_test_state.sh`
      removed the accumulated 7733 domains + 944 temp dirs. Evidence
      2026-06-11: three consecutive full unit runs leak zero files.

## Phase 1 — Pipeline (every iteration self-verifies) — DONE

- [x] Scenario-based GUI harness `script/ui/` (lib.swift + 7 scenarios +
      run.sh). Evidence: 7/7 PASS, screenshots in `build/ui-artifacts/`.
- [x] Screenshot-evidence discipline + verification ladder (L0-L3) in
      AGENTS.md; agents must visually inspect every screenshot.
- [x] Self-healing user-state protection in the harness (persistent backup +
      `.pending` marker; interrupted runs auto-recover on the next run).
      Evidence: kill -9 mid-suite then rerun restores 4 providers + 100
      history entries.
- [x] Claude Code repo integration disabled for this project:
      `.claude/settings.json` blanks commit/PR attribution, and the former
      `CLAUDE.md` symlink was removed on 2026-06-12 so Claude Code no longer
      gets repo instructions from this repository.
- [x] `ROADMAP.md` (this file) as persistent progress tracking.
- [x] Commit Phase 1 to `dev`. Landed as its own commit, separate from the
      App Identity work (2026-06-11).

## Phase 2 — Usability parity and beyond (vs EasyDict)

- [ ] Apple Translation framework provider (macOS 15+): local, free, instant,
      offline. Show it first while LLM providers stream in.
- [ ] Dictionary mode: single words get phonetics, part of speech, senses,
      examples (separate layout from sentence translation).
- [ ] History search (current JSON list is browse-only; useless at 100+).
- [ ] Input-translate mode (type → translate → optionally replace/copy).
- [ ] Optional mouse-selection popup icon (EasyDict-style, default off).

## Phase 3 — Taste, performance, zero-bug feel

- [x] OCR selection overlay drag jank: replaced full-view `draw(_:)`
      invalidation with CALayer composition (CAShapeLayer dim/hole + border,
      CATextLayer size label, pre-rendered prompt image). Also fixed the
      overlay sometimes staying blank until the first drag (hotkey-callout
      panels need an explicit display pass) and the prompt centering on the
      multi-display union instead of the cursor's screen (2026-06-12).
- [x] Rich translation results clipping at the panel edge: tokenizer now
      emits breakable tokens (CJK break opportunities, 24-char cap on
      unbroken runs) and InlineFlowLayoutEngine computes wrap frames from
      the real panel width (GeometryReader). Evidence 2026-06-12: 5 new
      renderer unit tests, new `rich_result_wrap` GUI scenario PASS with
      default-width and 900px screenshots inspected.
- [ ] Split `LexiRayController` (877 lines) into TranslationWorkflow /
      HistoryNavigation / PermissionWorkflow services. Precondition for
      confident iteration on interaction logic.
- [ ] Performance budgets asserted in GUI scenarios: hotkey→panel visible,
      first provider result latency.
- [ ] UI detail pass with screenshots as evidence (see Backlog for known
      issues).
- [ ] Empty states, error states, motion polish.

## Backlog (known issues, newest first)

- Dashboard hotkey chips truncate ("Control-Optio…") at default window width
  (screenshot evidence 2026-06-11).
- Pin state persists across panel sessions — next hotkey panel opens already
  pinned. Decide if intended (observed in scenario screenshots 2026-06-11).
- Whole-sentence System Dictionary lookups always fail with a raw "Failed"
  badge; sentence inputs should probably skip dictionary or soften the result
  presentation.
- `ensure_local_codesign_identity.sh` silently creates a NEW identity if the
  cert is missing, which changes the dev TCC identity. Should warn loudly
  instead.

## Decision log

- 2026-06-11: GUI verification standardized on `script/ui/run.sh` scenarios
  (AX-driven, screenshot evidence). Computer Use stays as the final layer for
  what scenarios cannot reach.
- 2026-06-10: Release DMGs must use the fixed self-signed certificate
  (`LexiRay Release Self-Signed`); unsigned releases banned.
- 2026-05-29: CI/CodeQL/Release moved to `macos-26` + current Xcode after
  Swift 6.1.2 module-emit crashes on `macos-15`.
