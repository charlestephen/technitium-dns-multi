#!/bin/sh
# Run Technitium and, when dnsdist fronts it, move Technitium off port 53.
# Technitium has no environment variable for its DNS listen address, so it is set
# through the settings API once the web service is up. The value is persisted in
# /etc/dns, so later boots find it already applied.
set -u

dotnet /opt/technitium/dns/DnsServerApp.dll /etc/dns &
pid=$!
trap 'kill -TERM "$pid" 2>/dev/null' TERM INT

move_dns_listener() {
    pass=${DNS_SERVER_ADMIN_PASSWORD:-}
    if [ -z "$pass" ] && [ -n "${DNS_SERVER_ADMIN_PASSWORD_FILE:-}" ]; then
        pass=$(cat "$DNS_SERVER_ADMIN_PASSWORD_FILE")
    fi
    if [ -z "$pass" ]; then
        echo "technitium-start: no admin password set; cannot move DNS listener to $TECHNITIUM_DNS_LISTEN" >&2
        return 1
    fi
    api="http://127.0.0.1:${DNS_SERVER_WEB_SERVICE_HTTP_PORT:-5380}/api"
    i=0
    while [ "$i" -lt 60 ]; do
        token=$(curl -fsS -G "$api/user/login" --data-urlencode "user=admin" --data-urlencode "pass=$pass" 2>/dev/null \
            | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
        [ -n "$token" ] && break
        i=$((i + 1)); sleep 2
    done
    [ -n "${token:-}" ] || { echo "technitium-start: API login failed" >&2; return 1; }
    if curl -fsS -G "$api/settings/get" --data-urlencode "token=$token" | grep -q "\"$TECHNITIUM_DNS_LISTEN\""; then
        return 0
    fi
    curl -fsS -G "$api/settings/set" --data-urlencode "token=$token" \
        --data-urlencode "dnsServerLocalEndPoints=$TECHNITIUM_DNS_LISTEN" >/dev/null \
        && echo "technitium-start: DNS listener set to $TECHNITIUM_DNS_LISTEN"
}

if [ "${ENABLE_DNSDIST:-true}" = "true" ]; then
    move_dns_listener &
fi

wait "$pid"
