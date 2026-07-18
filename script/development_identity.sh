#!/usr/bin/env bash

# Public metadata for the fixed local development identity. This file contains
# no private key material or password. Normal builds verify this identity and
# fail closed; they never create, import, trust, or rotate certificates.
LEXIRAY_DEVELOPMENT_IDENTITY_NAME="LexiRay Local Development"
LEXIRAY_DEVELOPMENT_CERT_SHA1="B665AB9A2956DDD3C2712669E4DA0DBE30DA084D"
LEXIRAY_DEVELOPMENT_CERT_SHA256="77C74E4D76C7A7AE0D0FF77D5C4AA928E0FE75CA463BF7B5FC6D0C9E08F6D356"
LEXIRAY_DEVELOPMENT_SECURITY_TOOL="${LEXIRAY_DEVELOPMENT_SECURITY_TOOL:-/usr/bin/security}"
LEXIRAY_DEVELOPMENT_SWIFT_TOOL="${LEXIRAY_DEVELOPMENT_SWIFT_TOOL:-/usr/bin/swift}"

lexiray_development_keychain() {
  printf '%s\n' "${LEXIRAY_CODE_SIGN_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
}

lexiray_development_identity_output() {
  "$LEXIRAY_DEVELOPMENT_SECURITY_TOOL" find-identity -v -p codesigning "$(lexiray_development_keychain)" 2>/dev/null
}

lexiray_development_certificate_output() {
  "$LEXIRAY_DEVELOPMENT_SECURITY_TOOL" find-certificate \
    -a \
    -c "$LEXIRAY_DEVELOPMENT_IDENTITY_NAME" \
    -Z \
    "$(lexiray_development_keychain)" 2>/dev/null
}

lexiray_has_fixed_development_identity() {
  local identities certificates
  identities="$(lexiray_development_identity_output)" || return 1
  certificates="$(lexiray_development_certificate_output)" || return 1

  /usr/bin/awk \
    -v expected_sha1="$LEXIRAY_DEVELOPMENT_CERT_SHA1" \
    -v expected_name="$LEXIRAY_DEVELOPMENT_IDENTITY_NAME" '
      index($0, expected_sha1) && index($0, "\"" expected_name "\"") { found = 1 }
      END { exit(found ? 0 : 1) }
    ' <<<"$identities" || return 1

  /usr/bin/awk \
    -v expected_sha1="$LEXIRAY_DEVELOPMENT_CERT_SHA1" \
    -v expected_sha256="$LEXIRAY_DEVELOPMENT_CERT_SHA256" '
      /^SHA-256 hash:/ { sha256 = $3 }
      /^SHA-1 hash:/ {
        if ($3 == expected_sha1 && sha256 == expected_sha256) found = 1
        sha256 = ""
      }
      END { exit(found ? 0 : 1) }
    ' <<<"$certificates"
}

lexiray_probe_fixed_development_private_key() {
  local root_dir
  root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  "$LEXIRAY_DEVELOPMENT_SWIFT_TOOL" "$root_dir/script/probe_release_signing_identity.swift" \
    "$LEXIRAY_DEVELOPMENT_IDENTITY_NAME" \
    "$LEXIRAY_DEVELOPMENT_CERT_SHA256" >/dev/null 2>&1
}

lexiray_app_certificate_sha256_for_development() {
  local app_path="$1"
  local temp_dir fingerprint
  temp_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/lexiray-development-certificate.XXXXXX")"
  if ! (cd "$temp_dir" && /usr/bin/codesign -d --extract-certificates "$app_path" >/dev/null 2>&1) ||
    [[ ! -f "$temp_dir/codesign0" ]]; then
    /bin/rm -rf "$temp_dir"
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
  /bin/rm -rf "$temp_dir"
  [[ "$fingerprint" == "$LEXIRAY_DEVELOPMENT_CERT_SHA256" ]]
}

lexiray_verify_development_app_identity() {
  local app_path="$1"
  local signature requirement expected_requirement
  /usr/bin/codesign --verify --deep --strict "$app_path" >/dev/null 2>&1 || return 1
  signature="$(/usr/bin/codesign -dvvv "$app_path" 2>&1)" || return 1
  /usr/bin/grep -F "Authority=$LEXIRAY_DEVELOPMENT_IDENTITY_NAME" <<<"$signature" >/dev/null || return 1
  lexiray_app_certificate_sha256_for_development "$app_path" || return 1
  requirement="$(
    /usr/bin/codesign -d -r- "$app_path" 2>&1 |
      /usr/bin/awk '/^designated => / { sub(/^designated => /, ""); print; exit }'
  )"
  expected_requirement="identifier \"io.github.tensornull.lexiray\" and certificate leaf = H\"$(
    printf '%s' "$LEXIRAY_DEVELOPMENT_CERT_SHA1" | /usr/bin/tr '[:upper:]' '[:lower:]'
  )\""
  [[ "$requirement" == "$expected_requirement" ]]
}

development_identity_failure() {
  echo "The fixed LexiRay development signing identity is missing, inaccessible, or mismatched." >&2
  echo "Expected SHA-1: $LEXIRAY_DEVELOPMENT_CERT_SHA1" >&2
  echo "Expected SHA-256: $LEXIRAY_DEVELOPMENT_CERT_SHA256" >&2
  echo "Keychain: $(lexiray_development_keychain)" >&2
  echo "Run: ./script/development_identity.sh doctor" >&2
}

development_identity_verify() {
  if ! lexiray_has_fixed_development_identity ||
    ! lexiray_probe_fixed_development_private_key; then
    development_identity_failure
    return 1
  fi
  printf '%s\n' "$LEXIRAY_DEVELOPMENT_CERT_SHA1"
}

development_identity_doctor() {
  local identities certificates duplicate_count
  echo "Identity name: $LEXIRAY_DEVELOPMENT_IDENTITY_NAME"
  echo "Expected SHA-1: $LEXIRAY_DEVELOPMENT_CERT_SHA1"
  echo "Expected SHA-256: $LEXIRAY_DEVELOPMENT_CERT_SHA256"
  echo "Keychain: $(lexiray_development_keychain)"

  identities="$(lexiray_development_identity_output 2>/dev/null || true)"
  certificates="$(lexiray_development_certificate_output 2>/dev/null || true)"
  duplicate_count="$(/usr/bin/grep -c '^SHA-256 hash:' <<<"$certificates" || true)"
  echo "Same-name certificates: $duplicate_count"
  if [[ -n "$certificates" ]]; then
    /usr/bin/awk '/^SHA-(1|256) hash:/ { print }' <<<"$certificates"
  fi
  if [[ -n "$identities" ]]; then
    echo "Valid code-signing identities:"
    printf '%s\n' "$identities"
  else
    echo "Valid code-signing identities: unavailable or none"
  fi

  if development_identity_verify >/dev/null; then
    echo "DEVELOPMENT_IDENTITY_PASS"
    return 0
  fi
  echo "DEVELOPMENT_IDENTITY_FAIL" >&2
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  case "${1:-}" in
    verify) development_identity_verify ;;
    doctor) development_identity_doctor ;;
    verify-app)
      [[ $# -eq 2 ]] || { echo "usage: $0 verify-app <LexiRay.app>" >&2; exit 2; }
      lexiray_verify_development_app_identity "$2"
      ;;
    *) echo "usage: $0 verify|doctor" >&2; exit 2 ;;
  esac
fi
