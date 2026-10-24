#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERT_DIR="$ROOT/certs"
NAME="Islet Development"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning 2>/dev/null | grep -q "$NAME"; then
  echo "signing identity '$NAME' already exists"
  security find-identity -p codesigning | grep "$NAME" || true
  exit 0
fi

mkdir -p "$CERT_DIR"

cat > "$CERT_DIR/openssl.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = Islet Development
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF

openssl req -x509 \
  -newkey rsa:2048 \
  -keyout "$CERT_DIR/islet-key.pem" \
  -out "$CERT_DIR/islet-cert.pem" \
  -days 3650 \
  -nodes \
  -config "$CERT_DIR/openssl.cnf" >/dev/null 2>&1

# LibreSSL's modern PKCS#12 defaults are not readable by `security import`.
openssl pkcs12 -export \
  -out "$CERT_DIR/islet.p12" \
  -inkey "$CERT_DIR/islet-key.pem" \
  -in "$CERT_DIR/islet-cert.pem" \
  -name "$NAME" \
  -passout pass:islet \
  -macalg sha1 \
  -keypbe PBE-SHA1-3DES \
  -certpbe PBE-SHA1-3DES >/dev/null 2>&1

security import "$CERT_DIR/islet.p12" \
  -k "$KEYCHAIN" \
  -P "islet" \
  -T /usr/bin/codesign \
  -T /usr/bin/security >/dev/null

echo "created signing identity '$NAME'"
security find-identity -p codesigning | grep "$NAME" || true
echo
echo "If macOS refuses to remember Calendar access, trust the certificate once:"
echo "  security add-trusted-cert -r trustRoot -k \"$KEYCHAIN\" \"$CERT_DIR/islet-cert.pem\""
