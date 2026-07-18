#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/LexiRay.xcodeproj"
APP_BUNDLE="$ROOT_DIR/build/DerivedData/Build/Products/Debug/LexiRay.app"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lexiray-verify.XXXXXX")"
CHANGED_FILES="$WORK_DIR/changed-files.txt"
TEST_CLASSES="$WORK_DIR/test-classes.txt"
SCENARIOS="$WORK_DIR/scenarios.txt"
AVAILABLE_SCENARIOS="$WORK_DIR/available-scenarios.txt"
trap 'rm -rf "$WORK_DIR"' EXIT

case "$MODE" in
  changed|candidate|pr) ;;
  *) echo "usage: $0 changed|candidate|pr" >&2; exit 2 ;;
esac

cd "$ROOT_DIR"

base_ref() {
  local branch
  if [[ -n "${LEXIRAY_BASE_REF:-}" ]]; then
    git rev-parse --verify "$LEXIRAY_BASE_REF"
    return
  fi
  branch="$(git symbolic-ref --quiet --short HEAD || true)"
  case "$branch" in
    feat/*|fix/*|chore/*|docs/*)
      if git rev-parse --verify origin/dev >/dev/null 2>&1; then
        git merge-base HEAD origin/dev
        return
      fi
      ;;
    dev)
      if git rev-parse --verify origin/dev >/dev/null 2>&1; then
        git merge-base HEAD origin/dev
        return
      fi
      ;;
    main)
      if git rev-parse --verify origin/main >/dev/null 2>&1; then
        git merge-base HEAD origin/main
        return
      fi
      ;;
  esac
  if git rev-parse HEAD^ >/dev/null 2>&1; then
    git rev-parse HEAD^
  else
    git hash-object -t tree /dev/null
  fi
}

collect_changed_files() {
  local base
  if [[ -n "${LEXIRAY_CHANGED_FILES_FILE:-}" ]]; then
    sed '/^[[:space:]]*$/d' "$LEXIRAY_CHANGED_FILES_FILE" | LC_ALL=C sort -u >"$CHANGED_FILES"
    return
  fi
  base="$(base_ref)"
  {
    git diff --name-only --diff-filter=ACDMRTUXB "$base"...HEAD
    git diff --name-only --diff-filter=ACDMRTUXB HEAD
    git ls-files --others --exclude-standard
  } | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u >"$CHANGED_FILES"
}

path_matches() {
  local pattern="$1"
  grep -E "$pattern" "$CHANGED_FILES" >/dev/null 2>&1
}

has_build_inputs() {
  path_matches '^(LexiRay|LexiRayTests)/|^(Package\.swift|project\.yml)$'
}

has_app_binary_changes() {
  path_matches '^LexiRay/|^(Package\.swift|project\.yml)$'
}

has_context_changes() {
  path_matches '\.md$|^\.agents/|^\.claude/|^\.codex/|^\.github/|^script/context_lint\.sh$'
}

ui_required_for_changes() {
  # Conservatively treat every app-source/build-input change as user-visible or
  # behavior-affecting. Test, documentation, and control-plane-only edits do not
  # require a GUI pass unless they touch the GUI harness itself.
  has_app_binary_changes || path_matches '^script/ui/'
}

login_item_probe_required_for_changes() {
  path_matches '(^|/)(LoginItem|AppRuntime|AcceptanceProfile|AppDelegate|SettingsView|LexiRayController)|^script/(development_identity|ensure_local_codesign_identity|build_and_run|install_applications|login_item_system_probe|acceptance_receipt|release|sign_release)|^\.github/workflows/release-build\.yml$'
}

lint_changed_swift() {
  local files=()
  local path
  while IFS= read -r path; do
    case "$path" in
      *.swift)
        [[ -f "$path" ]] && files+=("$path")
        ;;
    esac
  done <"$CHANGED_FILES"
  if [[ ${#files[@]} -gt 0 ]]; then
    echo "--- SwiftFormat (changed paths)"
    "$ROOT_DIR/script/swiftformat_tool.sh" "${files[@]}" --lint
  fi
}

add_test_file_classes() {
  local test_file="$1"
  [[ -f "$test_file" ]] || return 0
  awk '/^(final[[:space:]]+)?class[[:space:]]+[A-Za-z0-9_]+Tests[[:space:]]*:/ {name=$0; sub(/^(final[[:space:]]+)?class[[:space:]]+/, "", name); sub(/[[:space:]]*:.*/, "", name); print name}' \
    "$test_file" >>"$TEST_CLASSES"
}

