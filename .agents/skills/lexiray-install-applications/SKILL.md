---
name: lexiray-install-applications
description: Use after a verified LexiRay app/UI change when the user wants to preview it from `/Applications/LexiRay.app`, or when the user asks to compile, install, replace, update, or launch the local Applications copy of LexiRay.
---

# LexiRay Applications Install Skill

This skill installs the current workspace-built LexiRay app over the local
`/Applications/LexiRay.app` copy so the user can inspect the real installed app.
It is for local preview only; it is not a release, notarization, tag, or commit
workflow.

## Safety Boundary

- Do not replace `/Applications/LexiRay.app` unless the user explicitly asks or
  explicitly approves the replacement after you remind them.
- It is appropriate to remind the user after a meaningful app/UI change has
  passed verification: "The app is ready to preview; I can replace
  `/Applications/LexiRay.app` if you want to inspect the installed copy."
- Do not use `sudo` by default. If `/Applications` permissions block the
  replacement, report the exact permission error and ask the user how to proceed.
- Do not reset TCC, delete `~/.lexiray`, modify provider secrets, or touch
  release artifacts.
- Do not claim this is a release build. The installed copy is a Debug build
  signed with `LexiRay Local Development`.
- If another LexiRay build/test/CI command is currently running, wait for it to
  finish or report that it is blocking installation. Do not kill unrelated
  build processes.

## Preconditions

Run from `/Users/xmx/workspace/LexiRay`.

Before installing:

1. Verify you are in the LexiRay repo.
2. Check for active LexiRay build/test processes:
   ```bash
   pgrep -fl 'xcodebuild|ci_local|LexiRay' || true
   ```
   A running installed LexiRay app is fine; the install helper will quit it.
   A running `xcodebuild` or `script/ci_local.sh` should finish before install.
3. Use the canonical workspace build path:
   `build/DerivedData/Build/Products/Debug/LexiRay.app`.

## Install Workflow

Use the helper script rather than hand-assembling copy commands:

```bash
.codex/skills/lexiray-install-applications/scripts/install_applications.sh
```

The helper performs these steps:

1. Runs `./script/build_and_run.sh --verify`, which cleans stale development
   app bundles, regenerates the Xcode project, builds the app, verifies the
   `LexiRay Local Development` signature, and briefly launches the workspace
   build.
2. Copies the workspace app to `/Applications/LexiRay.app.codex-installing`.
3. Verifies the staged app with:
   `codesign --verify --deep --strict`.
4. Verifies the staged app is signed by `LexiRay Local Development`.
5. Quits running LexiRay copies whose executable path ends in
   `LexiRay.app/Contents/MacOS/LexiRay`.
6. Moves the previous `/Applications/LexiRay.app` aside to a temporary backup,
   installs the staged app, and restores the backup if the install move fails.
7. Registers the installed app with LaunchServices.
8. Verifies the installed app signature.
9. Opens `/Applications/LexiRay.app` and confirms the running process path.

## Handoff

Report:

- Whether the build succeeded.
- Whether `/Applications/LexiRay.app` was replaced.
- The installed app signing authority.
- The running installed app path and PID.
- Any non-fatal local toolchain noise, such as CoreSimulator warnings, without
  treating it as a blocker when the macOS build succeeds.

Do not include git stage/commit/push directives unless the user separately asks
for git operations.
