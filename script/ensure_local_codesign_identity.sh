#!/usr/bin/env bash
set -euo pipefail

IDENTITY_NAME="${1:-${LEXIRAY_CODE_SIGN_IDENTITY:-LexiRay Local Development}}"
KEYCHAIN="${LEXIRAY_CODE_SIGN_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

identity_is_valid() {
  /usr/bin/security find-identity -p codesigning -v "$KEYCHAIN" 2>/dev/null |
    /usr/bin/grep -F "\"$IDENTITY_NAME\"" >/dev/null
}

if identity_is_valid; then
  exit 0
fi

tmp_dir="$(/usr/bin/mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cert_path="$tmp_dir/codesign.crt"
key_path="$tmp_dir/codesign.key"
p12_path="$tmp_dir/codesign.p12"
p12_password="lexiray-local-development"

/usr/bin/openssl req \
  -new \
  -newkey rsa:2048 \
  -nodes \
  -x509 \
  -days 3650 \
  -subj "/CN=$IDENTITY_NAME" \
  -keyout "$key_path" \
  -out "$cert_path" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

/usr/bin/openssl pkcs12 \
  -export \
  -name "$IDENTITY_NAME" \
  -inkey "$key_path" \
  -in "$cert_path" \
  -out "$p12_path" \
  -passout "pass:$p12_password" >/dev/null 2>&1

/usr/bin/security import "$p12_path" \
  -k "$KEYCHAIN" \
  -P "$p12_password" \
  -T /usr/bin/codesign \
  -T /usr/bin/security >/dev/null

/usr/bin/security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "$KEYCHAIN" \
  "$cert_path" >/dev/null

if ! identity_is_valid; then
  echo "Failed to create a valid local code signing identity: $IDENTITY_NAME" >&2
  echo "Keychain: $KEYCHAIN" >&2
  exit 1
fi
