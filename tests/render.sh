#!/bin/sh
# Runs inside the image. Renders the configuration for several environments and runs each program's own
# configuration check. The last line of entrypoint.sh and dnsdist-start.sh (the exec) is dropped.
set -u
mkdir -p /tmp/t
sed '$d' /usr/local/bin/entrypoint.sh > /tmp/t/entry.sh
sed '$d' /usr/local/bin/dnsdist-start.sh > /tmp/t/dd.sh
fail=0

ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; fail=1; }
check() { # name, command...
    n=$1; shift
    if out=$("$@" 2>&1); then ok "$n"; else bad "$n"; echo "$out" | sed 's/^/        | /' | head -10; fi
}
contains() { # name, file, fixed string
    if grep -qF -- "$3" "$2"; then ok "$1"; else bad "$1 (missing: $3)"; fi
}
render() { sh /tmp/t/entry.sh >/tmp/t/entry.out 2>&1 && sh /tmp/t/dd.sh >/tmp/t/dd.out 2>&1; }

echo "defaults"
render || { bad "render"; cat /tmp/t/entry.out /tmp/t/dd.out; }
check "keepalived config valid" keepalived -t -f /run/conf/keepalived.conf
check "dnsdist config valid" dnsdist --check-config -C /run/conf/dnsdist.conf
contains "packet cache is off" /run/conf/dnsdist.conf "if 0 > 0 then"
contains "dnsdist listens on IPv4" /run/conf/dnsdist.conf 'setLocal("0.0.0.0:53")'
contains "dnsdist listens on IPv6" /run/conf/dnsdist.conf 'addLocal("[::]:53")'
contains "ACL allows IPv6 ULA" /run/conf/dnsdist.conf 'fc00::/7'

echo "packet cache enabled"
export DNSDIST_CACHE_ENTRIES=5000
render
check "dnsdist config valid" dnsdist --check-config -C /run/conf/dnsdist.conf
contains "packet cache size rendered" /run/conf/dnsdist.conf "if 5000 > 0 then"
export DNSDIST_CACHE_ENTRIES=0

echo "TLS listeners, dashboard, several backends"
mkdir -p /etc/dns/certs
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 1 -subj /CN=test \
    -keyout /etc/dns/certs/key.pem -out /etc/dns/certs/fullchain.pem 2>/dev/null
# the quotes, dollar sign and backslash in the password are deliberate: they test escaping
# shellcheck disable=SC2016,SC2089
export DNSDIST_WEB_PASSWORD='pa"ss$word\x' DNSDIST_WEB_API_KEY='k"ey' DNSDIST_BACKENDS='10.0.0.1:538, 10.0.0.2:538' DNSDIST_ACL='10.1.0.0/16, 192.168.0.0/16'
render
check "dnsdist config valid (DoT, DoH, DoQ, dashboard)" dnsdist --check-config -C /run/conf/dnsdist.conf
contains "DoT on IPv4 and IPv6" /run/conf/dnsdist.conf 'addTLSLocal("[::]:853"'
contains "DoH on IPv6" /run/conf/dnsdist.conf 'addDOHLocal("[::]:443"'
contains "DoQ on IPv6" /run/conf/dnsdist.conf 'addDOQLocal("[::]:853"'
# shellcheck disable=SC2016
contains "password escaped" /run/conf/dnsdist.conf 'password="pa\"ss$word\\x"'
contains "second backend" /run/conf/dnsdist.conf 'address="10.0.0.2:538"'
# shellcheck disable=SC2090
export DNSDIST_WEB_PASSWORD='' DNSDIST_WEB_API_KEY='' DNSDIST_BACKENDS=127.0.0.1:538 DNSDIST_ACL=127.0.0.0/8
rm -f /etc/dns/certs/key.pem /etc/dns/certs/fullchain.pem

echo "keepalived"
export KEEPALIVED_UNICAST_PEERS=192.168.1.12 KEEPALIVED_UNICAST_SRC=''
render
check "unicast peer without a source address" keepalived -t -f /run/conf/keepalived.conf
export KEEPALIVED_UNICAST_SRC=192.168.1.11
render
check "unicast peer with a source address" keepalived -t -f /run/conf/keepalived.conf
contains "unicast source rendered" /run/conf/keepalived.conf "unicast_src_ip 192.168.1.11"
export KEEPALIVED_UNICAST_PEERS='' KEEPALIVED_UNICAST_SRC='' KEEPALIVED_VIP='192.168.1.53/24, fd00:1::53/64'
render
check "IPv4 and IPv6 addresses" keepalived -t -f /run/conf/keepalived.conf
contains "IPv6 instance" /run/conf/keepalived.conf "vrrp_instance DNS6"
contains "sync group" /run/conf/keepalived.conf "vrrp_sync_group DNS_GROUP"
export KEEPALIVED_VIP=fd00:1::53/64
render
check "IPv6 only" keepalived -t -f /run/conf/keepalived.conf
export KEEPALIVED_VIP=192.168.1.53/24

echo "an invalid keepalived configuration stops the container with the error"
export KEEPALIVED_VIP=not-an-address
if out=$(sh /usr/local/bin/entrypoint.sh 2>&1); then bad "entrypoint accepted an invalid VIP"; else
    case "$out" in *"keepalived configuration is invalid"*) ok "entrypoint exits with a message" ;; *) bad "no message: $out" ;; esac
fi
export KEEPALIVED_VIP=192.168.1.53/24

echo "PgBouncer"
export PGBOUNCER_DATABASES='app=host=10.0.50.2 port=5432 dbname=app; other=host=10.0.50.2 dbname=other'
render
contains "database entries on separate lines" /run/conf/pgbouncer.ini "other=host=10.0.50.2 dbname=other"

exit $fail
