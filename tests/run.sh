#!/bin/sh
# Runs the test suites against a built image.
#   tests/run.sh [image]            default image: technitium-dns-multi:test
# Uses docker, or podman when docker is not installed (override with ENGINE=).
# The in-image suites install python3 with apt, so the host needs network access.
set -u
IMAGE=${1:-technitium-dns-multi:test}
HERE=$(cd "$(dirname "$0")" && pwd)
ENGINE=${ENGINE:-$(command -v docker || command -v podman)}
[ -n "$ENGINE" ] || { echo "neither docker nor podman found" >&2; exit 2; }
NAME=tdm-test-$$
fail=0

# containers need IPv6 enabled for the IPv6 checks
NET="--sysctl net.ipv6.conf.all.disable_ipv6=0 --sysctl net.ipv6.conf.default.disable_ipv6=0"
CAPS="--cap-add NET_ADMIN --cap-add NET_RAW --cap-add NET_BIND_SERVICE"

# shellcheck disable=SC2329
cleanup() { "$ENGINE" rm -f "$NAME" >/dev/null 2>&1; }
trap cleanup EXIT

suite() { # title, script, extra run arguments
    echo "== $1"
    # shellcheck disable=SC2086
    if "$ENGINE" run --rm --entrypoint sh $NET $CAPS -v "$HERE/$2:/suite.sh:ro,Z" -v "$HERE/backend.py:/tmp/backend.py:ro,Z" "$IMAGE" /suite.sh; then
        :
    else
        fail=1
    fi
}
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }
ex() { "$ENGINE" exec "$NAME" "$@"; }

suite "configuration rendering" render.sh
suite "dnsdist and per-client answers" dnsdist.sh

echo "== boot, virtual addresses, IPv4 and IPv6 queries, graceful stop"
# Some runners leave IPv6 off on container interfaces. Probe first, so the IPv6 checks are skipped (not failed) there.
# shellcheck disable=SC2086
probe=$("$ENGINE" run --rm --entrypoint sh $NET "$IMAGE" -c 'ip -6 addr show dev eth0 | grep -q "scope link" && echo eth0; ip -6 addr show dev lo | grep -q "::1" && echo lo' 2>/dev/null)
case "$probe" in *eth0*) vip='192.168.1.53/24,fd00:1::53/64'; v6vip=1 ;; *) vip='192.168.1.53/24'; v6vip=0; echo "  skip  IPv6 virtual address: no IPv6 on the container interface" ;; esac
case "$probe" in *lo*) v6lo=1 ;; *) v6lo=0; echo "  skip  query over ::1: no ::1 in the container" ;; esac
# shellcheck disable=SC2086
"$ENGINE" run -d --name "$NAME" $NET $CAPS -e DNS_SERVER_ADMIN_PASSWORD=test-password-123 \
    -e KEEPALIVED_VIP="$vip" "$IMAGE" >/dev/null || { bad "container did not start"; exit 1; }

healthy=0
i=0
while [ "$i" -lt 60 ]; do
    if ex /usr/local/bin/healthcheck.sh >/dev/null 2>&1 && ex supervisorctl status technitium 2>/dev/null | grep -q RUNNING; then healthy=1; break; fi
    i=$((i + 1)); sleep 2
done
if [ "$healthy" = 1 ]; then ok "health check passes"; else bad "health check did not pass within 120 s"; "$ENGINE" logs "$NAME" 2>&1 | tail -30; fi

for svc in technitium dnsdist keepalived; do
    if ex supervisorctl status "$svc" 2>/dev/null | grep -q RUNNING; then ok "$svc is running"; else bad "$svc is not running"; fi
done

i=0; vips=0
while [ "$i" -lt 20 ]; do
    addrs=$(ex ip -o addr show eth0 2>/dev/null)
    case "$addrs" in
        *192.168.1.53/24*)
            if [ "$v6vip" = 0 ]; then vips=1; break; fi
            case "$addrs" in *fd00:1::53/64*) vips=1; break ;; esac ;;
    esac
    i=$((i + 1)); sleep 2
done
if [ "$vips" = 1 ]; then ok "virtual address(es) assigned"; else bad "virtual addresses missing"; echo "$addrs" | sed 's/^/        | /'; fi

for target in 127.0.0.1 ::1; do
    if [ "$target" = ::1 ] && [ "$v6lo" = 0 ]; then continue; fi
    rc=$(ex dig +time=3 +tries=1 +noall +comments "@$target" localhost A 2>/dev/null | sed -n 's/.*status: \([A-Z]*\).*/\1/p')
    if [ "$rc" = NOERROR ]; then ok "dnsdist answers on $target"; else bad "dnsdist on $target returned '${rc:-nothing}'"; fi
done

"$ENGINE" stop -t 30 "$NAME" >/dev/null 2>&1
logs=$("$ENGINE" logs "$NAME" 2>&1)
case "$logs" in *"Technitium DNS Server was stopped successfully"*) ok "Technitium finished shutting down" ;; *) bad "Technitium did not finish shutting down" ;; esac
case "$logs" in *"stopped: technitium (exit status 0)"*) ok "Technitium exited with status 0" ;; *) bad "Technitium did not exit with status 0" ;; esac

if [ "$fail" = 0 ]; then echo "all tests passed"; else echo "tests failed"; fi
exit $fail
