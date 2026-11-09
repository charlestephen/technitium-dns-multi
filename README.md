# technitium-dns-multi

A single container that bundles a highly available DNS stack around
[Technitium DNS Server](https://technitium.com/dns/) ([source](https://github.com/TechnitiumSoftware/DnsServer)):

| Component | Role |
|---|---|
| [Technitium DNS Server](https://technitium.com/dns/) | Authoritative and recursive DNS, DHCP, web console |
| [Technitium Console](https://github.com/byGarcia/technitium-console) | Alternative web UI (served from Technitium's web folder) |
| [dnsdist](https://dnsdist.org/) | Listens on port 53, caches, applies ACL/rate limits, load balances across backends |
| [keepalived](https://www.keepalived.org/) | VRRP virtual IP that fails over when the local DNS path stops answering |
| [acme.sh](https://github.com/acmesh-official/acme.sh) | Optional DNS-01 certificate issue and renewal, published as a PKCS#12 file |
| [PgBouncer](https://www.pgbouncer.org/) | Optional PostgreSQL connection pooler |
| [Kea DHCPv4](https://www.isc.org/kea/) | Optional DHCP with HA load balancing between two nodes |

Each component is switched on or off with an `ENABLE_*` variable. All configuration comes from environment
variables; config files are rendered from templates at start.

Images: [`ghcr.io/charlestephen/technitium-dns-multi`](https://github.com/charlestephen/technitium-dns-multi/pkgs/container/technitium-dns-multi) and [`docker.io/charlestephen/technitium-dns-multi`](https://hub.docker.com/r/charlestephen/technitium-dns-multi) (`linux/amd64`, `linux/arm64`).

## How it fits together

```
client ──► VIP (keepalived) ──► dnsdist :53 ──► Technitium 127.0.0.1:5353
```

Technitium has no environment variable for its DNS listen address, so on start the container logs in to the
Technitium API and sets `TECHNITIUM_DNS_LISTEN` (default `127.0.0.1:5353`). This needs `DNS_SERVER_ADMIN_PASSWORD`.
Until that has happened on first boot, dnsdist cannot bind port 53 and is restarted by supervisord.

Run multiple nodes with the same `KEEPALIVED_VIP` and `KEEPALIVED_VRID` and different `KEEPALIVED_PRIORITY`.

## Quick start

```sh
cp .env.example .env      # edit; set at least NODE_IP, LAN_SUBNET, LAN_GATEWAY, DNS_SERVER_ADMIN_PASSWORD
docker compose up -d      # or: podman compose up -d
```

### `podman run` (rootful; macvlan needs root)

```sh
sudo podman network create -d macvlan \
  --subnet "$LAN_SUBNET" --gateway "$LAN_GATEWAY" -o parent="$LAN_PARENT_INTERFACE" lan

sudo podman run -d --name technitium-dns-multi --hostname technitium-dns-multi \
  --restart unless-stopped \
  --network lan --ip "$NODE_IP" \
  --cap-add NET_ADMIN --cap-add NET_RAW --cap-add NET_BIND_SERVICE \
  --env-file .env \
  -v dns-config:/etc/dns \
  -v acme:/var/lib/acme.sh \
  -v kea:/var/lib/kea \
  ghcr.io/charlestephen/technitium-dns-multi:latest
```

`docker run` accepts the same flags (`docker network create -d macvlan …`). Without macvlan, use `--network host`
and drop `--ip`; keepalived then manages the VIP on the host's interface.

## Variables

Set variables with `--env-file .env` or `-e`. [.env.example](.env.example) lists them with example values.

### Compose and network (used by `compose.yml`, not read inside the container)

| Variable | Default | Description |
|---|---|---|
| `IMAGE` | `ghcr.io/charlestephen/technitium-dns-multi:latest` | Image to run. |
| `CONTAINER_NAME` | `technitium-dns-multi` | Container name. |
| `CONTAINER_HOSTNAME` | `technitium-dns-multi` | Container hostname. |
| `LAN_PARENT_INTERFACE` | `eth0` | Host interface the macvlan network attaches to. |
| `LAN_SUBNET` | required | Subnet of the macvlan network, for example `192.168.1.0/24`. |
| `LAN_GATEWAY` | required | Gateway of the macvlan network. |
| `NODE_IP` | required | This node's own address on the macvlan network. |

### Service switches

| Variable | Default | Description |
|---|---|---|
| `ENABLE_TECHNITIUM` | `true` | Run Technitium DNS Server. |
| `ENABLE_DNSDIST` | `true` | Run dnsdist in front of Technitium. When `true`, Technitium is moved to `TECHNITIUM_DNS_LISTEN`. |
| `ENABLE_KEEPALIVED` | `true` | Run keepalived and manage the virtual IP. |
| `ENABLE_PGBOUNCER` | `false` | Run PgBouncer. |
| `ENABLE_KEA` | `false` | Run Kea DHCPv4 and the Kea control agent. |
| `ENABLE_ACME` | `false` | Run acme.sh certificate issue and renewal. |

### Technitium (image settings)

| Variable | Default | Description |
|---|---|---|
| `TECHNITIUM_DNS_LISTEN` | `127.0.0.1:5353` | Address and port Technitium listens on for DNS when `ENABLE_DNSDIST=true`. Applied through the Technitium API; needs `DNS_SERVER_ADMIN_PASSWORD` or `DNS_SERVER_ADMIN_PASSWORD_FILE`. |
| `DNS_SERVER_WEB_SERVICE_WWW_FOLDER_PATH` | `/opt/technitium-console` | Folder Technitium serves as its web console. The default is the bundled Technitium Console; point it at another folder to serve a different console. |

### Technitium (upstream variables)

These are passed straight to Technitium. Upstream reads them [only when the DNS config file does not exist](https://github.com/TechnitiumSoftware/DnsServer/blob/master/DockerEnvironmentVariables.md), that is on first start with an empty `/etc/dns`. Descriptions are from upstream.

| Variable | Type | Description |
|---|---|---|
| `DNS_SERVER_DOMAIN` | String | The primary fully qualified domain name used by this DNS Server to identify itself. |
| `DNS_SERVER_ADMIN_PASSWORD` | String | The DNS web console admin user password. |
| `DNS_SERVER_ADMIN_PASSWORD_FILE` | String | The path to a file that contains a plain text password for the DNS web console admin user. |
| `DNS_SERVER_PREFER_IPV6` | Boolean | DNS Server will use IPv6 for querying whenever possible with this option enabled. |
| `DNS_SERVER_WEB_SERVICE_LOCAL_ADDRESSES` | String | A comma separated list of IP addresses for the DNS web console to listen on. |
| `DNS_SERVER_WEB_SERVICE_HTTP_PORT` | Integer | The TCP port number for the DNS web console over HTTP protocol. |
| `DNS_SERVER_WEB_SERVICE_HTTPS_PORT` | Integer | The TCP port number for the DNS web console over HTTPS protocol. |
| `DNS_SERVER_WEB_SERVICE_ENABLE_HTTPS` | Boolean | Enables HTTPS for the DNS web console. |
| `DNS_SERVER_WEB_SERVICE_USE_SELF_SIGNED_CERT` | Boolean | Enables self signed TLS certificate for the DNS web console. |
| `DNS_SERVER_WEB_SERVICE_TLS_CERTIFICATE_PATH` | String | The file path to the TLS certificate for the DNS web console. |
| `DNS_SERVER_WEB_SERVICE_TLS_CERTIFICATE_PASSWORD` | String | The password for the TLS certificate for the DNS web console. |
| `DNS_SERVER_WEB_SERVICE_HTTP_TO_TLS_REDIRECT` | Boolean | Enables HTTP to HTTPS redirection for the DNS web console. |
| `DNS_SERVER_WEB_SERVICE_REVERSE_PROXY_ADDRESSES` | String | A comma separated list of IP addresses or network addresses to define allowed reverse proxy servers. Add ! character at the start to deny, e.g. !192.168.10.0/24 will deny entire subnet. The ACL is processed in the same order its listed. If no networks match, the default policy is to deny all. |
| `DNS_SERVER_OPTIONAL_PROTOCOL_DNS_OVER_HTTP` | Boolean | Enables DNS server optional protocol DNS-over-HTTP on TCP port 80 to be used with a TLS terminating reverse proxy like nginx. |
| `DNS_SERVER_RECURSION` | String | Recursion options: `Allow`, `Deny`, `AllowOnlyForPrivateNetworks`, `UseSpecifiedNetworkACL`. |
| `DNS_SERVER_RECURSION_NETWORK_ACL` | String | A comma separated list of IP addresses or network addresses to allow access. Add ! character at the start to deny access, e.g. !192.168.10.0/24 will deny entire subnet. The ACL is processed in the same order its listed. If no networks match, the default policy is to deny all except loopback. Valid only for `UseSpecifiedNetworkACL` recursion option. |
| `DNS_SERVER_RECURSION_DENIED_NETWORKS` | String | A comma separated list of IP addresses or network addresses to deny recursion. Valid only for `UseSpecifiedNetworkACL` recursion option. This option is obsolete and DNS_SERVER_RECURSION_NETWORK_ACL should be used instead. |
| `DNS_SERVER_RECURSION_ALLOWED_NETWORKS` | String | A comma separated list of IP addresses or network addresses to allow recursion. Valid only for `UseSpecifiedNetworkACL` recursion option. This option is obsolete and DNS_SERVER_RECURSION_NETWORK_ACL should be used instead. |
| `DNS_SERVER_ENABLE_BLOCKING` | Boolean | Sets the DNS server to block domain names using Blocked Zone and Block List Zone. |
| `DNS_SERVER_ALLOW_TXT_BLOCKING_REPORT` | Boolean | Specifies if the DNS Server should respond with TXT records containing a blocked domain report for TXT type requests. |
| `DNS_SERVER_BLOCK_LIST_URLS` | String | A comma separated list of block list URLs. |
| `DNS_SERVER_FORWARDERS` | String | A comma separated list of forwarder addresses. |
| `DNS_SERVER_FORWARDER_PROTOCOL` | String | Forwarder protocol options: `Udp`, `Tcp`, `Tls`, `Https`, `Quic`. |
| `DNS_SERVER_LOG_USING_LOCAL_TIME` | Boolean | Enable this option to use local time instead of UTC for logging. |
| `DNS_SERVER_LOG_FOLDER_PATH` | String | The folder path on the server where the log files should be saved. The path can be relative to the DNS server's config folder. |
| `DNS_SERVER_LOG_MAX_LOG_FILE_DAYS` | Integer | Max number of days to keep the log files. Log files older than the specified number of days will be deleted automatically. Set 0 to disable auto delete. |
| `DNS_SERVER_STATS_ENABLE_IN_MEMORY_STATS` | Boolean | This option will enable in-memory stats and only Last Hour data will be available on Dashboard. No stats data will be stored on disk. |
| `DNS_SERVER_STATS_MAX_STAT_FILE_DAYS` | Integer | Max number of days to keep the dashboard stats. Stat files older than the specified number of days will be deleted automatically. Set 0 to disable auto delete. |
| `DNS_SERVER_SSO_ENABLED` | Boolean | Enable to allow Single Sign-On (SSO) with OpenID Connect (OIDC). |
| `DNS_SERVER_SSO_AUTHORITY` | String | The OpenID Connect (OIDC) Authority URL (Issuer). |
| `DNS_SERVER_SSO_CLIENT_ID` | String | The OpenID Connect (OIDC) Client ID. |
| `DNS_SERVER_SSO_CLIENT_SECRET` | String | The OpenID Connect (OIDC) Client Secret. |
| `DNS_SERVER_SSO_CLIENT_SECRET_FILE` | String | The path to a file that contains a plain text OpenID Connect (OIDC) Client Secret string. |
| `DNS_SERVER_SSO_METADATA_ADDRESS` | String | The OpenID Connect (OIDC) metadata discovery URL to be used instead of the default one. Configure this option only if the Single Sign-On (SSO) provider uses a different discovery URL. |
| `DNS_SERVER_SSO_SCOPES` | String | A comma separated list of OpenID Connect (OIDC) Scopes. For example, `openid,profile,email`. The scopes `openid` and `profile` are mandatory and will be automatically added if missing. Add the scope `email` if you want to use email address as the username for all SSO users that sign up for an account. |
| `DNS_SERVER_SSO_ALLOW_SIGNUP` | Boolean | Enable to allow automatically provisioning of user accounts for new users signing in via Single Sign-On (SSO). Keep this option disabled if you do not expect new SSO users to sign up. |
| `DNS_SERVER_SSO_ALLOW_SIGNUP_ONLY_FOR_MAPPED_USERS` | Boolean | Enable to allow a new user to sign up via Single Sign-On (SSO) only when the user is a member of at least one Remote Group that is mapped to a Local Group in the Group Map option below. This option allows SSO administrators to restrict SSO users to control who can sign up and get access based on their group memberships. |
| `DNS_SERVER_SSO_GROUP_MAP` | String | A comma separated list of entries where each entry is a colon separated key value pair. For example, `Admins:Administrators,DNS Admins:DNS Administrators`. Map Remote Groups at Single Sign-On (SSO) provider to Local Groups for both new and existing users signed up via Single Sign-On (SSO). These SSO user's group membership will be automatically synced to mapped Local Groups each time they log in. |
| `DNS_SERVER_LDAP_ENABLED` | Boolean | Enable to allow users from an LDAP directory (Active Directory, OpenLDAP, etc.) to log in using their directory credentials. |
| `DNS_SERVER_LDAP_SERVER` | String | Domain name or IP address of the LDAP server. |
| `DNS_SERVER_LDAP_PORT` | Integer | The port number for the LDAP service. Use default 389 for plain LDAP/StartTLS or default 636 for LDAPS. |
| `DNS_SERVER_LDAP_SSL_OPTION` | String | The SSL/TLS option to use to connect to LDAP service. Valid options are: `None`, `StartTLS`, `LDAPS`. |
| `DNS_SERVER_LDAP_IGNORE_SSL_ERRORS` | Boolean | Enable to ignore SSL/TLS certificate errors. Warning! The Ignore SSL Certificate Errors option is not secure and should be used only for testing purposes. |
| `DNS_SERVER_LDAP_BIND_USERNAME` | String | The Distinguished Name (DN) or User Principal Name (UPN) of a service account used to search the directory. Leave empty for anonymous bind. |
| `DNS_SERVER_LDAP_BIND_PASSWORD` | String | The password for the above bind service account. |
| `DNS_SERVER_LDAP_BIND_PASSWORD_FILE` | String | The path to a file that contains a plain text password for the bind service account string. |
| `DNS_SERVER_LDAP_SEARCH_BASE` | String | The base Distinguished Name (DN) used to search for user entries. |
| `DNS_SERVER_LDAP_USER_SEARCH_FILTER` | String | The LDAP search filter used to find the user. Use `{0}` as a placeholder for the username. Use default `(sAMAccountName={0})` for Active Directory and `(uid={0})` for OpenLDAP. Use `(userPrincipalName={0})` if usernames in the directory are stored under 'userPrincipalName' attribute. |
| `DNS_SERVER_LDAP_GROUP_ATTRIBUTE` | String | The user attribute listing group memberships. Use default `memberOf` for Active Directory. |
| `DNS_SERVER_LDAP_ALLOW_SIGNUP` | Boolean | Enable to allow automatically provisioning of user accounts for new users signing in via LDAP. Keep this option disabled if you do not expect new LDAP users to sign up. |
| `DNS_SERVER_LDAP_ALLOW_SIGNUP_ONLY_FOR_MAPPED_USERS` | String | Enable to allow a new user to sign up via LDAP only when the user is a member of at least one Remote Group that is mapped to a Local Group in the Group Map option below. This option allows LDAP administrators to restrict LDAP users to control who can sign up and get access based on their group memberships. |
| `DNS_SERVER_LDAP_GROUP_MAP` | String | A comma separated list of entries where each entry is a colon separated key value pair. For example, `Administrators:Administrators,DNS Admins:DNS Administrators`. Map Remote Groups at directory service to Local Groups for both new and existing users signed up via LDAP. These LDAP user's group membership will be automatically synced to mapped Local Groups each time they log in. |

### dnsdist

| Variable | Default | Description |
|---|---|---|
| `DNSDIST_LISTEN` | `0.0.0.0:53` | Address and port dnsdist listens on. |
| `DNSDIST_BACKENDS` | `127.0.0.1:5353` | Comma separated `address:port` list of backend DNS servers. |
| `DNSDIST_ACL` | `127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16` | Comma separated networks allowed to query. |
| `DNSDIST_CACHE_ENTRIES` | `100000` | Packet cache size in entries. |
| `DNSDIST_MAX_QPS_PER_IP` | `0` | Queries per second allowed per client address; `0` disables the limit. |

### keepalived

| Variable | Default | Description |
|---|---|---|
| `KEEPALIVED_INTERFACE` | `eth0` | Interface that carries VRRP and the virtual IP. |
| `KEEPALIVED_VIP` | `192.168.1.53/24` | Virtual IP address with prefix length. |
| `KEEPALIVED_VRID` | `53` | VRRP virtual router ID. Same on every node, unique on the LAN. |
| `KEEPALIVED_STATE` | `BACKUP` | Initial VRRP state (`MASTER` or `BACKUP`). |
| `KEEPALIVED_PRIORITY` | `100` | VRRP priority; the highest healthy node holds the virtual IP. |
| `KEEPALIVED_UNICAST_SRC` | empty | This node's address for unicast VRRP. Empty uses multicast. |
| `KEEPALIVED_UNICAST_PEERS` | empty | Comma separated peer addresses for unicast VRRP. |
| `HEALTH_QUERY_NAME` | `localhost` | Name queried every 2 seconds to check that DNS answers. Also used by the container health check. |

### PgBouncer

| Variable | Default | Description |
|---|---|---|
| `PGBOUNCER_DATABASES` | empty | Database entries (`name = connection parameters`) separated by `;`. See [PgBouncer](#pgbouncer). |
| `PGBOUNCER_LISTEN_ADDR` | `0.0.0.0` | Address PgBouncer listens on. |
| `PGBOUNCER_LISTEN_PORT` | `6432` | Port PgBouncer listens on. |
| `PGBOUNCER_AUTH_TYPE` | `scram-sha-256` | PgBouncer `auth_type`. |
| `PGBOUNCER_AUTH_FILE` | `/etc/pgbouncer/userlist.txt` | Path of the user list file. Mount it into the container. |
| `PGBOUNCER_POOL_MODE` | `transaction` | PgBouncer `pool_mode`: `session`, `transaction` or `statement`. |
| `PGBOUNCER_MAX_CLIENT_CONN` | `1000` | Maximum client connections. |
| `PGBOUNCER_DEFAULT_POOL_SIZE` | `20` | Server connections per user/database pair. |

### acme.sh

| Variable | Default | Description |
|---|---|---|
| `ACME_DOMAINS` | empty | Comma separated domain names. The first is the certificate name. Required when `ENABLE_ACME=true`. |
| `ACME_DNS_PROVIDER` | empty | acme.sh [`dnsapi`](https://github.com/acmesh-official/acme.sh/wiki/dnsapi) name, for example `dns_cf`. Required when `ENABLE_ACME=true`. The provider's own credential variables (for example `CF_Token`) are read by acme.sh from the environment. |
| `ACME_EMAIL` | empty | Account email address. |
| `ACME_SERVER` | `letsencrypt` | ACME CA name or directory URL. |
| `ACME_PFX_PASSWORD` | empty | Password for the generated PKCS#12 file. |

### Kea DHCPv4

| Variable | Default | Description |
|---|---|---|
| `KEA_INTERFACE` | `eth0` | Interface Kea serves DHCP on. |
| `KEA_SUBNET` | `192.168.1.0/24` | Subnet served. |
| `KEA_POOL` | `192.168.1.100 - 192.168.1.199` | Address pool. |
| `KEA_ROUTERS` | `192.168.1.1` | Default gateway handed to clients. |
| `KEA_DNS_SERVERS` | `192.168.1.53` | DNS servers handed to clients; normally the keepalived virtual IP. |
| `KEA_DOMAIN` | `local` | Domain name handed to clients. |
| `KEA_LEASE_SECONDS` | `3600` | Lease lifetime in seconds. |
| `KEA_HA_ROLE` | `primary` | `primary` on one node, `secondary` on the other. |
| `KEA_HA_PRIMARY_ADDR` | `192.168.1.10` | Address of the primary node's control agent. |
| `KEA_HA_SECONDARY_ADDR` | `192.168.1.11` | Address of the secondary node's control agent. |
| `KEA_CTRL_BIND` | `0.0.0.0` | Address the Kea control agent listens on. |
| `KEA_CTRL_PORT` | `8000` | Port the Kea control agent listens on. |

Config templates are in `rootfs/usr/local/share/templates`. Mount a directory over it to replace them.

## Certificates

Either supply your own certificate or let the container obtain one with [acme.sh](https://github.com/acmesh-official/acme.sh).

**Your own:** mount a PKCS#12 file (for example at `/etc/dns/certs/technitium.pfx`).

**acme.sh:** set `ENABLE_ACME=true`, `ACME_DOMAINS`, `ACME_DNS_PROVIDER` and that provider's credential variables
(for example `CF_Token`). Issuance uses the DNS-01 challenge. The certificate is written to
`/etc/dns/certs/technitium.pfx`, protected by `ACME_PFX_PASSWORD`, and renewal is checked every 12 hours.
Keep `/var/lib/acme.sh` on a volume so the account and certificates survive restarts.

Either way, point Technitium at the file with `DNS_SERVER_WEB_SERVICE_ENABLE_HTTPS=true`,
`DNS_SERVER_WEB_SERVICE_TLS_CERTIFICATE_PATH` and `DNS_SERVER_WEB_SERVICE_TLS_CERTIFICATE_PASSWORD`. For DoT/DoH set
the certificate path in the DNS settings.

## PgBouncer

Set `ENABLE_PGBOUNCER=true`, `PGBOUNCER_DATABASES` and mount a `userlist.txt` at `PGBOUNCER_AUTH_FILE`.

`PGBOUNCER_DATABASES` maps logical database names to real PostgreSQL databases, written as PgBouncer
[`[databases]`](https://www.pgbouncer.org/config.html#section-databases) entries (`name = connection parameters`).
Separate several entries with `;`:

```sh
PGBOUNCER_DATABASES=dns = host=10.0.0.5 port=5432 dbname=technitium; dhcp = host=10.0.0.5 port=5432 dbname=kea
```

Clients connect to `PGBOUNCER_LISTEN_PORT` (default 6432) and use the logical name (`dns` or `dhcp`) as the database
name. The real database name, host and port can then change without touching the clients.

## Kea DHCP (HA load balancing)

Technitium's DHCP server cannot fail over, so for redundant DHCP enable Kea and leave Technitium's DHCP scopes
disabled (both would answer on UDP 67).

- Run one node with `KEA_HA_ROLE=primary` and the other with `KEA_HA_ROLE=secondary`; set `KEA_HA_PRIMARY_ADDR`
  and `KEA_HA_SECONDARY_ADDR` to the nodes' addresses.
- In `load-balancing` mode each node answers about half of the clients and takes over the other half when its peer
  stops responding. Leases are replicated between the nodes over the Kea control agent (`KEA_CTRL_PORT`).
- The control agent API is unauthenticated. Restrict TCP `KEA_CTRL_PORT` to the peer node and set `KEA_CTRL_BIND`.
- DHCP needs layer 2 access: use macvlan or host networking, not a bridged published-port setup.

## Build

```sh
podman build -f Containerfile -t technitium-dns-multi .
```

Upstream versions are build arguments: `TECHNITIUM_VERSION`, `CONSOLE_VERSION`, `ACMESH_VERSION`.

## CI

- `build.yml`: multi-arch build, push to GHCR and Docker Hub, SBOM and provenance, Trivy image scan to code scanning.
  Runs on push to `main`, on `v*` tags, weekly (to pick up distro security updates) and on demand.
- `security.yml`: hadolint, shellcheck and a Trivy repository scan (secrets, misconfiguration, vulnerabilities) daily.
- `renovate.json`: Renovate raises and auto-merges pull requests for new Technitium, Technitium Console and acme.sh
  releases and for GitHub Action updates (pinned by commit SHA). A merge to `main` triggers `build.yml`.

Required repository settings: variable `DOCKERHUB_USERNAME`, secret `DOCKERHUB_TOKEN`, the Renovate GitHub App
installed on the repository, and branch protection that requires the `build` and `security` checks if auto-merge
should wait for them.

## License

See the licenses of the bundled components. This repository's own files are provided as-is.
