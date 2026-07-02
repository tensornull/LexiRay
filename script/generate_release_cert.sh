#!/usr/bin/env bash
set -euo pipefail

# Generate a new release signing certificate that can be shared between local and CI builds

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDENTITY_NAME="LexiRay Release Self-Signed"
CERT_PATH="$ROOT_DIR/build/release-cert.crt"
KEY_PATH="$ROOT_DIR/build/release-cert.key"
P12_PATH="$ROOT_DIR/build/release-signing.p12"
P12_PASSWORD="${LEXIRAY_RELEASE_CERT_PASSWORD:-lexiray-release-2026}"

mkdir -p "$ROOT_DIR/build"

echo "Generating release certificate..."

/usr/bin/openssl req \
  -new \
  -newkey rsa:4096 \
  -nodes \
  -x509 \
  -days 7300 \
  -subj "/CN=$IDENTITY_NAME" \
  -keyout "$KEY_PATH" \
  -out "$CERT_PATH" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"

echo "Creating PKCS12 bundle..."

/usr/bin/openssl pkcs12 \
  -export \
  -name "$IDENTITY_NAME" \
  -inkey "$KEY_PATH" \
  -in "$CERT_PATH" \
  -out "$P12_PATH" \
  -passout "pass:$P12_PASSWORD"

echo ""
echo "Release certificate generated:"
echo "  Certificate: $CERT_PATH"
echo "  PKCS12: $P12_PATH"
echo "  Password: $P12_PASSWORD"
echo ""
echo "To set up GitHub secrets, run:"
echo "  base64 -i $P12_PATH | pbcopy"
echo "  # Then paste into GitHub Secrets as LEXIRAY_RELEASE_CERT_P12_BASE64"
echo ""
echo "To set up local environment, add to your shell profile:"
echo "  export LEXIRAY_RELEASE_CERT_P12_BASE64=\$(base64 -i $P12_PATH)"
echo "  export LEXIRAY_RELEASE_CERT_PASSWORD='$P12_PASSWORD'"
echo ""
