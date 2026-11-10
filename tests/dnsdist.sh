#!/bin/sh
# Runs inside the image, with backend.py mounted at /tmp/backend.py. Checks that dnsdist passes each client's
# address to the backend and that, with the default settings, one client's answer is not served to another.
set -u
apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq --no-install-recommends python3 >/dev/null 2>&1
command -v python3 >/dev/null || { echo "  FAIL  could not install python3"; exit 1; }
fail=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }

# the IPv6 checks need ::1 on the loopback interface
if ip -6 addr show dev lo 2>/dev/null | grep -q '::1'; then v6=true; listen='127.0.0.1:5399,[::1]:5399'; else v6=false; listen='127.0.0.1:5399'; echo "  skip  IPv6 checks: no ::1 in this container"; fi

sed '$d' /usr/local/bin/dnsdist-start.sh > /tmp/dd.sh
export DNSDIST_BACKENDS=127.0.0.1:5300 DNSDIST_LISTEN="$listen" \
    DNSDIST_ACL=127.0.0.0/8,::1/128 DNSDIST_ENABLE_DOT=false DNSDIST_ENABLE_DOH=false DNSDIST_ENABLE_DOQ=false
sh /tmp/dd.sh 2>/dev/null
python3 /tmp/backend.py >/tmp/backend.out 2>&1 &
sleep 1
dnsdist --supervised -C /run/conf/dnsdist.conf >/tmp/dnsdist.out 2>&1 &
sleep 4

status() { # source address, name, server -> rcode
    dig -b "$1" +time=2 +tries=1 +noall +comments -p 5399 "@$3" "$2" A 2>&1 | sed -n 's/.*status: \([A-Z]*\).*/\1/p'
}
expect() { # description, got, want
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi
}

expect "unblocked client gets the answer"            "$(status 127.0.0.2 a.example.test 127.0.0.1)" NOERROR
expect "blocked client is not served that answer"    "$(status 127.0.0.3 a.example.test 127.0.0.1)" NXDOMAIN
expect "same, other way round (new name)"            "$(status 127.0.0.3 b.example.test 127.0.0.1)" NXDOMAIN
expect "unblocked client after the blocked one"      "$(status 127.0.0.2 b.example.test 127.0.0.1)" NOERROR
if [ "$v6" = true ]; then
    expect "client address reaches the backend over IPv6" "$(status ::1 a.example.test ::1)" NXDOMAIN
    if grep -q ' ::1 NXDOMAIN' /tmp/backend.log; then ok "backend saw the IPv6 client address"; else bad "backend did not see ::1"; fi
fi
expect "IPv4 query reaches the IPv4 listener"        "$(status 127.0.0.2 c.example.test 127.0.0.1)" NOERROR
exit $fail
