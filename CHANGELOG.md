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

## v2026.11.9 (2026-11-09)

### Bundled versions

| Component | Version | Change | Release notes |
|---|---|---|---|
| Technitium DNS Server | 15.6.2 | new | [notes](https://github.com/TechnitiumSoftware/DnsServer/releases/tag/v15.6.2) |
| Technitium Console | 1.4.1 | new | [notes](https://github.com/byGarcia/technitium-console/releases/tag/v1.4.1) |
| dnsdist | 2.1.3 | new | [notes](https://dnsdist.org/changelog.html) |
| acme.sh | 3.1.6 | new | [notes](https://github.com/acmesh-official/acme.sh/releases/tag/3.1.6) |
| keepalived | 2.2.8 | new | [notes](https://www.keepalived.org/release-notes/Release-2.2.8/) |
| PgBouncer | 1.22.0 | new | [notes](https://github.com/pgbouncer/pgbouncer/releases/tag/pgbouncer_1_22_0) |
| Kea DHCP | 2.4.1 | new | [notes](https://downloads.isc.org/isc/kea/2.4.1/Kea-2.4.1-ReleaseNotes.txt) |
| libmsquic (Technitium DNS over QUIC) | 2.6.3 | new | [notes](https://github.com/microsoft/msquic/releases/tag/v2.6.3) |

### Upstream release notes

#### Technitium DNS Server 15.6.2

Technitium DNS Server v15.6.2 is now available for download. This is a service update for the previous release that fixes multiple issues.

See what's new in this release:
https://github.com/TechnitiumSoftware/DnsServer/blob/master/CHANGELOG.md

#### Technitium Console 1.4.1

**A visual editor for Advanced Blocking, a console that runs as its own container, and a console you can install as an app.** Every feature of the stock console works as before, through the same API: checked against Technitium DNS Server 15.6.2. Each addition is written down, with its limits, in [CONVENTIONS.md](CONVENTIONS.md#deliberate-deviations-from-upstream-behaviour).

Thanks to the people who asked for these: see each line below.

###### New

- **A standalone container.** `ghcr.io/bygarcia/technitium-console-standalone` runs the console as a web container of its own: give it `TECHNITIUM_URL`, and it serves the console and forwards the API to your server, with nothing installed on the DNS server. Same tags and the same per-platform check as the existing image, which stays as it was. See [Standalone container](README.md#standalone-container). Requested by `@triptolemus510` in [#27](https://github.com/byGarcia/technitium-console/issues/27), and by u/Nervous-Cheek-583 and u/flobernd on r/technitium.
- **The console can be installed as an app**, on a phone or desktop home screen, with its own icon and a browser bar that follows the theme. It has no service worker and no offline cache, so what you see always comes from the server.
- **Refresh on the Dashboard**: a button beside the period reloads the figures on demand for the chosen period, node and custom range. The idea comes from `@varunagarwal-pro`'s dashboard proposal for the stock console.
- **A visual editor for the Advanced Blocking app**: `Visual Editor` in the app's row in Apps opens its clients, groups, domains, regex and list URLs on one page, checked as the server reads them. The JSON stays one click away. Saving changes only what you changed and keeps what the editor does not know; a config it cannot keep exactly, it refuses to edit and says why. Requested by u/The4Dees on r/technitium.



**Install or update:** run the one-line installer from the [README](https://github.com/byGarcia/technitium-console#installing) again. Which console goes with which server: [CHANGELOG](https://github.com/byGarcia/technitium-console/blob/main/CHANGELOG.md#which-version-for-which-server).

**On Docker:** `docker compose pull technitium-console && docker compose up -d technitium-console`, or pin `ghcr.io/bygarcia/technitium-console:1.4.1`. See [Docker](https://github.com/byGarcia/technitium-console#docker).


##### What's Changed
* A visual editor for the Advanced Blocking app by `@byGarcia` in https://github.com/byGarcia/technitium-console/pull/29
* Release 1.4.1 by `@byGarcia` in https://github.com/byGarcia/technitium-console/pull/30


**Full Changelog**: https://github.com/byGarcia/technitium-console/compare/v1.4.0...v1.4.1

#### dnsdist 2.1.3

- **Bug Fixes**: Fix possible use-after-free in add*Action ([#18062](https://github.com/PowerDNS/pdns/pull/18062))
- **Bug Fixes, DNS over TLS, DNS over HTTPS**: Stop Closing TLS connections too early (DNSBunker) ([#18150](https://github.com/PowerDNS/pdns/pull/18150))
- **Improvements, Webserver, Metrics**: Tighten access to metrics when the dashboard is passwordless ([#18151](https://github.com/PowerDNS/pdns/pull/18151))
- **Bug Fixes**: Skip timeout entries for DynBlock NMT rules ([#18152](https://github.com/PowerDNS/pdns/pull/18152))
- **Bug Fixes**: Fix several AF_XDP / XSK issues ([#18153](https://github.com/PowerDNS/pdns/pull/18153))
- **Bug Fixes, Metrics**: Correct stat name lookup in `udpErrorStats()` ([#18154](https://github.com/PowerDNS/pdns/pull/18154))
- **Bug Fixes**: Fix out-of-range exception in `getEDNSOptionsFromContent` ([#18155](https://github.com/PowerDNS/pdns/pull/18155))

#### acme.sh 3.1.6

1. Release tags are signed from 3.1.6 on. The public key is allowed_signers
in this repository; see "Verify a Release" in the README.
2. 3.1.5 and earlier are unsigned. The 3.1.5 tag was created by the GitHub
release form, which can only produce a lightweight tag and therefore carries
no signature ([#7273](https://github.com/acmesh-official/acme.sh/issues/7273)).
3. No functional change since 3.1.5.

#### keepalived 2.2.8

No machine-readable release notes. See https://www.keepalived.org/release-notes/Release-2.2.8/.

#### PgBouncer 1.22.0

**2024-01-31  -  PgBouncer 1.22.0  -  "DEALLOCATE ALL"**

- Features
  * Adds support for `DEALLOCATE ALL` and `DISCARD ALL` when `max_prepared_statements` is set to a non-zero value (normal `DEALLOCATE`
    is still unsupported) ([#972])
  * Support configuring `auth_query` per database ([#979])

- Changes
  * Improve settings in the recommended systemd unit file ([#983])
  * Make fail fast logic handle all scenarios where no working connections to the database exist anymore and none can be established ([#998])
  * Multiple documentation improvements

- Fixes
  * Fix issue in PG14+ where PgBouncer would send `SET DateStyle='ISO'` for every transaction ([#879])
  * Fix handling of empty `application_name` ([#999])
  * Fix building on Windows with OpenSSL 3.2.0 ([#1009])

[#972]: https://github.com/pgbouncer/pgbouncer/pull/972
[#979]: https://github.com/pgbouncer/pgbouncer/pull/979
[#983]: https://github.com/pgbouncer/pgbouncer/pull/983
[#998]: https://github.com/pgbouncer/pgbouncer/pull/998
[#879]: https://github.com/pgbouncer/pgbouncer/pull/879
[#999]: https://github.com/pgbouncer/pgbouncer/pull/999
[#1009]: https://github.com/pgbouncer/pgbouncer/pull/1009

##### New Contributors
* `@mudit-loya` made their first contribution in https://github.com/pgbouncer/pgbouncer/pull/965
* `@GuanqunYang193` made their first contribution in https://github.com/pgbouncer/pgbouncer/pull/979
* `@joseortiz3` made their first contribution in https://github.com/pgbouncer/pgbouncer/pull/994
* `@tcraxs` made their first contribution in https://github.com/pgbouncer/pgbouncer/pull/1004

**All changes**: https://github.com/pgbouncer/pgbouncer/compare/pgbouncer_1_21_0...pgbouncer_1_22_0

#### Kea DHCP 2.4.1

```text
# Kea 2.4.1 Release Notes, November 29, 2023

Welcome to Kea 2.4.1, a maintenance release of the stable 2.4 series.

Kea is a DHCP implementation developed by Internet Systems Consortium 
(ISC) that features DHCPv4 and DHCPv6 servers with DNS update and a REST 
API; optional database support (MySQL and PostgreSQL); optional RADIUS, 
Kerberos, YANG/NETCONF, and GSS-TSIG support; and much more. Kea 
provides extensive management capabilities, including but not limited 
to: TLS support, Role-Based Access Control, run-time configuration 
monitoring and updates via a REST API, host reservations, and client 
classification.

The text below references issue numbers. For more details, visit the Kea 
GitLab page at https://gitlab.isc.org/isc-projects/kea/-/issues. For 
details about Docker issues, visit the page at 
https://gitlab.isc.org/isc-projects/kea-docker/-/issues/. For details 
about packaging, visit the page at 
https://gitlab.isc.org/isc-projects/kea-packaging/-/issues/.

Fixes for the following bugs have been implemented since the previous 
release, version 2.4.0:

1. **Race condition in FLQ**: The Free Lease Queue (FLQ) allocator is 
now thread-safe. It suffered from a race condition which could result in 
kea-dhcp4 crashing [#3143].
2. **Interface redetection regression**: Interface redetection governed 
by the "re-detect" configuration flag, which is enabled by default, 
stopped working with the 2.3.6 release. It is now working again as of 
version 2.4.1 [#3145].
3. **Minor hammer update**: A minor change to hammer, our build tool, 
was introduced to fix issues with building the 2.4 branch on our test 
farm [#3148].

### Incompatible Changes

None.

### License

This version of Kea is released under the Mozilla Public License, 
version 2.0.

https://www.mozilla.org/en-US/MPL/2.0

Some Kea hook libraries are provided under the MPL 2.0; others are 
licensed with the Kea Hooks Basic Commercial End User License. The 
source for each hook library includes the applicable license.

### Download

Pre-built ISC packages for current versions of the most popular Linux 
operating systems are available at:

https://cloudsmith.io/\~isc/repos/

Pre-built Docker images and well as Docker files are available. For 
details, see:

https://gitlab.isc.org/isc-projects/kea-docker

The Kea source and PGP signature for this release may be downloaded from:

https://www.isc.org/download

The signature was generated with the ISC code-signing key, which is 
available at:

https://www.isc.org/pgpkey

ISC provides detailed documentation, including installation instructions 
and usage tutorials, in the Kea Administrator Reference Manual. 
Documentation is included with the installation or at 
https://kea.readthedocs.io/en/latest/index.html in HTML, PDF, or EPUB 
formats. ISC maintains a public open source code tree, wiki, issue 
tracking system, milestone planner, and roadmap at 
https://gitlab.isc.org/isc-projects/kea.

Limitations and known issues with this release can be found at 
https://gitlab.isc.org/isc-projects/kea/-/wikis/known-issues-list.

We ask users of this software to please let us know how it worked for 
you and what operating system you tested on. Feel free to share your 
feedback on the Kea Users mailing list 
(https://lists.isc.org/mailman/listinfo/kea-users). We would also like 
to hear whether the documentation is adequate and accurate. Please open 
tickets in the Kea GitLab project for bugs, documentation omissions and 
errors, and enhancement requests. We want to hear from you even if 
everything worked.

### Support

Professional support for Kea is available from ISC. We encourage all 
professional users to consider this option; Kea maintenance is funded 
with support subscriptions. For more information on ISC's Kea software 
support, see https://www.isc.org/support/.

Free best-effort support is provided by our user community via a mailing 
list. Information on all public email lists is available at 
https://www.isc.org/community/mailing-list. If you have any comments or 
questions about working with Kea, please share them to the Kea Users 
list (https://lists.isc.org/mailman/listinfo/kea-users). Bugs and 
feature requests may be submitted via GitLab at 
https://gitlab.isc.org/isc-projects/kea/-/issues.

### Changes

The following summarizes changes and important upgrades since the 
previous release, version 2.4.0.

2169.	[build]		razvan
	The library version numbers have been bumped up for the Kea 2.4.1
	stable release.
	(Gitlab #3153)

2168.	[bug]		andrei
	Fixed interface redetection which had stopped working since
	Kea 2.3.6.
	(Gitlab #3017, #3145)

2167.	[bug]		razvan
	Fixed a race condition in free lease queue allocator.
	(Gitlab #3111, #3143)

There were no changes to the hook libraries, but please update hook 
libraries to the 2.4.1 version when updating your core application(s).

Thank you again to everyone who assisted us in making this release 
possible.

We look forward to receiving your feedback.
```

#### libmsquic (Technitium DNS over QUIC) 2.6.3

##### What's Changed
* [CP] Fix portable certificate context cleanup ([#6344](https://github.com/microsoft/msquic/issues/6344)) by `@guhetier` in https://github.com/microsoft/msquic/pull/6352
* [CP] OpenSSL: Eliminate RECORD_ENTRY receive buffering ([#6314](https://github.com/microsoft/msquic/issues/6314)) by `@Santhosha-bk` in https://github.com/microsoft/msquic/pull/6375
* [CP] Validate stream receive buffer size ([#6302](https://github.com/microsoft/msquic/issues/6302)) by `@Santhosha-bk` in https://github.com/microsoft/msquic/pull/6377
* [CP] Fixed divide by zero receive window ([#6364](https://github.com/microsoft/msquic/issues/6364)) by `@Santhosha-bk` in https://github.com/microsoft/msquic/pull/6378
* Bump version to 2.6.3 by `@guhetier` in https://github.com/microsoft/msquic/pull/6379
* [CP] Prevents an all-zero PATH_RESPONSE sent before a PATH_CHALLENGE from validating the path ([#6382](https://github.com/microsoft/msquic/issues/6382)) by `@guhetier` in https://github.com/microsoft/msquic/pull/6390
* [CP] Fix Ack of a retransmitted RETIRE_CONNECTION_ID causing use-after-free of a CID ([#6383](https://github.com/microsoft/msquic/issues/6383)) by `@guhetier` in https://github.com/microsoft/msquic/pull/6389
* [CP] Fix uint16_t underflow in QuicStreamSendWrite ([#6384](https://github.com/microsoft/msquic/issues/6384)) by `@guhetier` in https://github.com/microsoft/msquic/pull/6386


**Full Changelog**: https://github.com/microsoft/msquic/compare/v2.6.2...v2.6.3

