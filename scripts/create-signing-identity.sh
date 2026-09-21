#!/bin/bash
#
# Creates a local, self-signed code signing identity for missbar, once per machine.
#
# Why this exists: CI builds are ad-hoc signed, and an ad-hoc signature has no stable identity
# for macOS to pin a permission to. Its designated requirement is a bare code-directory hash:
#
#     designated => cdhash H"500f2893..."
#
# which changes with every build, so Accessibility and Screen Recording have to be granted again
# after each update. Re-signing with a certificate produces an identity-based requirement:
#
#     designated => identifier "com.nexuskfk.missbar" and certificate root = H"04c1d506..."
#
# which is identical across builds, so the grants survive updates.
#
# The certificate is self-signed and never leaves this machine. It is NOT an Apple Developer ID:
# it does not satisfy Gatekeeper and does nothing for anyone else's Mac. It exists only so that
# this Mac can recognise successive builds as the same program.
#
# Idempotent: if the identity is already in the keychain, this does nothing.

set -euo pipefail

IDENTITY="${MISSBAR_SIGNING_IDENTITY:-missbar Local Signing}"
DIR="${MISSBAR_SIGNING_DIR:-$HOME/.local/share/missbar-signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    echo "Identity '$IDENTITY' already exists. Nothing to do."
    echo
    echo "Back it up if you have not: losing it means every permission has to be granted again."
    echo "  $DIR"
    exit 0
fi

mkdir -p "$DIR"
chmod 700 "$DIR"

# 20 years. codesign refuses to sign with an expired certificate, and an identity that expires
# is an identity that silently resets every permission on the day it does.
cat > "$DIR/openssl.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions    = v3
prompt             = no

[ dn ]
CN = $IDENTITY
O  = missbar
C  = US

[ v3 ]
basicConstraints       = critical, CA:false
keyUsage               = critical, digitalSignature
extendedKeyUsage       = critical, codeSigning
subjectKeyIdentifier   = hash
EOF

echo "Generating certificate…"
openssl req -x509 -newkey rsa:2048 -keyout "$DIR/key.pem" -out "$DIR/cert.pem" \
    -days 7300 -nodes -config "$DIR/openssl.cnf" 2>/dev/null
chmod 600 "$DIR/key.pem"

# PBE-SHA1-3DES and -macalg sha1 are required: Security.framework rejects PKCS#12 files that
# use the modern defaults with "MAC verification failed during PKCS12 import (wrong password?)",
# which reads like a password problem and is not one.
PW="missbar-local"
openssl pkcs12 -export -inkey "$DIR/key.pem" -in "$DIR/cert.pem" -out "$DIR/missbar-signing.p12" \
    -name "$IDENTITY" \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 \
    -passout "pass:$PW" 2>/dev/null
chmod 600 "$DIR/missbar-signing.p12"
printf '%s\n' "$PW" > "$DIR/.p12-password"
chmod 600 "$DIR/.p12-password"

echo "Importing into the login keychain…"
# -A lets codesign use the key without a confirmation dialog on every signature.
security import "$DIR/missbar-signing.p12" -k "$KEYCHAIN" -P "$PW" -A -T /usr/bin/codesign >/dev/null

# The certificate is deliberately NOT added to the trust store. codesign signs with an untrusted
# self-signed identity perfectly well — `security find-identity -v` hides it and reports
# CSSMERR_TP_NOT_TRUSTED, which is about Gatekeeper, not about whether it can sign. Trusting it
# would ask for an admin password and buy nothing here.
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    echo
    echo "Created '$IDENTITY'."
    security find-identity -p codesigning | grep "\"$IDENTITY\"" | sed 's/^/  /'
    echo
    echo "Back up $DIR — losing the key means macOS stops recognising new"
    echo "builds as the same app, and every permission has to be granted again."
    echo
    echo "Next: scripts/install-local.sh"
else
    echo "Import reported success but the identity is not visible. Aborting." >&2
    exit 1
fi
