#!/bin/sh
# Issue/renew a certificate with acme.sh (DNS-01) and publish it as a PKCS#12 file
# that Technitium can load (web console, DoT, DoH).
set -eu

if [ -z "${ACME_DOMAINS:-}" ] || [ -z "${ACME_DNS_PROVIDER:-}" ]; then
    echo "acme: ACME_DOMAINS and ACME_DNS_PROVIDER are required; idling" >&2
    exec sleep infinity
fi

ACME=/opt/acme.sh/acme.sh
H="--home /opt/acme.sh --config-home /var/lib/acme.sh"
CERT_DIR=/etc/dns/certs
mkdir -p "$CERT_DIR"

domain_args=""
for d in $(printf '%s' "$ACME_DOMAINS" | tr ',' ' '); do domain_args="$domain_args -d $d"; done
first=${ACME_DOMAINS%%,*}

# shellcheck disable=SC2086
"$ACME" $H --set-default-ca --server "$ACME_SERVER"
# shellcheck disable=SC2086
[ -z "${ACME_EMAIL:-}" ] || "$ACME" $H --register-account -m "$ACME_EMAIL" || true

# Exit code 2 means "not due for renewal yet".
# shellcheck disable=SC2086
"$ACME" $H --issue --dns "$ACME_DNS_PROVIDER" $domain_args --keylength ec-256 || [ $? -eq 2 ]

# shellcheck disable=SC2086
"$ACME" $H --install-cert -d "$first" --ecc \
    --key-file "$CERT_DIR/key.pem" \
    --fullchain-file "$CERT_DIR/fullchain.pem" \
    --reloadcmd "openssl pkcs12 -export -inkey $CERT_DIR/key.pem -in $CERT_DIR/fullchain.pem -out $CERT_DIR/technitium.pfx -passout env:ACME_PFX_PASSWORD"

while :; do
    sleep 43200
    # shellcheck disable=SC2086
    "$ACME" $H --cron || echo "acme: renewal run failed" >&2
done
