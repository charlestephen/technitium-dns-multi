# technitium-dns-ha

A single container that bundles a highly available DNS stack around
[Technitium DNS Server](https://technitium.com/dns/):

| Component | Role |
|---|---|
| Technitium DNS Server | Authoritative and recursive DNS, DHCP, web console |
| [Technitium Console](https://github.com/byGarcia/technitium-console) | Alternative web UI (served from Technitium's web folder) |
| dnsdist | Listens on port 53, caches, applies ACL/rate limits, load balances across backends |
| keepalived | VRRP virtual IP that fails over when the local DNS path stops answering |
| PgBouncer | Optional PostgreSQL connection pooler |
| Kea DHCPv4 | Optional DHCP with HA load balancing between two nodes |

Each component is switched on or off with an `ENABLE_*` variable. All configuration comes from environment
variables; config files are rendered from templates at start.

Images: `ghcr.io/<owner>/technitium-dns-ha` and `docker.io/<owner>/technitium-dns-ha` (`linux/amd64`, `linux/arm64`).

## How it fits together

```
client ──► VIP (keepalived) ──► dnsdist :53 ──► Technitium 127.0.0.1:5353
```

Technitium has no environment variable for its DNS listen address, so on start the container logs in to the
Technitium API and sets `TECHNITIUM_DNS_LISTEN` (default `127.0.0.1:5353`). This needs `DNS_SERVER_ADMIN_PASSWORD`.
Until that has happened on first boot, dnsdist cannot bind port 53 and is restarted by supervisord.

Run two nodes with the same `KEEPALIVED_VIP` and `KEEPALIVED_VRID` and different `KEEPALIVED_PRIORITY`.

## Quick start

```sh
cp .env.example .env      # edit; set at least NODE_IP, LAN_SUBNET, LAN_GATEWAY, DNS_SERVER_ADMIN_PASSWORD
docker compose up -d      # or: podman compose up -d
```

### `podman run` (rootful; macvlan needs root)

```sh
sudo podman network create -d macvlan \
  --subnet "$LAN_SUBNET" --gateway "$LAN_GATEWAY" -o parent="$LAN_PARENT_INTERFACE" lan

sudo podman run -d --name technitium-ha --hostname technitium-ha \
  --restart unless-stopped \
  --network lan --ip "$NODE_IP" \
  --cap-add NET_ADMIN --cap-add NET_RAW --cap-add NET_BIND_SERVICE \
  --env-file .env \
  -v dns-config:/etc/dns \
  -v kea:/var/lib/kea \
  ghcr.io/<owner>/technitium-dns-ha:latest
```

`docker run` accepts the same flags (`docker network create -d macvlan …`). Without macvlan, use `--network host`
and drop `--ip`; keepalived then manages the VIP on the host's interface.

## Variables

See [.env.example](.env.example) for every variable with its default. Technitium's own variables
(`DNS_SERVER_*`) are documented in its
[DockerEnvironmentVariables.md](https://github.com/TechnitiumSoftware/DnsServer/blob/master/DockerEnvironmentVariables.md).

Config templates are in `rootfs/usr/local/share/templates`. Mount a directory over it to replace them.

## Certificates

The image does not issue certificates. Mount your own PKCS#12 file (for example at `/etc/dns/certs/technitium.pfx`)
and point Technitium at it with `DNS_SERVER_WEB_SERVICE_ENABLE_HTTPS=true`,
`DNS_SERVER_WEB_SERVICE_TLS_CERTIFICATE_PATH` and `DNS_SERVER_WEB_SERVICE_TLS_CERTIFICATE_PASSWORD`. For DoT/DoH set
the certificate path in the DNS settings.

## PgBouncer

Set `ENABLE_PGBOUNCER=true`, `PGBOUNCER_DATABASES` (the body of the `[databases]` section) and mount a `userlist.txt`
at `PGBOUNCER_AUTH_FILE`.

## Kea DHCP (HA load balancing)

Technitium's DHCP server cannot fail over, so for redundant DHCP enable Kea and leave Technitium's DHCP scopes
disabled (both would answer on UDP 67).

- Run one node with `KEA_HA_ROLE=primary` and the other with `KEA_HA_ROLE=secondary`; set `KEA_HA_PRIMARY_ADDR`
  and `KEA_HA_SECONDARY_ADDR` to the nodes' addresses.
- In `load-balancing` mode each node answers about half of the clients and takes over the other half when its peer
  stops responding. Leases are replicated between the nodes over the Kea control agent (`KEA_CTRL_PORT`).
- The control agent API is unauthenticated. Restrict TCP `KEA_CTRL_PORT` to the peer node and set `KEA_CTRL_BIND`.
- DHCP needs layer 2 access: use macvlan or host networking, not a bridged published-port setup.
- Kea shipped in Ubuntu 24.04 is 2.4.x.

## Build

```sh
podman build -f Containerfile -t technitium-dns-ha .
```

Upstream versions are build arguments: `TECHNITIUM_VERSION`, `CONSOLE_VERSION`.

## CI

- `build.yml`: multi-arch build, push to GHCR and Docker Hub, SBOM and provenance, Trivy image scan to code scanning.
  Runs on push to `main`, on `v*` tags, weekly (to pick up distro security updates) and on demand.
- `security.yml`: hadolint, shellcheck and a Trivy repository scan (secrets, misconfiguration, vulnerabilities) daily.
- `renovate.json`: Renovate raises and auto-merges pull requests for new Technitium and Technitium Console
  releases and for GitHub Action updates (pinned by commit SHA). A merge to `main` triggers `build.yml`.

Required repository settings: variable `DOCKERHUB_USERNAME`, secret `DOCKERHUB_TOKEN`, the Renovate GitHub App
installed on the repository, and branch protection that requires the `build` and `security` checks if auto-merge
should wait for them.

## License

See the licenses of the bundled components. This repository's own files are provided as-is.
