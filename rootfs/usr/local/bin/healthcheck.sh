#!/bin/sh
# Used by keepalived (track_script) and the container HEALTHCHECK: the DNS path must answer.
# Queries dnsdist when it is enabled, Technitium directly otherwise.
if [ "${ENABLE_DNSDIST:-true}" = "true" ]; then
    server=127.0.0.1; port=${DNSDIST_LISTEN##*:}
else
    server=127.0.0.1; port=53
fi
dig +time=2 +tries=1 +short -p "$port" @"$server" "${HEALTH_QUERY_NAME:-localhost}" A >/dev/null