collect_test_classes() {
  local path basename matching
  : >"$TEST_CLASSES"
  while IFS= read -r path; do
    case "$path" in
      LexiRayTests/*Tests.swift)
        add_test_file_classes "$path"
        ;;
      LexiRay/*.swift|LexiRay/**/*.swift)
        basename="${path##*/}"
        basename="${basename%.swift}"
        matching="$ROOT_DIR/LexiRayTests/${basename}Tests.swift"
        add_test_file_classes "$matching"
        case "$path" in
          LexiRay/App/*|LexiRay/Views/*|*FloatingPanel*|*TextSelection*|*GlobalHotKey*|*SpeechService*)
            add_test_file_classes "$ROOT_DIR/LexiRayTests/ControllerInteractionTests.swift"
            ;;
          *AppIdentity*) add_test_file_classes "$ROOT_DIR/LexiRayTests/AppIdentityTests.swift" ;;
          *OpenAICompatibleProvider*|*HTTPClient*|*TranslationProvider*|*ProviderTranslationTaskCoordinator*)
            add_test_file_classes "$ROOT_DIR/LexiRayTests/LLMProviderTests.swift"
            ;;
          *RichTranslation*|*SourceMarkdown*)
            add_test_file_classes "$ROOT_DIR/LexiRayTests/RichTranslationRendererTests.swift"
            ;;
          *Language*)
            add_test_file_classes "$ROOT_DIR/LexiRayTests/LanguageDetectorTests.swift"
            add_test_file_classes "$ROOT_DIR/LexiRayTests/TranslationPipelineTests.swift"
            ;;
          *Settings*) add_test_file_classes "$ROOT_DIR/LexiRayTests/SettingsStoreTests.swift" ;;
          *OCR*) add_test_file_classes "$ROOT_DIR/LexiRayTests/OCRServiceTests.swift" ;;
        esac
        ;;
    esac
  done <"$CHANGED_FILES"
  LC_ALL=C sort -u "$TEST_CLASSES" -o "$TEST_CLASSES"
}

run_targeted_tests() {
  local args=()
  local test_class
  collect_test_classes
  [[ -s "$TEST_CLASSES" ]] || {
    echo "--- Unit tests: no directly mapped test class for this edit batch"
    return 0
  }
  while IFS= read -r test_class; do
    [[ -n "$test_class" ]] && args+=("-only-testing:LexiRayTests/$test_class")
  done <"$TEST_CLASSES"
  echo "--- Unit tests (targeted): $(paste -sd, "$TEST_CLASSES")"
  xcodebuild test \
    -project "$PROJECT" \
    -scheme LexiRay \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$ROOT_DIR/build/TestDerivedData" \
    CODE_SIGNING_ALLOWED=NO \
    "${args[@]}"
}

add_scenario() {
  printf '%s\n' "$1" >>"$SCENARIOS"
}

collect_targeted_scenarios() {
  local path scenario
  : >"$SCENARIOS"
  "$ROOT_DIR/script/ui/run.sh" --list >"$AVAILABLE_SCENARIOS"
  while IFS= read -r path; do
    case "$path" in
      script/ui/scenarios/*.swift)
        scenario="${path##*/}"
        add_scenario "${scenario%.swift}"
        ;;
      script/ui/*|project.yml|Package.swift)
        cat "$AVAILABLE_SCENARIOS" >>"$SCENARIOS"
        ;;
      *SourceTextEditor*|*MainView*|*LexiRayController*)
        add_scenario source_editor
        add_scenario panel_blank
        ;;
      *LanguagePicker*|*LanguageSettings*|*LanguageDetector*)
        add_scenario source_editor
        add_scenario settings_identity
        add_scenario language_direction_input
        ;;
      *Speech*)
        add_scenario speech_controls
        add_scenario rich_result_wrap
        ;;
      *FloatingPanel*|*WindowReporting*|*FloatingPanelView*|*FloatingPanelControls*)
        add_scenario panel_blank
        add_scenario pin
        add_scenario manual_resize_preserved
        add_scenario panel_visual_states
        ;;
      *OCR*)
        add_scenario ocr_permission_gate
        add_scenario ocr_multi_display
        ;;
      *Provider*|*TranslationPipeline*|*HTTPClient*)
        add_scenario providers
        add_scenario streaming_growth
        ;;
      *History*) add_scenario history_nav ;;
      *RichTranslation*|*Markdown*) add_scenario rich_result_wrap ;;
      *Selection*|*HotKey*) add_scenario selection_translate ;;
      LexiRay/*)
        add_scenario launch
        add_scenario panel_blank
        ;;
    esac
  done <"$CHANGED_FILES"

  LC_ALL=C sort -u "$SCENARIOS" -o "$SCENARIOS"
  grep -Fxf "$SCENARIOS" "$AVAILABLE_SCENARIOS" >"$SCENARIOS.available" || true
  mv "$SCENARIOS.available" "$SCENARIOS"
  if [[ ! -s "$SCENARIOS" ]]; then
    for scenario in launch panel_blank; do
      grep -Fx "$scenario" "$AVAILABLE_SCENARIOS" >>"$SCENARIOS" || true
    done
  fi
}

make_contact_sheet() {
  local artifact_dir="$1"
  local output="$artifact_dir/contact-sheet.png"
  "$ROOT_DIR/script/make_contact_sheet.swift" "$artifact_dir" "$output" >/dev/null
  [[ -f "$output" ]] || {
    echo "Contact sheet was not generated: $output" >&2
    return 1
  }
  printf '%s\n' "$output"
}

resolve_reusable_gui_artifact() {
  local requested="${LEXIRAY_REUSE_GUI_ARTIFACT_DIR:-}"
  local artifact_root requested_real required_file
  [[ -n "$requested" ]] || return 1
  [[ -d "$requested" && ! -L "$requested" ]] || {
    echo "Reusable GUI artifact is missing or symlinked: $requested" >&2
    return 2
  }
  artifact_root="$(cd "$ROOT_DIR/build/ui-artifacts" && pwd -P)"
  requested_real="$(cd "$requested" && pwd -P)"
  case "$requested_real/" in
    "$artifact_root"/*) ;;
    *)
      echo "Reusable GUI artifact must stay below $artifact_root" >&2
      return 2
      ;;
  esac
  for required_file in gui-run.json results.txt gui-screenshots.sha256 contact-sheet.png; do
    [[ -f "$requested_real/$required_file" && ! -L "$requested_real/$required_file" ]] || {
      echo "Reusable GUI artifact is missing $required_file" >&2
      return 2
    }
  done
  printf '%s\n' "$requested_real"
}

run_targeted_gui() {
  local artifact_dir
  collect_targeted_scenarios
  artifact_dir="$ROOT_DIR/build/ui-artifacts/changed-$(date '+%Y%m%d-%H%M%S')-$$"
  mkdir -p "$artifact_dir"
  echo "--- GUI scenarios (targeted): $(paste -sd, "$SCENARIOS")"
  LEXIRAY_UI_ARTIFACT_DIR="$artifact_dir" \
    "$ROOT_DIR/script/ui/run.sh" --skip-build $(<"$SCENARIOS")
  contact_sheet="$(make_contact_sheet "$artifact_dir")"
  echo "GUI_ARTIFACT_DIR=$artifact_dir"
  echo "GUI_CONTACT_SHEET=$contact_sheet"
}

run_l3() {
  local marker
  if [[ "${LEXIRAY_FORCE_L3:-0}" != 1 ]] && marker="$("$ROOT_DIR/script/acceptance_receipt.sh" l3-valid 2>/dev/null)"; then
    echo "--- L3 reused for current source fingerprint: $marker"
    return 0
  fi
  echo "--- L3 / CI-equivalent suite"
  "$ROOT_DIR/script/ci_local.sh"
  "$ROOT_DIR/script/acceptance_receipt.sh" l3-valid >/dev/null || {
    echo "ci_local.sh passed but did not create current-source L3 evidence." >&2
    return 1
  }
}

run_script_tests() {
  local test_script ran=0
  for test_script in "$ROOT_DIR"/script/tests/*_test.sh; do
    [[ -x "$test_script" ]] || continue
    ran=1
    echo "--- Script test: ${test_script#$ROOT_DIR/}"
    "$test_script"
  done
  if [[ "$ran" == 0 ]]; then
    echo "--- Script tests: none registered"
  fi
}

verify_source_unchanged() {
  local before="$1"
  local after
  after="$("$ROOT_DIR/script/acceptance_receipt.sh" fingerprint)"
  [[ "$before" == "$after" ]] || {
    echo "Source inputs changed during verification ($before -> $after); rerun $MODE." >&2
    return 1
  }
}

collect_changed_files
fingerprint_before="$("$ROOT_DIR/script/acceptance_receipt.sh" fingerprint)"
computer_use_required_scenarios="$("$ROOT_DIR/script/computer_use_scope.sh" "$CHANGED_FILES")"
changed_count="$(wc -l <"$CHANGED_FILES" | tr -d ' ')"
echo "VERIFY_MODE=$MODE"
echo "SOURCE_FINGERPRINT=$fingerprint_before"
echo "CHANGED_PATHS=$changed_count"
echo "COMPUTER_USE_REQUIRED_SCENARIOS=$computer_use_required_scenarios"
if [[ "$changed_count" -gt 0 ]]; then
  sed 's/^/  /' "$CHANGED_FILES"
fi

case "$MODE" in
  changed)
    "$ROOT_DIR/script/preflight.sh" change
    if has_context_changes; then
      "$ROOT_DIR/script/context_lint.sh"
    fi
    if path_matches '^script/'; then
      run_script_tests
    fi
    lint_changed_swift
    if has_build_inputs; then
      echo "--- Incremental signed workspace build"
      "$ROOT_DIR/script/build_and_run.sh" build
      run_targeted_tests
    fi
    if ui_required_for_changes; then
      run_targeted_gui
    fi
    verify_source_unchanged "$fingerprint_before"
    echo "VERIFY_PASS[changed]"
    ;;

  candidate)
    "$ROOT_DIR/script/context_lint.sh"
    run_script_tests
    if [[ -z "${LEXIRAY_REUSE_GUI_ARTIFACT_DIR:-}" ]] &&
      [[ "${LEXIRAY_FORCE_VERIFY:-0}" != 1 ]] &&
      "$ROOT_DIR/script/acceptance_receipt.sh" require-automated-candidate >/dev/null 2>&1 &&
      [[ "$("$ROOT_DIR/script/acceptance_receipt.sh" field \
        verification.computer_use_required_scenarios)" == "$computer_use_required_scenarios" ]] &&
      "$ROOT_DIR/script/acceptance_receipt.sh" l3-valid >/dev/null 2>&1; then
      receipt="$("$ROOT_DIR/script/acceptance_receipt.sh" require-automated-candidate)"
      echo "VERIFY_REUSED[candidate]=$receipt"
      exit 0
    fi
    reusable_gui_artifact=""
    if (ui_required_for_changes || [[ "$changed_count" -eq 0 ]]) &&
      [[ -n "${LEXIRAY_REUSE_GUI_ARTIFACT_DIR:-}" ]]; then
      reusable_gui_artifact="$(resolve_reusable_gui_artifact)" || exit $?
      "$ROOT_DIR/script/acceptance_receipt.sh" validate-gui-artifact \
        "$APP_BUNDLE" "$reusable_gui_artifact" "$reusable_gui_artifact/contact-sheet.png"
    fi
    run_l3
    if [[ -n "$reusable_gui_artifact" ]]; then
      echo "--- Signed workspace candidate build reused with exact GUI-tested bundle"
      /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
    else
      echo "--- Signed workspace candidate build"
      "$ROOT_DIR/script/build_and_run.sh" build
    fi
    verify_source_unchanged "$fingerprint_before"
    echo "--- Acceptance-profile data safety (normal/failure/SIGINT/SIGKILL)"
    "$ROOT_DIR/script/test_acceptance_data_safety.sh" "$APP_BUNDLE"

    gui_status=not-required
    artifact_dir=""
    contact_sheet=""
    if ui_required_for_changes || [[ "$changed_count" -eq 0 ]]; then
      gui_status=passed
      if [[ -n "$reusable_gui_artifact" ]]; then
        artifact_dir="$reusable_gui_artifact"
        contact_sheet="$artifact_dir/contact-sheet.png"
        echo "--- GUI scenarios reused from current-source full-suite evidence"
      else
        artifact_dir="$ROOT_DIR/build/ui-artifacts/candidate-${fingerprint_before:0:12}-$(date '+%Y%m%d-%H%M%S')"
        mkdir -p "$artifact_dir"
        echo "--- GUI scenarios (full suite)"
        LEXIRAY_UI_ARTIFACT_DIR="$artifact_dir" \
          "$ROOT_DIR/script/ui/run.sh" --skip-build
        contact_sheet="$(make_contact_sheet "$artifact_dir")"
      fi
      echo "GUI_ARTIFACT_DIR=$artifact_dir"
      echo "GUI_CONTACT_SHEET=$contact_sheet"
    fi
    verify_source_unchanged "$fingerprint_before"
    login_item_probe_required=0
    if login_item_probe_required_for_changes; then
      login_item_probe_required=1
    fi
    receipt="$(LEXIRAY_LOGIN_ITEM_PROBE_REQUIRED="$login_item_probe_required" \
      LEXIRAY_COMPUTER_USE_REQUIRED_SCENARIOS="$computer_use_required_scenarios" \
      "$ROOT_DIR/script/acceptance_receipt.sh" write-candidate \
      "$APP_BUNDLE" "$gui_status" "$artifact_dir" "$contact_sheet")"
    echo "ACCEPTANCE_RECEIPT=$receipt"
    if [[ "$gui_status" == passed ]]; then
      echo "GUI_VISUAL_INSPECTION=pending"
      echo "Inspect $contact_sheet, then run: ./script/acceptance_receipt.sh mark-gui-inspected passed <evidence>"
    fi
    echo "VERIFY_PASS[candidate]"
    ;;

  pr)
    "$ROOT_DIR/script/context_lint.sh"
    run_script_tests
    if has_app_binary_changes; then
      echo "--- Current installed-app handoff evidence"
      "$ROOT_DIR/script/acceptance_receipt.sh" require-handoff >/dev/null
    elif ui_required_for_changes; then
      echo "--- Current inspected GUI candidate evidence"
      "$ROOT_DIR/script/acceptance_receipt.sh" require-candidate >/dev/null
    fi
    run_l3
    verify_source_unchanged "$fingerprint_before"
    echo "L3_RECEIPT=$("$ROOT_DIR/script/acceptance_receipt.sh" l3-valid)"
    echo "VERIFY_PASS[pr]"
    ;;
esac
