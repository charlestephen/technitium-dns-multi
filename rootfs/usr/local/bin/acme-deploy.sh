#!/bin/sh
# Called by acme.sh after each issue/renewal: publish a PKCS#12 file for Technitium
# and restart dnsdist so it loads the new PEM certificate.
set -eu
CERT_DIR=/etc/dns/certs
openssl pkcs12 -export -inkey "$CERT_DIR/key.pem" -in "$CERT_DIR/fullchain.pem" \
    -out "$CERT_DIR/technitium.pfx" -passout env:ACME_PFX_PASSWORD
if [ "${ENABLE_DNSDIST:-true}" = "true" ]; then
    supervisorctl restart dnsdist || echo "acme-deploy: could not restart dnsdist" >&2
fi
