#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lexiray-gui-safety-test.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cd "$ROOT_DIR"

fail() {
  echo "GUI_RUNNER_SAFETY_TEST_FAIL: $*" >&2
  exit 1
}

bash -n script/ui/run.sh
bash -n script/verify.sh

reuse_guard="$(sed -n '/^resolve_reusable_gui_artifact()/,/^}/p' script/verify.sh)"
[[ -n "$reuse_guard" ]] || fail "candidate GUI reuse guard is missing"
for invariant in \
  '[[ -d "$requested" && ! -L "$requested" ]]' \
  '"$ROOT_DIR/build/ui-artifacts"' \
  '"$artifact_root"/*' \
  'below $artifact_root' \
  'gui-run.json results.txt gui-screenshots.sha256 contact-sheet.png' \
  '[[ -f "$requested_real/$required_file" && ! -L "$requested_real/$required_file" ]]'; do
  grep -F "$invariant" <<<"$reuse_guard" >/dev/null ||
    fail "candidate GUI reuse guard is missing invariant: $invariant"
done
rg -F 'artifact_dir="$(resolve_reusable_gui_artifact)"' script/verify.sh >/dev/null ||
  rg -F 'reusable_gui_artifact="$(resolve_reusable_gui_artifact)"' script/verify.sh >/dev/null ||
    fail "candidate verification does not use the guarded reusable GUI artifact"
rg -F 'codesign --verify --deep --strict "$APP_BUNDLE"' script/verify.sh >/dev/null ||
  fail "candidate GUI reuse does not validate the exact GUI-tested bundle"
prevalidate_line="$(rg -n 'validate-gui-artifact' script/verify.sh | head -n 1 | cut -d: -f1)"
l3_line="$(rg -n '^[[:space:]]*run_l3$' script/verify.sh | head -n 1 | cut -d: -f1)"
[[ -n "$prevalidate_line" && -n "$l3_line" && "$prevalidate_line" -lt "$l3_line" ]] ||
  fail "candidate GUI reuse is not fully validated before expensive L3 verification"

artifact_guard="$(sed -n '/^prepare_artifact_dir()/,/^}/p' script/ui/run.sh)"
[[ -n "$artifact_guard" ]] || fail "artifact directory guard is missing"
if (
  ROOT_DIR="$WORK_DIR/repo"
  ARTIFACT_BASE="$ROOT_DIR/build/ui-artifacts"
  ARTIFACT_DIR="$WORK_DIR/user-data"
  eval "$artifact_guard"
  prepare_artifact_dir
) >/dev/null 2>&1; then
  fail "artifact directory guard accepted a path outside build/ui-artifacts"
fi
mkdir -p "$WORK_DIR/repo/build/ui-artifacts" "$WORK_DIR/outside"
ln -s "$WORK_DIR/outside" "$WORK_DIR/repo/build/ui-artifacts/link"
if (
  ROOT_DIR="$WORK_DIR/repo"
  ARTIFACT_BASE="$ROOT_DIR/build/ui-artifacts"
  ARTIFACT_DIR="$ROOT_DIR/build/ui-artifacts/link/run"
  eval "$artifact_guard"
  prepare_artifact_dir
) >/dev/null 2>&1; then
  fail "artifact directory guard accepted a symlinked path component"
fi

if rg -n '(^|[[:space:]])(kill|killall|pkill)[[:space:]]' script/ui/run.sh >/dev/null; then
  fail "the shell runner must never terminate a LexiRay process"
fi
rg -F 'require_no_existing_workspace_app || exit 2' script/ui/run.sh >/dev/null ||
  fail "the shell runner does not block before GUI/build work when a workspace app exists"
rg -F 'if ! require_no_existing_workspace_app; then' script/ui/run.sh >/dev/null ||
  fail "the shell runner does not recheck process isolation between scenarios"

if rg -n '/usr/sbin/screencapture|CGWindowListCreateImage|CGDisplayCreateImage' \
  script/ui/scenarios >/dev/null; then
  fail "scenario code must use the PID-bound shared evidence capture"
fi
if rg -n 'snap\(' script/ui/scenarios/ocr_multi_display.swift >/dev/null; then
  fail "translucent OCR overlays must be recorded as identity/geometry, not pixels"
fi
[[ "$(rg -c '/usr/sbin/screencapture' script/ui/lib.swift)" == 1 ]] ||
  fail "all screenshot evidence must flow through one shared capture function"
