#!/bin/sh
# Render config templates from environment variables, then hand off to supervisord.
set -eu

T=/usr/local/share/templates
OUT=/run/conf
mkdir -p "$OUT" /run/kea /run/postgresql /var/lib/kea /var/log/postgresql
chown postgres:postgres /run/postgresql /var/log/postgresql

# "a,b, c" -> list with one quoted item per element: "a","b","c"
quote_list() { printf '%s' "$1" | tr -d ' ' | sed 's/,/","/g; s/^/"/; s/$/"/'; }

# --- dnsdist ---------------------------------------------------------------
DNSDIST_ACL_LUA=$(quote_list "$DNSDIST_ACL")
DNSDIST_BACKEND_LUA=$(printf '%s' "$DNSDIST_BACKENDS" | tr -d ' ' | tr ',' '\n' \
    | awk 'NF { printf "newServer({address=\"%s\", name=\"backend%d\"})\n", $1, NR }')
export DNSDIST_ACL_LUA DNSDIST_BACKEND_LUA
envsubst < "$T/dnsdist.conf.tmpl" > "$OUT/dnsdist.conf"

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
