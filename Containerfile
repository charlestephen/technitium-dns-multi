# Upstream versions. Bumped automatically by Renovate (see renovate.json).
# renovate: datasource=github-releases depName=TechnitiumSoftware/DnsServer extractVersion=^v(?<version>.*)$
ARG TECHNITIUM_VERSION=15.6.2
# renovate: datasource=github-releases depName=byGarcia/technitium-console extractVersion=^v(?<version>.*)$
ARG CONSOLE_VERSION=1.4.1
# Latest dnsdist release published by PowerDNS (container powerdns/dnsdist-21 and the repo.powerdns.com apt repository).
# renovate: datasource=docker depName=powerdns/dnsdist-21
ARG DNSDIST_VERSION=2.1.3
ARG DNSDIST_SERIES=21
# renovate: datasource=github-releases depName=acmesh-official/acme.sh
ARG ACMESH_VERSION=3.1.6

# The console image only carries a release tarball; it is unpacked below.
FROM ghcr.io/bygarcia/technitium-console:${CONSOLE_VERSION} AS console

FROM technitium/dns-server:${TECHNITIUM_VERSION}
ARG ACMESH_VERSION
ARG DNSDIST_VERSION
ARG DNSDIST_SERIES

ENV DEBIAN_FRONTEND=noninteractive

