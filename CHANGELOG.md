# Changelog

## Unreleased

- Rebuilt the bundle: supervisord with per-service `ENABLE_*` switches, config rendered from templates and environment variables.
- dnsdist now fronts Technitium (Technitium moved to `127.0.0.1:5353` through its API) instead of both binding port 53.
- Console is unpacked from the release tarball in the console image; the previous `COPY /target` path does not exist in that image.
- Added Kea DHCPv4 with HA load balancing as an optional DHCP component.
- Added multi-arch GHCR and Docker Hub build, hadolint, shellcheck and Renovate.
- Replaced hardcoded addresses in `compose.yml` with variables.
- Renamed the project and images to `technitium-dns-multi` (`charlestephen/technitium-dns-multi` on Docker Hub and GHCR).
- `PGBOUNCER_DATABASES` accepts several entries separated by `;`.
- Added acme.sh back: pinned release install, DNS-01 issuance, PKCS#12 output for Technitium.
- PgBouncer documentation uses logical database names (`dns`, `dhcp`).
- dnsdist now serves plain DNS, DoT, DoH and DoQ with the supplied PEM certificate; it is installed from PowerDNS's repository (2.1.3) because Ubuntu's 1.8.x has no DoQ.
- dnsdist talks to Technitium with the PROXY protocol so Technitium sees real client addresses; Technitium's own DoT/DoH/DoQ listeners are disabled.
- acme.sh restarts dnsdist after each issue or renewal; build asserts libmsquic, dig and dnsdist QUIC support.
- Added a Requirements section to the README.
- Added automatic releases: a release job creates a GitHub release and a changelog entry from the versions of the bundled applications and their upstream release notes.
- Removed Trivy scanning from the workflows.
- Added a GPL-3.0-or-later license, matching Technitium DNS Server, Technitium Console and acme.sh.
- Docker Hub push is skipped, not failed, when the `DOCKERHUB_TOKEN` secret is missing; the Docker Hub user name is fixed in the workflow.
- Containerfile passes hadolint: `pipefail` shell, `WORKDIR` for the acme.sh install, JSON-form health check; build also asserts the `postgres` user exists.
- Health check treats SERVFAIL and REFUSED as unhealthy, so a dead Technitium behind a running dnsdist moves the virtual IP; loopback is always in the dnsdist ACL.
- `CMD` is cleared, because the base image's `CMD ["/etc/dns"]` was passed to the new entrypoint.
- Renovate: dependency dashboard configured with a weekly schedule, PR limits, a 3 day release age, grouped GitHub Actions updates, dnsdist held to 2.1.x, and major updates approved from the dashboard.
- Fixed the image build: the dnsdist 2.1 repository is signed by key FD380FBB, not the master-branch key that was pinned.
- Added the dnsdist dashboard and API (port 8083), protected by `DNSDIST_WEB_PASSWORD` and limited by `DNSDIST_WEB_ACL`; it is not started without a password.
