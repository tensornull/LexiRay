# GUI and Computer Use Acceptance

Compilation is not visual acceptance. Define a state matrix before changing a
visible or interactive behavior, then exercise the same matrix in automation
and on the installed app.

## Scenario loop

List and run the smallest affected scenarios during iteration:

```bash
./script/ui/run.sh --list
./script/ui/run.sh <scenario>...
```

At candidate, `./script/verify.sh candidate` runs the complete suite for a
UI-affecting change. Scenarios write screenshots beneath
`build/ui-artifacts/<timestamp>/`. Inspect the generated contact sheet and the
full-size image for any ambiguous frame. Confirm layout, spacing, truncation,
copy, focus, appearance, and state—not just the process exit code.

Every screenshot must be cropped from a window owned by the exact acceptance
PID. Never use a full-display capture for failure evidence or OCR coverage; the
OCR scenario stores PID-bound overlay window identity and display geometry,
without capturing translucent overlay pixels or the user's desktop underneath.
Material-panel captures additionally require the runner's verified, opaque,
synthetic backdrop immediately below the panel; failure to establish it blocks
the capture instead of sampling the real desktop.

`LEXIRAY_UI_ARTIFACT_DIR`, when supplied by an orchestrator, must resolve to a
new empty, non-symlinked child of `build/ui-artifacts/`. The runner rejects every
other path before reading or writing screenshot evidence.

- Add or extend a small scenario for every new visible behavior.
- Give interactive controls stable accessibility identifiers.
- Begin failure diagnosis with `FAIL-<scenario>.png`.
- Exit code 2 is blocked (for example Accessibility permission, shielded GUI,
  or conflicting app copy), not a pass. Fix the precondition or report it.
- Never weaken an assertion or skip a state merely to make the suite green.
- Acceptance uses Control-Option-Shift-A/S and path-bound AX targeting. Because
  Carbon hotkeys cannot be directed to one bundle-identical process, scenarios
  block when another LexiRay copy is running; they never quit or relaunch the
  user's normal-profile app.
- Selection acceptance launches a separate TextEdit instance, records its PID
  in the acceptance profile, and rejects focused AX elements from every other
  process. It never falls back to an existing TextEdit window.

## Minimum state matrices

- Source editor: empty, focused, IME marked text, committed text, clear, and
  placeholder restored.
- Languages: selector interaction, source/target direction, Once/Always state,
  and real text entry.
- Speech: source disabled, play, stop, and mutual exclusion with translated
  speech.
- Panel styling: key/non-key, pinned/unpinned, resized/default, light/dark,
  rounded corners, and live translucency.
- OCR: each available display plus union-relative geometry. Record the display
  count; if a second display is required but unavailable, record not covered.

## Installed-app Computer Use

After candidate verification and canonical installation:

1. Confirm the running executable is
   `/Applications/LexiRay.app/Contents/MacOS/LexiRay`.
2. Launch the isolated acceptance profile, never the user's normal profile.
3. The installer seals the `launch` main-window capture before returning, so a
   manually opened window cannot impersonate automatic launch. Read the fixed
   matrix with `./script/acceptance_receipt.sh computer-use-matrix`, inspect the
   installed main window with Computer Use, then use Computer Use to perform
   every remaining scenario with real clicks, typing, focus changes, and
   drag/resize where relevant.
   When a scenario needs another app to take focus, launch a fresh fixture
   process that opens only an empty file beneath the acceptance data root,
   record its exact PID and executable, target that fixture with Computer Use,
   and terminate only that PID afterward. Never borrow an existing Finder,
   Calculator, TextEdit, editor, browser, or other user window to manufacture a
   key/non-key state.
   Computer Use cannot reliably disambiguate two running instances with the
   same bundle identifier. Choose a fixture application with no existing
   process, launch it through `NSWorkspace.OpenConfiguration` with
   `createsNewApplicationInstance = true` and `addsToRecentItems = false`, then
   verify the visible window title/URL and returned PID before any UI action.
   If Computer Use resolves to an existing window, do not interact with it or
   use it as evidence; terminate only the newly created PID and choose a
   different unused fixture application.
   The capture helper independently reads the target PID's AX tree and CGWindow
   state. Passing capture states are fixed: a main window for `launch`; a
   focused non-empty editor for `source_editor`; Japanese and English pickers
   plus `Direction: ja -> en` for `language_direction`; exactly one identified
   Stop button for `speech_controls`; an Unpin control on a resized, non-key,
   floating-level panel for `panel_visual_states`; and one PID-owned OCR overlay
   for every current display. A scenario label without these predicates blocks.
4. After reaching the required state for each scenario, run
   `./script/acceptance_receipt.sh capture-computer-use <scenario> [window-id]`.
   The helper chooses only an allowed PID-owned window, validates any required
   synthetic backdrop, and writes controlled PNG/provenance evidence under
   `build/acceptance/`. Do not provide an external screenshot directory or
   contact sheet.
5. Generate the canonical contact sheet and source/app/process-bound manifest
   while the acceptance PID is still running. Inspect the generated contact
   sheet before recording the result:

   ```bash
   manifest="$(./script/acceptance_receipt.sh write-computer-use-manifest)"
   ./script/acceptance_receipt.sh mark-computer-use passed "$manifest"
   ```

   Arbitrary scenarios, generic notes, or external screenshots are not passing
   evidence. The manifest binds the canonical matrix, source, installed
   path, PID plus kernel process start time, CDHash,
   executable/certificate/requirement/entitlements hashes, isolated root/suite,
   PID-owned windows, screenshot provenance, and generated contact-sheet hashes.
   Validation rebuilds the contact sheet from the exact sealed PNG list. UTC
   timestamps must satisfy `installed_at <= captured_at <= manifest.created_at
   <= computer_use_at <= current time`. All artifacts are bound to the current
   install transaction UUID; reinstalling identical source invalidates the
   previous transaction's Computer Use evidence.
6. Quit the acceptance-profile process. Leave the verified installed app in
   place for the user; do not launch it against real data as part of automation.

If Computer Use cannot reach a required permission or hardware state, record
`blocked` with exact evidence and residual risk. Do not ask the user to repeat
routine visual acceptance that the agent can perform.
