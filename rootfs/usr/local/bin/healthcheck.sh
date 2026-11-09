#!/bin/sh
# Used by keepalived (track_script) and the container HEALTHCHECK: the DNS path must answer.
# Queries dnsdist when it is enabled, Technitium directly otherwise. A reply counts as healthy
# when the server could answer (NOERROR or NXDOMAIN); SERVFAIL, REFUSED and timeouts do not,
# so a dead Technitium behind a running dnsdist is detected.
if [ "${ENABLE_DNSDIST:-true}" = "true" ]; then
    port=${DNSDIST_LISTEN##*:}
else
    port=53
fi
dig +time=2 +tries=1 +noall +comments -p "$port" @127.0.0.1 "${HEALTH_QUERY_NAME:-localhost}" A 2>/dev/null \
    | grep -Eq 'status: (NOERROR|NXDOMAIN)'
