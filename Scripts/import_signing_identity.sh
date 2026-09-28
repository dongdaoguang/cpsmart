#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 /path/to/cpsmart-release-signing.p12" >&2
    exit 2
fi

P12_PATH="$1"
IDENTITY_NAME="cpsmart Release Signing"
if [[ ! -f "$P12_PATH" ]]; then
    echo "Signing identity backup not found: $P12_PATH" >&2
    exit 2
fi

LOGIN_KEYCHAIN="$(security login-keychain -d user 2>/dev/null || security login-keychain)"
LOGIN_KEYCHAIN="$(printf '%s' "$LOGIN_KEYCHAIN" | tr -d ' \"')"
if [[ -z "$LOGIN_KEYCHAIN" || ! -f "$LOGIN_KEYCHAIN" ]]; then
    echo "Unable to locate the current user's login keychain" >&2
    exit 1
fi

echo "macOS will ask for the .p12 export password in a secure system dialog."
security import \
    "$P12_PATH" \
    -k "$LOGIN_KEYCHAIN" \
    -T /usr/bin/codesign \
    -T /usr/bin/security

CERT_PATH="$(mktemp /tmp/cpsmart-release-signing.XXXXXX)"
trap 'unlink "$CERT_PATH" 2>/dev/null || true' EXIT
security find-certificate -c "$IDENTITY_NAME" -p "$LOGIN_KEYCHAIN" \
    | /usr/bin/openssl x509 -outform DER -out "$CERT_PATH"
security add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "$LOGIN_KEYCHAIN" \
    "$CERT_PATH"

echo
echo "Available code-signing identities:"
IDENTITIES="$(security find-identity -v -p codesigning "$LOGIN_KEYCHAIN")"
echo "$IDENTITIES"
if [[ "$IDENTITIES" != *"$IDENTITY_NAME"* ]]; then
    echo "Imported identity is not available for code signing" >&2
    exit 1
fi
