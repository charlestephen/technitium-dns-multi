#!/bin/sh
# shellcheck disable=SC2089,SC2090
# Render the dnsdist configuration from the environment and run dnsdist.
# Rendering happens at every (re)start so that new certificates are picked up
# by restarting the program (acme-deploy.sh does this after each issue/renewal).
set -eu

T=/usr/local/share/templates
OUT=/run/conf/dnsdist.conf
mkdir -p /run/conf

# "a,b, c" -> "a","b","c"
quote_list() { printf '%s' "$1" | tr -d ' ' | sed 's/,/","/g; s/^/"/; s/$/"/'; }

# Every listener setting is a comma separated list of addresses. dnsdist binds IPv6 sockets IPv6-only, so the
# defaults list an IPv4 and an IPv6 address. IPv6 entries are skipped when the kernel has no IPv6.
if [ -r /proc/net/if_inet6 ]; then
    v6=true
else
    v6=false
fi
addr_list() { # comma separated list -> usable addresses, one per line
    # the newline matters: read drops a last line that has none
    printf '%s\n' "$1" | tr -d ' ' | tr ',' '\n' | sed '/^$/d' | while IFS= read -r a; do
        case "$a" in
            "["*) if [ "$v6" != "true" ]; then echo "dnsdist-start: IPv6 is not available; skipping $a" >&2; continue; fi ;;
        esac
        printf '%s\n' "$a"
    done
}
# one Lua statement per address; $1 is a printf format with %s for the address
lua_each() { addr_list "$2" | awk -v fmt="$1" '{ printf fmt "\n", $0 }'; }

DNSDIST_LISTEN_LUA=$(addr_list "$DNSDIST_LISTEN" | awk 'NR == 1 { printf "setLocal(\"%s\")\n", $0; next } { printf "addLocal(\"%s\")\n", $0 }')

# loopback is always allowed: the health check queries dnsdist from 127.0.0.1
DNSDIST_ACL_LUA=$(quote_list "$DNSDIST_ACL,127.0.0.0/8,::1/128")

proxy=""
[ "$DNSDIST_BACKEND_PROXY_PROTOCOL" = "true" ] && proxy=", useProxyProtocol=true"
# Backend health checks ask for a name the backend answers locally. dnsdist's default (a.root-servers.net)
# makes a recursive resolver query the internet, which times out where external DNS is slow or blocked.
check="${HEALTH_QUERY_NAME:-localhost}"
case "$check" in *.) ;; *) check="$check." ;; esac
DNSDIST_BACKEND_LUA=$(printf '%s' "$DNSDIST_BACKENDS" | tr -d ' ' | tr ',' '\n' \
    | awk -v proxy="$proxy" -v check="$check" 'NF { printf "newServer({address=\"%s\", name=\"backend%d\", checkName=\"%s\"%s})\n", $1, NR, check, proxy }')

# Built-in web dashboard and API. Without a password nothing is started, because dnsdist would otherwise
# serve the dashboard unauthenticated to every address in the ACL.
lua_str() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
# value of $1, or the contents of the file named by $1_FILE
secret() {
    v=$(printenv "$1" || true)
    if [ -z "$v" ]; then
        f=$(printenv "$1_FILE" || true)
        if [ -n "$f" ]; then v=$(cat "$f"); fi
    fi
    printf '%s' "$v"
}
DNSDIST_WEB_LUA=""
web_pw=$(secret DNSDIST_WEB_PASSWORD)
if [ -n "$web_pw" ]; then
    web_key=$(secret DNSDIST_WEB_API_KEY)
    web_acl=$(printf '%s' "$DNSDIST_WEB_ACL" | tr -d ' ')
    api=""
    if [ -n "$web_key" ]; then api=", apiKey=\"$(lua_str "$web_key")\""; fi
    DNSDIST_WEB_LUA="webserver(\"${DNSDIST_WEB_LISTEN}\")
setWebserverConfig({password=\"$(lua_str "$web_pw")\"${api}, acl=\"${web_acl}\"})"
else
    echo "dnsdist-start: DNSDIST_WEB_PASSWORD is not set; the dashboard is disabled" >&2
fi

DNSDIST_TLS_LUA=""
want_tls=false
for v in "$DNSDIST_ENABLE_DOT" "$DNSDIST_ENABLE_DOH" "$DNSDIST_ENABLE_DOQ"; do
    [ "$v" = "true" ] && want_tls=true
done
if [ "$want_tls" = "true" ]; then
    if [ -s "$DNSDIST_TLS_CERT" ] && [ -s "$DNSDIST_TLS_KEY" ]; then
        c=\"$DNSDIST_TLS_CERT\"; k=\"$DNSDIST_TLS_KEY\"
        if [ "$DNSDIST_ENABLE_DOT" = "true" ]; then
            DNSDIST_TLS_LUA="${DNSDIST_TLS_LUA}$(lua_each "addTLSLocal(\"%s\", $c, $k)" "$DNSDIST_DOT_LISTEN")
"
        fi
        if [ "$DNSDIST_ENABLE_DOH" = "true" ]; then
            DNSDIST_TLS_LUA="${DNSDIST_TLS_LUA}$(lua_each "addDOHLocal(\"%s\", $c, $k, \"${DNSDIST_DOH_PATH}\")" "$DNSDIST_DOH_LISTEN")
"
        fi
        if [ "$DNSDIST_ENABLE_DOQ" = "true" ]; then
            DNSDIST_TLS_LUA="${DNSDIST_TLS_LUA}$(lua_each "addDOQLocal(\"%s\", $c, $k)" "$DNSDIST_DOQ_LISTEN")
"
        fi
    else
        echo "dnsdist-start: no certificate at $DNSDIST_TLS_CERT / $DNSDIST_TLS_KEY; encrypted DNS listeners are disabled" >&2
    fi
fi

# the rendered file can contain the dashboard password: readable by root only
umask 077
export DNSDIST_LISTEN_LUA DNSDIST_ACL_LUA DNSDIST_BACKEND_LUA DNSDIST_TLS_LUA DNSDIST_WEB_LUA
envsubst < "$T/dnsdist.conf.tmpl" > "$OUT"

exec dnsdist --supervised -C "$OUT"
