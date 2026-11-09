# Changelog

## Unreleased

- Rebuilt the bundle: supervisord with per-service `ENABLE_*` switches, config rendered from templates and environment variables.
- dnsdist now fronts Technitium (Technitium moved to `127.0.0.1:5353` through its API) instead of both binding port 53.
- Console is unpacked from the release tarball in the console image; the previous `COPY /target` path does not exist in that image.
- Added Kea DHCPv4 with HA load balancing as an optional DHCP component.
- Added multi-arch GHCR and Docker Hub build, Trivy scanning, hadolint, shellcheck and Renovate.
- Replaced hardcoded addresses in `compose.yml` with variables.
- Renamed the project and images to `technitium-dns-multi` (`charlestephen/technitium-dns-multi` on Docker Hub and GHCR).
- `PGBOUNCER_DATABASES` accepts several entries separated by `;`.
- Added acme.sh back: pinned release install, DNS-01 issuance, PKCS#12 output for Technitium.
- PgBouncer documentation uses logical database names (`dns`, `dhcp`).
- dnsdist now serves plain DNS, DoT, DoH and DoQ with the supplied PEM certificate; it is installed from PowerDNS's repository (2.1.3) because Ubuntu's 1.8.x has no DoQ.
- dnsdist talks to Technitium with the PROXY protocol so Technitium sees real client addresses; Technitium's own DoT/DoH/DoQ listeners are disabled.
- acme.sh restarts dnsdist after each issue or renewal; build asserts libmsquic, dig and dnsdist QUIC support.
- Added a Requirements section to the README.
