# technitium-dns-multi

One container that bundles a highly available DNS stack around [Technitium DNS Server](https://technitium.com/dns/):

| Component | Role |
|---|---|
| Technitium DNS Server | Authoritative and recursive DNS, web console |
| [Technitium Console](https://github.com/byGarcia/technitium-console) | Alternative web UI |
| [dnsdist](https://dnsdist.org/) | Front end for plain DNS, DNS over TLS, DNS over HTTPS and DNS over QUIC, with caching, ACLs and rate limits |
| [keepalived](https://www.keepalived.org/) | VRRP virtual IP that fails over when the local DNS path stops answering |
| [acme.sh](https://github.com/acmesh-official/acme.sh) | Optional DNS-01 certificate issue and renewal |
| [PgBouncer](https://www.pgbouncer.org/) | Optional PostgreSQL connection pooler |

Each component is switched on or off with an `ENABLE_*` variable, and all configuration comes from environment variables. Images are published for `linux/amd64` and `linux/arm64`.

- Source and full variable reference: https://github.com/charlestephen/technitium-dns-multi
- Issues: https://github.com/charlestephen/technitium-dns-multi/issues
- Also published at `ghcr.io/charlestephen/technitium-dns-multi`

## Tags

| Tag | Meaning |
|---|---|
| `vYYYY.MM.DD` | A dated release, for example `v2026.11.13`. Month and day are zero-padded. A release is cut when a bundled application's version changes. A second release on the same day gets a counter, such as `v2026.11.13.2`. Releases before 2026-11-13 used unpadded dates, such as `v2026.11.9`. |
| `latest` | Most recent build of `main`. |
| `technitium-<version>` | Latest build that bundles that Technitium version, for example `technitium-15.6.2`. |
| `sha-<commit>` | The image built from that commit. |

Pin a dated release tag for reproducible deployments. `latest` and `technitium-<version>` move with each build.

## How it works

```
                         ┌─ 53  UDP/TCP  plain DNS
client ─► VIP ─► dnsdist ├─ 853 TCP      DNS over TLS   ─┐
 (keepalived)            ├─ 853 UDP      DNS over QUIC  ─┼─► Technitium 127.0.0.1:538 (PROXY protocol)
                         └─ 443 TCP      DNS over HTTPS ─┘
```

dnsdist terminates all client-facing DNS protocols and forwards queries to Technitium on the loopback interface using the PROXY protocol, so Technitium's logs, ACLs and per-client blocking see the real client address.

On start the container logs in to the Technitium API to apply its listen address and PROXY settings, and turns off Technitium's own DoT, DoH and DoQ listeners so they don't collide with dnsdist. This needs `DNS_SERVER_ADMIN_PASSWORD` or `DNS_SERVER_ADMIN_PASSWORD_FILE` to stay set.

Run several nodes with the same `KEEPALIVED_VIP` and `KEEPALIVED_VRID` and different `KEEPALIVED_PRIORITY`. The node with the highest priority that is healthy holds the virtual IP.

## Requirements

- **Capabilities:** `NET_ADMIN` (keepalived adds the virtual IP), `NET_RAW` (VRRP raw sockets) and `NET_BIND_SERVICE` (ports below 1024).
- **Networking:** VRRP needs layer 2 access to your LAN, so use a macvlan network or host networking. A plain bridge network works for trying it out, but the virtual IP won't be reachable from the LAN.
- **Volumes:** keep `/etc/dns` (Technitium state and certificates) and `/var/lib/acme.sh` on volumes.

## Quick start with Docker Compose

Save this as `compose.yml`:

```yaml
services:
  dns:
    image: charlestephen/technitium-dns-multi:latest
    container_name: technitium-dns-multi
    hostname: technitium-dns-multi
    restart: unless-stopped
    cap_add: [NET_ADMIN, NET_RAW, NET_BIND_SERVICE]
    env_file: .env
    networks:
      lan:
        ipv4_address: ${NODE_IP}
    volumes:
      - dns-config:/etc/dns
      - acme:/var/lib/acme.sh

networks:
  lan:
    driver: macvlan
    driver_opts:
      parent: ${LAN_PARENT_INTERFACE:-eth0}
    ipam:
      config:
        - subnet: ${LAN_SUBNET}
          gateway: ${LAN_GATEWAY}

volumes:
  dns-config:
  acme:
```

Create `.env` next to it. Every value below is a placeholder you must replace with your own:

```ini
# Network the container joins (your LAN)
LAN_PARENT_INTERFACE=eth0
LAN_SUBNET=192.168.1.0/24
LAN_GATEWAY=192.168.1.1
NODE_IP=192.168.1.51

# Technitium web console admin password
DNS_SERVER_ADMIN_PASSWORD=change-me

# Virtual IP shared by all nodes (same VRID everywhere, different priority)
KEEPALIVED_INTERFACE=eth0
KEEPALIVED_VIP=192.168.1.53/24
KEEPALIVED_VRID=53
KEEPALIVED_PRIORITY=100
```

Then start it:

```bash
docker compose up -d
docker compose logs -f
```

To update:

```bash
docker compose pull && docker compose up -d
```

With macvlan, the Docker host itself can't reach the container's address. Test from another machine on the LAN.

### Docker run

```bash
docker network create -d macvlan \
  --subnet 192.168.1.0/24 --gateway 192.168.1.1 \
  -o parent=eth0 lan

docker run -d --name technitium-dns-multi --hostname technitium-dns-multi \
  --restart unless-stopped \
  --network lan --ip 192.168.1.51 \
  --cap-add NET_ADMIN --cap-add NET_RAW --cap-add NET_BIND_SERVICE \
  --env-file .env \
  -v dns-config:/etc/dns \
  -v acme:/var/lib/acme.sh \
  charlestephen/technitium-dns-multi:latest
```

Replace the subnet, gateway, parent interface and `--ip` with values for your network. Without macvlan you can use `--network host` and drop `--ip`. keepalived then manages the virtual IP on the host's interface.

## Trying it without macvlan

For a quick local test, run it on a bridge network with keepalived off and the ports published:

```bash
docker run -d --name dns-test \
  --cap-add NET_BIND_SERVICE \
  -e ENABLE_KEEPALIVED=false \
  -e DNS_SERVER_ADMIN_PASSWORD=change-me \
  -p 5380:5380 -p 5353:53/udp -p 5353:53/tcp \
  charlestephen/technitium-dns-multi:latest

dig @127.0.0.1 -p 5353 example.com
```

Then open `http://localhost:5380/` and sign in as `admin`.

## Ports

| Port | Use |
|---|---|
| 53 UDP/TCP | Plain DNS (dnsdist) |
| 853 TCP | DNS over TLS |
| 853 UDP | DNS over QUIC |
| 443 TCP | DNS over HTTPS (path `/dns-query`) |
| 5380 TCP | Technitium web console (HTTP) |
| 53443 TCP | Technitium web console (HTTPS, when enabled) |
| 6432 TCP | PgBouncer (when enabled) |
| 8083 TCP | dnsdist dashboard (when a password is set) |

## Common variables

The full list, with defaults, is in the [GitHub README](https://github.com/charlestephen/technitium-dns-multi#variables).

| Variable | Default | Description |
|---|---|---|
| `ENABLE_TECHNITIUM` | `true` | Run Technitium DNS Server. |
| `ENABLE_DNSDIST` | `true` | Run dnsdist in front of Technitium. |
| `ENABLE_KEEPALIVED` | `true` | Run keepalived and manage the virtual IP. |
| `ENABLE_PGBOUNCER` | `false` | Run PgBouncer. |
| `ENABLE_ACME` | `false` | Run acme.sh certificate issue and renewal. |
| `DNS_SERVER_ADMIN_PASSWORD` | none | Technitium admin password. `DNS_SERVER_ADMIN_PASSWORD_FILE` reads it from a file. |
| `DNSDIST_ACL` | private ranges | Networks allowed to query. Add your global IPv6 prefix if clients use one. |
| `DNSDIST_CACHE_ENTRIES` | `0` | Packet cache size. `0` disables it. |
| `DNSDIST_WEB_PASSWORD` | empty | Enables the dnsdist dashboard on port 8083 when set. |
| `KEEPALIVED_VIP` | `192.168.1.53/24` | Virtual IP with prefix length. Comma separate to mix IPv4 and IPv6. |
| `KEEPALIVED_UNICAST_PEERS` | empty | Peer addresses for unicast VRRP. Empty uses multicast. |
| `HEALTH_QUERY_NAME` | `localhost` | Name used by health checks. It must be answered without going to the internet. |

Technitium's own `DNS_SERVER_*` variables are also passed through. Upstream only reads them on first start, when `/etc/dns` is empty.

## Certificates

dnsdist needs a PEM certificate chain and key for DoT, DoH and DoQ. Without them it logs a message and serves plain DNS only.

- **Your own certificate:** mount the files at `/etc/dns/certs/fullchain.pem` and `/etc/dns/certs/key.pem`, then restart the container.
- **acme.sh:** set `ENABLE_ACME=true`, `ACME_DOMAINS`, `ACME_DNS_PROVIDER` and your DNS provider's credential variables (for example `CF_Token`). Only the DNS-01 challenge is supported. Renewals are checked every 12 hours and briefly restart dnsdist.

## Health and logs

The image has a built-in health check:

```bash
docker ps --filter name=technitium-dns-multi --format '{{.Status}}'
docker logs -f technitium-dns-multi
docker exec technitium-dns-multi supervisorctl status
```

## License

See https://github.com/charlestephen/technitium-dns-multi/blob/main/LICENSE
