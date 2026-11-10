#!/bin/sh
# Render config templates from environment variables, then hand off to supervisord.
set -eu

T=/usr/local/share/templates
OUT=/run/conf
mkdir -p "$OUT" /run/postgresql /var/log/postgresql
chown postgres:postgres /run/postgresql /var/log/postgresql

# --- keepalived ------------------------------------------------------------
# keepalived needs one VRRP instance per address family, so KEEPALIVED_VIP (comma separated, IPv4 and IPv6 mixed)
# is split by family. Peers and the unicast source are split the same way; a family without peers uses multicast.
by_family() { # family (4 or 6), comma separated list: the entries of that family, one per line
    printf '%s' "$2" | tr -d ' ' | tr ',' '\n' | sed '/^$/d' | if [ "$1" = 6 ]; then grep ':' || true; else grep -v ':' || true; fi
}
vrrp_instance() { # name, family
    vips=$(by_family "$2" "$KEEPALIVED_VIP")
    [ -n "$vips" ] || return 0
    peers=$(by_family "$2" "$KEEPALIVED_UNICAST_PEERS")
    src=$(by_family "$2" "$KEEPALIVED_UNICAST_SRC")
    printf 'vrrp_instance %s {\n    state %s\n    interface %s\n    virtual_router_id %s\n    priority %s\n    advert_int 1\n' \
        "$1" "$KEEPALIVED_STATE" "$KEEPALIVED_INTERFACE" "$KEEPALIVED_VRID" "$KEEPALIVED_PRIORITY"
    if [ -n "$peers" ]; then
        # the source address is optional; without it keepalived uses the interface address
        if [ -n "$src" ]; then printf '    unicast_src_ip %s\n' "$src"; fi
        printf '    unicast_peer {\n%s\n    }\n' "$(printf '%s\n' "$peers" | sed 's/^/        /')"
    fi
    printf '    virtual_ipaddress {\n%s\n    }\n    track_script {\n        chk_dns\n    }\n}\n' "$(printf '%s\n' "$vips" | sed 's/^/        /')"
}
inst4=$(vrrp_instance DNS 4)
inst6=$(vrrp_instance DNS6 6)
KEEPALIVED_INSTANCES="${inst4}
${inst6}"
# both instances must hold their addresses on the same node
if [ -n "$inst4" ] && [ -n "$inst6" ]; then
    KEEPALIVED_INSTANCES="${KEEPALIVED_INSTANCES}

vrrp_sync_group DNS_GROUP {
    group {
        DNS
        DNS6
    }
}"
fi
export KEEPALIVED_INSTANCES
envsubst < "$T/keepalived.conf.tmpl" > "$OUT/keepalived.conf"
if [ "${ENABLE_KEEPALIVED:-true}" = "true" ] && ! keepalived -t -f "$OUT/keepalived.conf" >/tmp/keepalived-check.log 2>&1; then
    echo "entrypoint: the generated keepalived configuration is invalid:" >&2
    cat /tmp/keepalived-check.log >&2
    exit 1
fi

# --- pgbouncer -------------------------------------------------------------
# entries are separated by ';' in the variable, one per line in the file
PGBOUNCER_DATABASES=$(printf '%s' "$PGBOUNCER_DATABASES" | tr ';' '\n' | sed 's/^[[:space:]]*//')
export PGBOUNCER_DATABASES
envsubst < "$T/pgbouncer.ini.tmpl" > "$OUT/pgbouncer.ini"
chmod 644 "$OUT/pgbouncer.ini"

exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
