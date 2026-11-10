#!/bin/sh
# Run Technitium and, when dnsdist fronts it, configure it through the settings API:
#  - move the plain DNS listener off port 53 (TECHNITIUM_DNS_LISTEN)
#  - accept PROXY protocol from dnsdist on TECHNITIUM_PROXY_PORT so query logs, ACLs
#    and per-client blocking see the real client address
#  - turn off Technitium's own DoT/DoH/DoQ listeners, which dnsdist serves instead
# Technitium has no environment variables for these, and persists them in /etc/dns.
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
    curl -fsS -G "$api/settings/set" --data-urlencode "token=$token" \
        --data-urlencode "dnsServerLocalEndPoints=$TECHNITIUM_DNS_LISTEN" \
        --data-urlencode "enableDnsOverUdpProxy=true" \
        --data-urlencode "enableDnsOverTcpProxy=true" \
        --data-urlencode "dnsOverUdpProxyPort=$TECHNITIUM_PROXY_PORT" \
        --data-urlencode "dnsOverTcpProxyPort=$TECHNITIUM_PROXY_PORT" \
        --data-urlencode "dnsReverseProxyNetworkACL=$TECHNITIUM_PROXY_ACL" \
        --data-urlencode "enableDnsOverTls=false" \
        --data-urlencode "enableDnsOverHttps=false" \
        --data-urlencode "enableDnsOverQuic=false" >/dev/null \
        && echo "technitium-start: DNS on $TECHNITIUM_DNS_LISTEN, PROXY protocol on port $TECHNITIUM_PROXY_PORT"
}

if [ "${ENABLE_DNSDIST:-true}" = "true" ]; then
    move_dns_listener &
fi

# A trapped signal ends the first wait early; wait again so the wrapper only exits after Technitium has
# finished shutting down (supervisord and the container runtime kill anything still running when it exits).
wait "$pid"
wait "$pid"
