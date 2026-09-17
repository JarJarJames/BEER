#!/bin/bash
# One-time setup: creates a self-signed local code-signing certificate and
# trusts it, so builds signed with it don't hit Gatekeeper's "brand new
# unrecognized binary" wall after every rebuild the way ad-hoc signing does.
#
# Why this exists: CloudSync (Tools/CloudSync) is a self-contained .NET
# executable, ad-hoc signed by default. Ad-hoc signatures have no stable
# identity — every rebuild produces a signature Gatekeeper has never seen,
# and macOS can SIGKILL it outright ("Code Signature Invalid") until that
# exact binary is individually approved. A certificate-based identity is
# stable across rebuilds: trust it once here, and every future build signed
# with it (see build_cloudsync.sh / build_app.sh) inherits that trust.
#
# This modifies your login keychain's trust settings, which is why it's a
# separate script for you to run yourself rather than something run for you.
# You'll likely see a Keychain Access confirmation — approve it.
set -euo pipefail

IDENTITY="BEER Local Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Certificate '$IDENTITY' already exists in the login keychain. Nothing to do."
    exit 0
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "==> Generating self-signed code-signing certificate…"
cat > "$WORKDIR/codesign.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF

openssl req -x509 -newkey rsa:2048 -keyout "$WORKDIR/key.pem" \
    -out "$WORKDIR/cert.pem" -days 3650 -nodes \
    -config "$WORKDIR/codesign.cnf" -extensions ext

# -legacy: OpenSSL 3's default PKCS#12 encryption (AES + SHA-256 MAC) isn't
# something macOS's own PKCS#12 importer can verify — `security import` fails
# with "MAC verification failed" on it. The legacy RC2/3DES + SHA-1 scheme is
# what Apple's importer actually understands.
openssl pkcs12 -export -legacy -out "$WORKDIR/identity.p12" \
    -inkey "$WORKDIR/key.pem" -in "$WORKDIR/cert.pem" -passout pass:beer

echo "==> Importing into your login keychain…"
security import "$WORKDIR/identity.p12" -k "$KEYCHAIN" -P beer \
    -T /usr/bin/codesign -T /usr/bin/security

echo "==> Trusting it for code signing (you may see a confirmation prompt)…"
security add-trusted-cert -d -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORKDIR/cert.pem"

echo ""
echo "Done. '$IDENTITY' is ready — build_cloudsync.sh and build_app.sh will"
echo "now sign with it instead of ad-hoc."
