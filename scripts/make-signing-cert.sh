#!/usr/bin/env bash
# Create a stable, self-signed code-signing identity for CallTape.
#
# Why: an ad-hoc signature (`codesign --sign -`) changes its code hash on every
# build, so macOS treats each rebuild as a new app and resets its permissions
# (Microphone, Contacts, Full Disk Access). Signing every build with the SAME
# self-signed certificate keeps a stable identity, so the permissions you grant
# once stick across rebuilds.
#
# Run this once:  ./scripts/make-signing-cert.sh
# Then build.sh will pick the identity up automatically.
set -euo pipefail

NAME="CallTape Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$NAME"; then
    echo "==> Signing identity already exists: $NAME"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions    = v3
prompt             = no
[dn]
CN = $NAME
[v3]
basicConstraints   = critical,CA:false
keyUsage           = critical,digitalSignature
extendedKeyUsage   = critical,codeSigning
EOF

echo "==> Generating self-signed code-signing certificate"
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" \
    -days 3650 -config "$tmp/openssl.cnf" >/dev/null 2>&1

openssl pkcs12 -export -legacy \
    -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
    -out "$tmp/identity.p12" -name "$NAME" -passout pass:calltape >/dev/null 2>&1

echo "==> Importing into your login keychain (you may be asked to allow codesign)"
security import "$tmp/identity.p12" -k "$KEYCHAIN" -P calltape -T /usr/bin/codesign

# Trust it for code signing in your own (user) trust settings. Best-effort.
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$tmp/cert.pem" 2>/dev/null \
    || echo "    (could not set trust automatically; signing still works)"

echo
echo "==> Done. Identity created: $NAME"
echo "    Now run: ./scripts/build.sh --install"
echo "    Grant permissions once; they will persist across future rebuilds."
