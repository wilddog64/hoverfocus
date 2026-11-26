#!/usr/bin/env bash
set -euo pipefail
umask 077

SECURITY="${SECURITY:-security}"
CODESIGN="${CODESIGN:-codesign}"
OPENSSL="${OPENSSL:-/usr/bin/openssl}"
SIGNING_NAME="${SIGNING_NAME:-HoverFocus Local Signing}"

if [ -z "$SIGNING_NAME" ] || [[ "$SIGNING_NAME" == *$'\n'* ]]; then
    echo "error: invalid SIGNING_NAME" >&2
    exit 2
fi

if [ -n "${SSH_CONNECTION:-}" ]; then
    echo "error: make signing-identity cannot run over SSH (Keychain prompt requires GUI session)" >&2
    exit 2
fi

keychain="$HOME/Library/Keychains/login.keychain-db"
if "$SECURITY" find-certificate -c "$SIGNING_NAME" "$keychain" >/dev/null 2>&1; then
    echo "already present"
    exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cat << EOF > "$tmp/req.cnf"
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $SIGNING_NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$tmp/req.cnf" -keyout "$tmp/key.pem" -out "$tmp/cert.pem"
pass="$("$OPENSSL" rand -hex 24)"
P12_PASS="$pass" "$OPENSSL" pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$SIGNING_NAME" -out "$tmp/id.p12" -passout env:P12_PASS
CODESIGN_PATH=$(command -v "$CODESIGN" || echo "$CODESIGN")
"$SECURITY" import "$tmp/id.p12" -k "$keychain" -f pkcs12 -P "$pass" -T "$CODESIGN_PATH"
unset pass
rm -f "$tmp/key.pem" "$tmp/id.p12"

id_out=$("$SECURITY" find-identity -p codesigning "$keychain")
if ! echo "$id_out" | grep -Fq "\"$SIGNING_NAME\""; then
    exit 1
fi
