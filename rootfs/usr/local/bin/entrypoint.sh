#!/bin/sh
# Render config templates from environment variables, then hand off to supervisord.
set -eu

T=/usr/local/share/templates
OUT=/run/conf
mkdir -p "$OUT" /run/kea /run/postgresql /var/lib/kea /var/log/postgresql
chown postgres:postgres /run/postgresql /var/log/postgresql
chmod 750 /run/kea /var/lib/kea

# --- keepalived ------------------------------------------------------------
KEEPALIVED_UNICAST_BLOCK=""
if [ -n "$KEEPALIVED_UNICAST_PEERS" ]; then
    peers=$(printf '%s' "$KEEPALIVED_UNICAST_PEERS" | tr -d ' ' | tr ',' '\n' | sed 's/^/        /')
    KEEPALIVED_UNICAST_BLOCK="unicast_src_ip ${KEEPALIVED_UNICAST_SRC}
    unicast_peer {
${peers}
    }"
fi
export KEEPALIVED_UNICAST_BLOCK
envsubst < "$T/keepalived.conf.tmpl" > "$OUT/keepalived.conf"

# --- pgbouncer -------------------------------------------------------------
# entries are separated by ';' in the variable, one per line in the file
PGBOUNCER_DATABASES=$(printf '%s' "$PGBOUNCER_DATABASES" | tr ';' '\n' | sed 's/^[[:space:]]*//')
export PGBOUNCER_DATABASES
envsubst < "$T/pgbouncer.ini.tmpl" > "$OUT/pgbouncer.ini"
chmod 644 "$OUT/pgbouncer.ini"

# --- kea (DHCPv4 + HA control agent) ----------------------------------------
if [ "$KEA_HA_ROLE" = "primary" ]; then
    KEA_HA_THIS_NAME=dhcp-primary
else
    KEA_HA_THIS_NAME=dhcp-secondary
fi
export KEA_HA_THIS_NAME
envsubst < "$T/kea-dhcp4.conf.tmpl" > "$OUT/kea-dhcp4.conf"
envsubst < "$T/kea-ctrl-agent.conf.tmpl" > "$OUT/kea-ctrl-agent.conf"

if [ "$ENABLE_KEA" = "true" ] && [ "$ENABLE_TECHNITIUM" = "true" ]; then
    echo "entrypoint: Kea is enabled; turn off Technitium's own DHCP scopes or both will answer on :67" >&2
fi

exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
