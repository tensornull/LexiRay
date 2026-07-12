#!/usr/bin/env bash

# Public identity metadata for the fixed self-signed, non-notarized release
# certificate used by the latest published LexiRay release (v0.4.0). This file
# contains no private key material or password.
LEXIRAY_RELEASE_IDENTITY_NAME="LexiRay Release Self-Signed"
LEXIRAY_RELEASE_CERT_SHA1="C4407C14D31AA9397CD21829E9F26C9AF7AA925B"
LEXIRAY_RELEASE_CERT_SHA256="5A54594CFDFB1827E3A097EA43BF4674A6FCBFA2563D60DE178566AE860229F5"
LEXIRAY_RELEASE_REPOSITORY="tensornull/LexiRay"

lexiray_validate_release_version() {
  local version="$1"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

lexiray_validate_release_origin() {
  local root_dir="$1"
  local remote_name="${2:-origin}"
  local remote_url

  remote_url="$(git -C "$root_dir" remote get-url "$remote_name" 2>/dev/null || true)"
  case "$remote_url" in
    "git@github.com:$LEXIRAY_RELEASE_REPOSITORY"|\
    "git@github.com:$LEXIRAY_RELEASE_REPOSITORY.git"|\
    "https://github.com/$LEXIRAY_RELEASE_REPOSITORY"|\
    "https://github.com/$LEXIRAY_RELEASE_REPOSITORY.git"|\
    "ssh://git@github.com/$LEXIRAY_RELEASE_REPOSITORY"|\
    "ssh://git@github.com/$LEXIRAY_RELEASE_REPOSITORY.git") return 0 ;;
    *) return 1 ;;
  esac
}

lexiray_has_fixed_release_certificate() {
  local keychain_path="${1:-}"
  local certificate_output
  local -a args=(-a -c "$LEXIRAY_RELEASE_IDENTITY_NAME" -Z)

  [[ -n "$keychain_path" ]] && args+=("$keychain_path")
  certificate_output="$(/usr/bin/security find-certificate "${args[@]}" 2>/dev/null || true)"
  /usr/bin/awk \
    -v expected_sha1="$LEXIRAY_RELEASE_CERT_SHA1" \
    -v expected_sha256="$LEXIRAY_RELEASE_CERT_SHA256" '
      /^SHA-256 hash:/ { sha256 = $3 }
      /^SHA-1 hash:/ {
        if ($3 == expected_sha1 && sha256 == expected_sha256) found = 1
        sha256 = ""
      }
      END { exit(found ? 0 : 1) }
    ' <<<"$certificate_output"
}

lexiray_app_certificate_sha256() {
  local app_path="$1"
  local temp_dir
  local fingerprint

  app_path="$(cd "$(dirname "$app_path")" && pwd -P)/$(basename "$app_path")"
  temp_dir="$(/usr/bin/mktemp -d)"
  if ! (cd "$temp_dir" && /usr/bin/codesign -d --extract-certificates "$app_path" >/dev/null 2>&1); then
    rm -rf "$temp_dir"
    return 1
  fi
  if [[ ! -f "$temp_dir/codesign0" ]]; then
    rm -rf "$temp_dir"
    return 1
  fi

  fingerprint="$(
    /usr/bin/openssl x509 \
      -inform DER \
      -in "$temp_dir/codesign0" \
      -noout \
      -fingerprint \
      -sha256 2>/dev/null |
      /usr/bin/awk -F= '{print $2}' |
      /usr/bin/tr -d ':'
  )"
  rm -rf "$temp_dir"
  [[ -n "$fingerprint" ]] || return 1
  printf '%s\n' "$fingerprint"
}

lexiray_app_designated_requirement() {
  local app_path="$1"
  local requirement

  requirement="$(
    /usr/bin/codesign -d -r- "$app_path" 2>&1 |
      /usr/bin/awk '
        /^designated => / && !found {
          sub(/^designated => /, "", $0)
          print
          found = 1
        }
      '
  )"
  [[ -n "$requirement" ]] || return 1
  printf '%s\n' "$requirement"
}

lexiray_sha256_text() {
  /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
}

lexiray_app_designated_requirement_sha256() {
  local requirement
  requirement="$(lexiray_app_designated_requirement "$1")" || return 1
  printf '%s' "$requirement" | lexiray_sha256_text
}