rg -F 'process.arguments = ["-x", "-l", "\(id)", outputURL.path]' script/ui/lib.swift >/dev/null ||
  fail "shared screenshot capture is not restricted to a single window ID"
rg -F 'windowOwnerPID(window) == processIdentifier' script/ui/lib.swift >/dev/null ||
  fail "screenshot capture does not bind evidence to the recorded PID"
[[ "$(rg -c 'currentOwnedWindowInfo\(targetWindowID: id, processIdentifier: processIdentifier\)' script/ui/lib.swift)" -ge 2 ]] ||
  fail "screenshot capture does not verify window ownership before and after capture"
rg -F 'recordFailureEvidence(message)' script/ui/lib.swift >/dev/null ||
  fail "failure evidence does not use the PID-bound evidence path"
rg -F 'panel.hasShadow = false' LexiRay/Services/FloatingPanelController.swift >/dev/null ||
  fail "floating panel must not use AppKit's rectangular window shadow"
rg -F 'Self.clipWindowFrameBacking(panel)' LexiRay/Services/FloatingPanelController.swift >/dev/null ||
  fail "floating panel must clip the resizable AppKit frame backing"
rg -F 'frameView.layer?.backgroundColor = NSColor.clear.cgColor' LexiRay/Services/FloatingPanelController.swift >/dev/null ||
  fail "floating panel frame backing must stay transparent"
rg -F 'frameView.layer?.cornerRadius = cornerRadius' LexiRay/Services/FloatingPanelController.swift >/dev/null ||
  fail "floating panel frame backing must use the product corner radius"
rg -F 'frameView.layer?.masksToBounds = true' LexiRay/Services/FloatingPanelController.swift >/dev/null ||
  fail "floating panel frame backing must not leak rectangular corner pixels"
rg -F 'alphaComponent <= 0.005' script/ui/lib.swift >/dev/null ||
  fail "panel pixel evidence must reject a faint rectangular frame at transparent corners"
if rg -F '.strokeBorder(Color(nsColor: .separatorColor)' LexiRay/Views/FloatingPanelView.swift >/dev/null; then
  fail "floating panel must not stack a second SwiftUI outline over native glass"
fi

screen_settings_block="$(sed -n '/^  static func openScreenCaptureSettings()/,/^  }/p' LexiRay/Services/PermissionService.swift)"
if grep -F 'requestScreenCaptureIfNeeded()' <<<"$screen_settings_block" >/dev/null; then
  fail "opening Screen Recording settings must not bypass the injected permission request path"
fi

capture_block="$(sed -n '/^func captureOwnedWindow(/,/^func recordFailureEvidence(/p' script/ui/lib.swift)"
grep -F 'if isFloatingPanelWindow(window)' <<<"$capture_block" >/dev/null ||
  fail "material panel capture is not bound to the AX-identified panel window"
grep -F 'guard let backdrop = ControlledPanelBackdrop(targetWindow: window)' \
  <<<"$capture_block" >/dev/null ||
  fail "material panel capture can proceed without creating a controlled backdrop"
[[ "$(grep -c 'verificationError(' <<<"$capture_block")" -ge 2 ]] ||
  fail "controlled backdrop is not verified before and after panel capture"
grep -F 'defer { ownedBackdrop?.close() }' <<<"$capture_block" >/dev/null ||
  fail "controlled backdrop is not deterministically removed after capture"

backdrop_block="$(sed -n '/^final class AcceptanceSafeBackdropPanel/,/^func currentOwnedWindowInfo(/p' script/ui/lib.swift)"
for invariant in \
  'styleMask: [.borderless, .nonactivatingPanel]' \
  'panel.isOpaque = true' \
  'panel.alphaValue = 1' \
  'panel.ignoresMouseEvents = true' \
  'panel.styleMask.contains(.nonactivatingPanel)' \
  '!panel.canBecomeKey' \
  'windowOwnerPID($0) == getpid()' \
  'backdropIndex == targetIndex + 1' \
  'alpha >= 0.999' \
  'backdropBounds.minX <= targetBounds.minX + tolerance' \
  'panel.contentView as? AcceptanceSafeBackdropView'; do
  grep -F "$invariant" <<<"$backdrop_block" >/dev/null ||
    fail "controlled panel backdrop is missing invariant: $invariant"
done
if grep -E '\.activate|NSWorkspace|screencapture|CGWindowListCreateImage|NSImage\(contentsOf' \
  <<<"$backdrop_block" >/dev/null; then
  fail "controlled backdrop must not activate or read another app or the desktop"
fi

