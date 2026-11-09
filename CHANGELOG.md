# Changelog

## Unreleased

- Rebuilt the bundle: supervisord with per-service `ENABLE_*` switches, config rendered from templates and environment variables.
- dnsdist now fronts Technitium (Technitium moved to `127.0.0.1:5353` through its API) instead of both binding port 53.
- Console is unpacked from the release tarball in the console image; the previous `COPY /target` path does not exist in that image.
- Added Kea DHCPv4 with HA load balancing as an optional DHCP component.
- Added multi-arch GHCR and Docker Hub build, Trivy scanning, hadolint, shellcheck and Renovate.
- Replaced hardcoded addresses in `compose.yml` with variables.
- Renamed the project and images to `technitium-dns-multi` (`charlestephen\/technitium-dns-multi` on Docker Hub and GHCR).
- `PGBOUNCER_DATABASES` accepts several entries separated by `;`.