lexiray_app_entitlements_sha256() {
  local app_path="$1"
  local extracted
  local canonical
  local digest

  extracted="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/lexiray-entitlements.XXXXXX")"
  canonical="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/lexiray-entitlements-canonical.XXXXXX")"
  if ! /usr/bin/codesign -d --entitlements :- "$app_path" >"$extracted" 2>/dev/null ||
    ! /usr/bin/plutil -convert binary1 -o "$canonical" -- "$extracted" >/dev/null 2>&1; then
    /bin/rm -f "$extracted" "$canonical"
    return 1
  fi
  digest="$(/usr/bin/shasum -a 256 "$canonical" | /usr/bin/awk '{print $1}')"
  /bin/rm -f "$extracted" "$canonical"
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
  printf '%s\n' "$digest"
}

lexiray_plist_sha256() {
  local plist_path="$1"
  local canonical
  local digest

  [[ -f "$plist_path" ]] || return 1
  canonical="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/lexiray-plist-canonical.XXXXXX")"
  if ! /usr/bin/plutil -convert binary1 -o "$canonical" -- "$plist_path" >/dev/null 2>&1; then
    /bin/rm -f "$canonical"
    return 1
  fi
  digest="$(/usr/bin/shasum -a 256 "$canonical" | /usr/bin/awk '{print $1}')"
  /bin/rm -f "$canonical"
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
  printf '%s\n' "$digest"
}

lexiray_verify_release_app_identity() {
  local app_path="$1"
  local entitlements_path="$2"
  local certificate requirement requirement_hash expected_requirement expected_requirement_hash
  local entitlements_hash expected_entitlements_hash

  certificate="$(lexiray_app_certificate_sha256 "$app_path" 2>/dev/null || true)"
  [[ "$certificate" == "$LEXIRAY_RELEASE_CERT_SHA256" ]] || return 1
  requirement="$(lexiray_app_designated_requirement "$app_path" 2>/dev/null || true)"
  requirement_hash="$(printf '%s' "$requirement" | lexiray_sha256_text)"
  expected_requirement="identifier \"io.github.tensornull.lexiray\" and certificate leaf = H\"$(printf '%s' "$LEXIRAY_RELEASE_CERT_SHA1" | /usr/bin/tr '[:upper:]' '[:lower:]')\""
  expected_requirement_hash="$(printf '%s' "$expected_requirement" | lexiray_sha256_text)"
  [[ "$requirement" == "$expected_requirement" && "$requirement_hash" == "$expected_requirement_hash" ]] || return 1
  entitlements_hash="$(lexiray_app_entitlements_sha256 "$app_path" 2>/dev/null || true)"
  expected_entitlements_hash="$(lexiray_plist_sha256 "$entitlements_path" 2>/dev/null || true)"
  [[ -n "$entitlements_hash" && "$entitlements_hash" == "$expected_entitlements_hash" ]]
}

lexiray_verify_sha256_file() {
  local checksum_path="$1"
  local payload_path="$2"
  local expected_name="$3"
  local nonempty_lines
  local checksum_line
  local recorded_hash
  local recorded_name
  local actual_hash

  [[ -f "$checksum_path" && -f "$payload_path" ]] || return 1
  nonempty_lines="$(/usr/bin/awk 'NF { count++ } END { print count + 0 }' "$checksum_path")"
  [[ "$nonempty_lines" -eq 1 ]] || return 1
  checksum_line="$(/usr/bin/awk 'NF { print; exit }' "$checksum_path")"
  if ! [[ "$checksum_line" =~ ^([0-9a-fA-F]{64})[[:space:]][[:space:]\*]([^[:space:]]+)$ ]]; then
    return 1
  fi

  recorded_hash="$(printf '%s' "${BASH_REMATCH[1]}" | /usr/bin/tr '[:upper:]' '[:lower:]')"
  recorded_name="${BASH_REMATCH[2]}"
  [[ "$recorded_name" == "$expected_name" ]] || return 1
  if command -v shasum >/dev/null 2>&1; then
    actual_hash="$(shasum -a 256 "$payload_path" | /usr/bin/awk '{print $1}')"
  elif command -v sha256sum >/dev/null 2>&1; then
    actual_hash="$(sha256sum "$payload_path" | /usr/bin/awk '{print $1}')"
  else
    return 1
  fi
  actual_hash="$(printf '%s' "$actual_hash" | /usr/bin/tr '[:upper:]' '[:lower:]')"
  [[ "$recorded_hash" == "$actual_hash" ]]
}
