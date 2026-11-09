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

# loopback is always allowed: the health check queries dnsdist from 127.0.0.1
DNSDIST_ACL_LUA=$(quote_list "$DNSDIST_ACL,127.0.0.0/8")

proxy=""
[ "$DNSDIST_BACKEND_PROXY_PROTOCOL" = "true" ] && proxy=", useProxyProtocol=true"
DNSDIST_BACKEND_LUA=$(printf '%s' "$DNSDIST_BACKENDS" | tr -d ' ' | tr ',' '\n' \
    | awk -v proxy="$proxy" 'NF { printf "newServer({address=\"%s\", name=\"backend%d\"%s})\n", $1, NR, proxy }')

DNSDIST_TLS_LUA=""
want_tls=false
for v in "$DNSDIST_ENABLE_DOT" "$DNSDIST_ENABLE_DOH" "$DNSDIST_ENABLE_DOQ"; do
    [ "$v" = "true" ] && want_tls=true
done
if [ "$want_tls" = "true" ]; then
    if [ -s "$DNSDIST_TLS_CERT" ] && [ -s "$DNSDIST_TLS_KEY" ]; then
        c=\"$DNSDIST_TLS_CERT\"; k=\"$DNSDIST_TLS_KEY\"
        if [ "$DNSDIST_ENABLE_DOT" = "true" ]; then
            DNSDIST_TLS_LUA="${DNSDIST_TLS_LUA}addTLSLocal(\"${DNSDIST_DOT_LISTEN}\", $c, $k)
"
        fi
        if [ "$DNSDIST_ENABLE_DOH" = "true" ]; then
            DNSDIST_TLS_LUA="${DNSDIST_TLS_LUA}addDOHLocal(\"${DNSDIST_DOH_LISTEN}\", $c, $k, \"${DNSDIST_DOH_PATH}\")
"
        fi
        if [ "$DNSDIST_ENABLE_DOQ" = "true" ]; then
            DNSDIST_TLS_LUA="${DNSDIST_TLS_LUA}addDOQLocal(\"${DNSDIST_DOQ_LISTEN}\", $c, $k)
"
        fi
    else
        echo "dnsdist-start: no certificate at $DNSDIST_TLS_CERT / $DNSDIST_TLS_KEY; encrypted DNS listeners are disabled" >&2
    fi
fi

export DNSDIST_ACL_LUA DNSDIST_BACKEND_LUA DNSDIST_TLS_LUA
envsubst < "$T/dnsdist.conf.tmpl" > "$OUT"

exec dnsdist --supervised -C "$OUT"