rg -F 'canonicalExecutablePath(application) == appExecutablePath' script/ui/lib.swift >/dev/null ||
  fail "process ownership is not bound to the exact workspace executable"
rg -F 'Array(arguments.dropFirst()) == expectedArguments' script/ui/lib.swift >/dev/null ||
  fail "process ownership is not bound to argv0 plus the complete acceptance arguments"
rg -F 'ownedWorkspaceArguments = launchArguments' script/ui/lib.swift >/dev/null ||
  fail "the runner does not record the arguments of its launched process"
rg -F 'waitFor("launched LexiRay process identity", timeout: 3)' script/ui/lib.swift >/dev/null ||
  fail "the runner does not tolerate transient argv registration after launch"
rg -F 'windowInfo(matching: floatingPanelAXWindow())' script/ui/lib.swift >/dev/null ||
  fail "floating panel identity is not mapped from its AX window and frame"
if rg -n 'windowName\([^)]*\)[[:space:]]*[!=]=[[:space:]]*"LexiRay Floating Panel"' \
  script/ui/lib.swift >/dev/null; then
  fail "CGWindowName must not be used as floating-panel identity"
fi
rg -F 'CGPreflightScreenCaptureAccess()' script/ui/run.sh >/dev/null ||
  fail "the runner does not fail fast when Screen Recording is unavailable"
if rg -n 'CGRequestScreenCaptureAccess[[:space:]]*\(' script/ui/run.sh script/ui/lib.swift >/dev/null; then
  fail "automated GUI verification must not trigger a Screen Recording prompt"
fi

terminate_block="$(sed -n '/^func terminateWorkspaceApp()/,/^func restartWorkspaceApp()/p' script/ui/lib.swift)"
grep -F 'applicationMatchesWorkspaceProcess(app, expectedArguments: expectedArguments)' \
  <<<"$terminate_block" >/dev/null ||
  fail "termination is not guarded by executable and argument validation"
grep -F 'kill(processIdentifier, SIGKILL)' <<<"$terminate_block" >/dev/null ||
  fail "the owned-process forced cleanup path is missing"
[[ "$(rg -c 'kill\(' script/ui/lib.swift)" == 1 ]] ||
  fail "only the validated owned-process cleanup path may send a signal"

for field in \
  app_certificate_sha256 \
  app_designated_requirement_sha256 \
  app_entitlements_sha256; do
  rg -F "$field" script/ui/run.sh >/dev/null ||
    fail "GUI manifest is missing identity field $field"
done

# Exercise the earliest process blocker with fake process-table commands. The
# fake Swift command is a tripwire proving no compiler or GUI code was reached.
mkdir -p "$WORK_DIR/bin"
printf '%s\n' '#!/usr/bin/env bash' 'printf "4242\\n"' >"$WORK_DIR/bin/pgrep"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" "$LEXIRAY_TEST_FAKE_COMMAND"' >"$WORK_DIR/bin/ps"
printf '%s\n' '#!/usr/bin/env bash' 'touch "$LEXIRAY_TEST_SWIFT_CALLED"' 'exit 99' >"$WORK_DIR/bin/swift"
chmod +x "$WORK_DIR/bin/pgrep" "$WORK_DIR/bin/ps" "$WORK_DIR/bin/swift"

set +e
PATH="$WORK_DIR/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
LEXIRAY_TEST_FAKE_COMMAND="$ROOT_DIR/build/DerivedData/Build/Products/Debug/LexiRay.app/Contents/MacOS/LexiRay --user-owned" \
LEXIRAY_TEST_SWIFT_CALLED="$WORK_DIR/swift-called" \
  ./script/ui/run.sh --skip-build launch >"$WORK_DIR/process-block.out" 2>&1
status=$?
set -e
[[ "$status" == 2 ]] || fail "existing workspace process returned $status instead of BLOCK (2)"
rg -F 'UI_BLOCKED[process]' "$WORK_DIR/process-block.out" >/dev/null ||
  fail "existing workspace process did not emit the expected blocker"
[[ ! -e "$WORK_DIR/swift-called" ]] ||
  fail "runner reached Swift/GUI work before blocking the existing process"

cat script/ui/panel_border_evidence.swift script/ui/lib.swift \
  script/ui/scenarios/ocr_multi_display.swift | xcrun swiftc -typecheck -
cat script/ui/panel_border_evidence.swift script/ui/lib.swift \
  script/ui/scenarios/ocr_permission_gate.swift | xcrun swiftc -typecheck -

echo "GUI_RUNNER_SAFETY_TEST_PASS"