# dnsdist comes from PowerDNS's own repository: the Ubuntu package is 1.8.x, which has no DNS over QUIC.
# The signing key is pinned by checksum; a rotated key fails the build instead of being trusted blindly.
ARG POWERDNS_KEY_SHA256=59f44df793f0541b0b2f58548be88c270794550066d4e34c5ab382f5f1a0e305
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl \
    && install -d /etc/apt/keyrings \
    && curl -fsSL https://repo.powerdns.com/CBC8B383-pub.asc -o /etc/apt/keyrings/dnsdist-pub.asc \
    && echo "${POWERDNS_KEY_SHA256}  /etc/apt/keyrings/dnsdist-pub.asc" | sha256sum -c - \
    && . /etc/os-release \
    && echo "deb [signed-by=/etc/apt/keyrings/dnsdist-pub.asc] https://repo.powerdns.com/ubuntu ${VERSION_CODENAME}-dnsdist-${DNSDIST_SERIES} main" > /etc/apt/sources.list.d/pdns.list \
    && printf 'Package: dnsdist*\nPin: origin repo.powerdns.com\nPin-Priority: 600\n' > /etc/apt/preferences.d/dnsdist \
    && apt-get update && apt-get install -y --no-install-recommends \
        supervisor gettext-base openssl tar \
        "dnsdist=${DNSDIST_VERSION}-*" keepalived pgbouncer \
        kea-dhcp4-server kea-ctrl-agent \
    && rm -rf /var/lib/apt/lists/*

# Fail the build if a runtime requirement is missing: libmsquic (Technitium DoQ), dig (health check),
# and a dnsdist built with QUIC support (DoQ).
RUN dpkg-query -W libmsquic \
    && command -v dig >/dev/null \
    && dnsdist --version 2>&1 | tee /dev/stderr | grep -qi quic

# acme.sh, pinned. Config and certificates live in /var/lib/acme.sh (volume).
RUN curl -fsSL "https://github.com/acmesh-official/acme.sh/archive/refs/tags/${ACMESH_VERSION}.tar.gz" | tar -xz -C /tmp \
    && cd "/tmp/acme.sh-${ACMESH_VERSION}" \
    && ./acme.sh --install --home /opt/acme.sh --config-home /var/lib/acme.sh --nocron --noprofile \
    && rm -rf /tmp/acme.sh-*

# Alternative web console (flat tarball, served from DNS_SERVER_WEB_SERVICE_WWW_FOLDER_PATH).
COPY --from=console /usr/share/technitium-console/technitium-console.tar.gz /tmp/console.tgz
RUN mkdir -p /opt/technitium-console \
    && tar -xzf /tmp/console.tgz -C /opt/technitium-console \
    && rm /tmp/console.tgz

COPY rootfs/ /
RUN chmod +x /usr/local/bin/*.sh

# Service switches and defaults. Every value can be overridden with -e.
ENV ENABLE_TECHNITIUM=true \
    ENABLE_DNSDIST=true \
    ENABLE_KEEPALIVED=true \
    ENABLE_PGBOUNCER=false \
    ENABLE_KEA=false \
    ENABLE_ACME=false \
    DNS_SERVER_WEB_SERVICE_WWW_FOLDER_PATH=/opt/technitium-console \
    TECHNITIUM_DNS_LISTEN=127.0.0.1:5353 \
    TECHNITIUM_PROXY_PORT=538 \
    TECHNITIUM_PROXY_ACL=127.0.0.1 \
    DNSDIST_LISTEN=0.0.0.0:53 \
    DNSDIST_BACKENDS=127.0.0.1:538 \
    DNSDIST_BACKEND_PROXY_PROTOCOL=true \
    DNSDIST_TLS_CERT=/etc/dns/certs/fullchain.pem \
    DNSDIST_TLS_KEY=/etc/dns/certs/key.pem \
    DNSDIST_ENABLE_DOT=true \
    DNSDIST_ENABLE_DOH=true \
    DNSDIST_ENABLE_DOQ=true \
    DNSDIST_DOT_LISTEN=0.0.0.0:853 \
    DNSDIST_DOH_LISTEN=0.0.0.0:443 \
    DNSDIST_DOH_PATH=/dns-query \
    DNSDIST_DOQ_LISTEN=0.0.0.0:853 \
    DNSDIST_ACL=127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16 \
    DNSDIST_CACHE_ENTRIES=100000 \
    DNSDIST_MAX_QPS_PER_IP=0 \
    KEEPALIVED_INTERFACE=eth0 \
    KEEPALIVED_VIP=192.168.1.53/24 \
    KEEPALIVED_VRID=53 \
    KEEPALIVED_STATE=BACKUP \
    KEEPALIVED_PRIORITY=100 \
    KEEPALIVED_UNICAST_SRC= \
    KEEPALIVED_UNICAST_PEERS= \
    HEALTH_QUERY_NAME=localhost \
    PGBOUNCER_LISTEN_ADDR=0.0.0.0 \
    PGBOUNCER_LISTEN_PORT=6432 \
    PGBOUNCER_DATABASES= \
    PGBOUNCER_AUTH_FILE=/etc/pgbouncer/userlist.txt \
    PGBOUNCER_AUTH_TYPE=scram-sha-256 \
    PGBOUNCER_POOL_MODE=transaction \
    PGBOUNCER_MAX_CLIENT_CONN=1000 \
    PGBOUNCER_DEFAULT_POOL_SIZE=20 \
    KEA_INTERFACE=eth0 \
    KEA_SUBNET=192.168.1.0/24 \
    KEA_POOL="192.168.1.100 - 192.168.1.199" \
    KEA_ROUTERS=192.168.1.1 \
    KEA_DNS_SERVERS=192.168.1.53 \
    KEA_DOMAIN=local \
    KEA_LEASE_SECONDS=3600 \
    KEA_HA_ROLE=primary \
    KEA_HA_PRIMARY_ADDR=192.168.1.10 \
    KEA_HA_SECONDARY_ADDR=192.168.1.11 \
    KEA_CTRL_BIND=0.0.0.0 \
    KEA_CTRL_PORT=8000 \
    ACME_EMAIL= \
    ACME_DOMAINS= \
    ACME_DNS_PROVIDER= \
    ACME_SERVER=letsencrypt \
    ACME_PFX_PASSWORD=

# DNS, DHCP, DoT/DoQ, DoH, web console (HTTP/HTTPS), PgBouncer, Kea control agent
EXPOSE 53/udp 53/tcp 67/udp 443/tcp 443/udp 853/tcp 853/udp 5380/tcp 53443/tcp 6432/tcp 8000/tcp

VOLUME ["/etc/dns", "/var/lib/acme.sh", "/var/lib/kea"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD /usr/local/bin/healthcheck.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
