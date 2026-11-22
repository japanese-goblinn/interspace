#!/bin/bash
# Creates a local self-signed code signing identity for Interspace, one time.
#
# macOS ties the Accessibility and Screen Recording grants to the signature of the app.
# With a stable identity the grants stay valid after a rebuild.
#
# The identity lives in its own keychain, so the login keychain is not changed
# and codesign never shows a password prompt.
set -euo pipefail

IDENTITY="interspace local signing"
KEYCHAIN="$HOME/Library/Keychains/interspace-signing.keychain-db"
SECRET_DIR="$HOME/.config/interspace"
SECRET_FILE="$SECRET_DIR/signing-keychain-password"
OPENSSL=/usr/bin/openssl # LibreSSL: writes a PKCS#12 file that `security import` can read

# codesign --keychain finds the identity only in a keychain on the user's search list.
add_to_search_list() {
    security list-keychains -d user | grep -q "$KEYCHAIN" ||
        security list-keychains -d user -s $(security list-keychains -d user | tr -d '"') "$KEYCHAIN"
}

if [ -f "$KEYCHAIN" ] && [ -f "$SECRET_FILE" ] &&
   security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY"; then
    add_to_search_list
    echo "Signing identity already exists."
    exit 0
fi

umask 077
mkdir -p "$SECRET_DIR"
PASSWORD="$("$OPENSSL" rand -hex 24)"
printf '%s' "$PASSWORD" > "$SECRET_FILE"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.conf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.conf" 2>/dev/null
"$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$IDENTITY" -out "$WORK/identity.p12" -passout "pass:$PASSWORD"

rm -f "$KEYCHAIN"
security create-keychain -p "$PASSWORD" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN" # no auto-lock timeout
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null
# Lets codesign use the key with no prompt.
security set-key-partition-list -S apple-tool:,apple: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null
# codesign takes only a trusted identity. Asks for the login password once.
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"
add_to_search_list

echo "Created signing identity \"$IDENTITY\" in $KEYCHAIN"
