# LexiRay Roadmap

Lightweight product horizon only. IDs are stable; move items between sections
without renaming them. Keep implementation plans, test logs, screenshots, and
release evidence in the task branch, PR, and acceptance receipt.

Status: `[ ]` planned · `[~]` active · `[x]` complete

## Vision

Make macOS selection translation instant, calm, native, keyboard-friendly, and
reliable, with no permission or data-loss surprises.

## Now

- [x] **WF-001** — Unify the agent-independent development, isolated acceptance,
  atomic install, and local-first release workflow.
- [x] **DEV-101** — Pin the development signing identity and fail closed instead
  of silently replacing a missing or inaccessible identity.

## Next

- [ ] **UX-001** — Add Apple Translation on supported macOS versions for a fast,
  local, offline first result.
- [ ] **UX-002** — Add a dictionary result mode for words, including phonetics,
  parts of speech, senses, and examples.
- [ ] **UX-003** — Add translation-history search.
- [ ] **UX-004** — Add a first-class type-to-translate workflow with optional
  replace/copy actions.
- [ ] **ARCH-001** — Split the oversized controller by translation, history, and
  permission workflows without changing behavior.

## Backlog

- [ ] **UX-101** — Decide whether panel pin state should persist between panel
  sessions.
- [ ] **UI-101** — Prevent dashboard hotkey chips from truncating at the default
  window width.
- [ ] **UI-102** — Soften or skip whole-sentence System Dictionary failures.
- [ ] **UX-102** — Evaluate an optional mouse-selection popup icon, default off.
- [ ] **PERF-101** — Add scenario budgets for hotkey-to-panel and first-result
  latency.
- [ ] **REL-101** — Revisit Apple Developer ID and notarization if an Apple
  Developer account becomes available.
