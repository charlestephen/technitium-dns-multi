#!/usr/bin/env python3
"""Build release notes from the versions of the applications bundled in the image.

Versions come from the ARG lines in the Containerfile (pinned upstream releases) and from
`dpkg-query` output taken from the built image (apt packages). Upstream release notes are
fetched for every component whose version changed since the previous release.
"""
import argparse
import datetime
import http.client
import json
import os
import re
import sys
import urllib.error
import urllib.request

MAX_NOTES = 10000
MARKER = re.compile(r"<!-- versions: (\{.*?\}) -->")


def get(url):
    """Fetch a URL as text; return None on failure so missing notes never block a release."""
    headers = {"User-Agent": "technitium-dns-multi-release-notes", "Accept-Encoding": "identity", "Connection": "close"}
    token = os.environ.get("GITHUB_TOKEN")
    if token and url.startswith("https://api.github.com/"):
        headers["Authorization"] = f"Bearer {token}"
    for attempt in (1, 2):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=30) as r:
                return r.read().decode("utf-8", "replace")
        except (OSError, http.client.HTTPException) as e:  # URLError and timeouts are OSError
            print(f"warning: {url} (attempt {attempt}): {e}", file=sys.stderr)
    return None


def upstream(version):
    """Upstream version from a Debian version string (drops epoch and packaging revision)."""
    m = re.match(r"^(?:\d+:)?(\d+(?:\.\d+)*)", version)
    return m.group(1) if m else version


def clean(text, repo=None):
    """Make third-party text safe to republish: no mentions, no cross-repo issue links."""
    text = re.sub(r"(?<![\w`])@([A-Za-z0-9][A-Za-z0-9-]*)", r"`@\1`", text)
    if repo:
        text = re.sub(r"(?<![\w/&\[])#(\d{1,7})\b", rf"[#\1](https://github.com/{repo}/issues/\1)", text)
    return nest_headings(text.replace("\r\n", "\n").strip())


def nest_headings(text, shift=3):
    """Push Markdown headings down so upstream notes sit below our own headings."""
    out, fenced = [], False
    for line in text.split("\n"):
        if line.lstrip().startswith(("```", "~~~")):
            fenced = not fenced
        m = None if fenced else re.match(r"^(#{1,6})\s", line)
        out.append("#" * min(6, len(m.group(1)) + shift) + line[len(m.group(1)):] if m else line)
    return "\n".join(out)


def cap(text, link):
    if len(text) <= MAX_NOTES:
        return text
    cut = text[:MAX_NOTES].rsplit("\n", 1)[0]
    return f"{cut}\n\n_Truncated. Full notes: {link}_"


def github_release(repo, tag):
    data = get(f"https://api.github.com/repos/{repo}/releases/tags/{tag}")
    if not data:
        return None
    body = (json.loads(data).get("body") or "").strip()
    return clean(body, repo) if body else None


def dnsdist_notes(version):
    rst = get("https://raw.githubusercontent.com/PowerDNS/pdns/master/pdns/dnsdistdist/docs/changelog.rst")
    if not rst:
        return None
    for block in re.split(r"^\.\. changelog::\s*\n", rst, flags=re.M)[1:]:
        m = re.search(r"^\s+:version:\s*(\S+)", block, re.M)
        if not m or m.group(1) != version:
            continue
        items = []
        for change in re.split(r"^\s+\.\. change::\s*\n", block, flags=re.M)[1:]:
            tags = re.search(r":tags:\s*(.+)", change)
            pr = re.search(r":pullreq:\s*(\d+)", change)
            text = " ".join(l.strip() for l in change.splitlines() if l.strip() and not l.strip().startswith(":"))
            text = text.replace("``", "`")
            ref = f" ([#{pr.group(1)}](https://github.com/PowerDNS/pdns/pull/{pr.group(1)}))" if pr else ""
            label = f"**{tags.group(1).strip()}**: " if tags else ""
            if text:
                items.append(f"- {label}{text}{ref}")
        return clean("\n".join(items)) if items else None
    return None


def pgbouncer_tag(v):
    return "pgbouncer_" + v.replace(".", "_")


# key, display name, source ("arg:NAME" or "dpkg:package"), notes fetcher, notes link
COMPONENTS = [
    ("technitium", "Technitium DNS Server", "arg:TECHNITIUM_VERSION",
     lambda v: github_release("TechnitiumSoftware/DnsServer", f"v{v}"),
     lambda v: f"https://github.com/TechnitiumSoftware/DnsServer/releases/tag/v{v}"),
    ("console", "Technitium Console", "arg:CONSOLE_VERSION",
     lambda v: github_release("byGarcia/technitium-console", f"v{v}"),
     lambda v: f"https://github.com/byGarcia/technitium-console/releases/tag/v{v}"),
    ("dnsdist", "dnsdist", "arg:DNSDIST_VERSION", dnsdist_notes,
     lambda v: "https://dnsdist.org/changelog.html"),
    ("acme", "acme.sh", "arg:ACMESH_VERSION",
     lambda v: github_release("acmesh-official/acme.sh", v),
     lambda v: f"https://github.com/acmesh-official/acme.sh/releases/tag/{v}"),
    ("keepalived", "keepalived", "dpkg:keepalived", lambda v: None,
     lambda v: f"https://www.keepalived.org/release-notes/Release-{v}/"),
    ("pgbouncer", "PgBouncer", "dpkg:pgbouncer",
     lambda v: github_release("pgbouncer/pgbouncer", pgbouncer_tag(v)),
     lambda v: f"https://github.com/pgbouncer/pgbouncer/releases/tag/{pgbouncer_tag(v)}"),
    ("msquic", "libmsquic (Technitium DNS over QUIC)", "dpkg:libmsquic",
     lambda v: github_release("microsoft/msquic", f"v{v}"),
     lambda v: f"https://github.com/microsoft/msquic/releases/tag/v{v}"),
]


# Components that were bundled earlier, so a release that drops one can say so.
FORMER = {"kea": "Kea DHCP"}


def read_versions(containerfile, packages):
    args = dict(re.findall(r"^ARG (\w+)=(\S+)", open(containerfile).read(), re.M))
    pkgs = dict(l.strip().split("=", 1) for l in open(packages) if "=" in l)
    out = {}
    for key, _, source, _, _ in COMPONENTS:
        kind, name = source.split(":", 1)
        value = args.get(name) if kind == "arg" else pkgs.get(name)
        if not value:
            sys.exit(f"error: no version found for {key} ({source})")
        out[key] = value
    return out


def pick_tag(existing, today):
    base = f"v{today.year}.{today.month:02d}.{today.day:02d}"
    tag, n = base, 1
    while tag in existing:
        n += 1
        tag = f"{base}.{n}"
    return tag


def build(cur, prev, tag, today):
    rows, sections = [], []
    for key, name, _, fetch, link in COMPONENTS:
        v = cur[key]
        up = upstream(v)
        old = prev.get(key)
        up_old = upstream(old) if old else None
        if old is None:
            status = "new"
        elif old == v:
            status = "unchanged"
        elif up_old == up:
            status = f"rebuilt ({old} → {v})"
        else:
            status = f"{up_old} → {up}"
        rows.append(f"| {name} | {up} | {status} | [notes]({link(up)}) |")
        if up_old != up:
            notes = fetch(up)
            title = f"### {name} {up}" + (f" (was {up_old})" if up_old else "")
            body = cap(notes, link(up)) if notes else f"No machine-readable release notes. See {link(up)}."
            sections.append(f"{title}\n\n{body}")
    for key in sorted(set(prev) - set(cur)):
        rows.append(f"| {FORMER.get(key, key)} | | removed | |")
    core = ["## Bundled versions", "", "| Component | Version | Change | Release notes |", "|---|---|---|---|", *rows]
    if sections:
        core += ["", "## Upstream release notes", "", "\n\n".join(sections)]
    return "\n".join(core) + "\n"


def insert_changelog(path, heading, core):
    text = open(path).read()
    core = re.sub(r"^(##|###) ", lambda m: "#" + m.group(1) + " ", core, flags=re.M)
    section = f"{heading}\n\n{core}\n"
    # new release goes after the Unreleased section, before the next "## " heading
    m = re.search(r"^## Unreleased\n", text, re.M)
    if not m:
        text = text.rstrip("\n") + "\n\n" + section
    else:
        nxt = re.search(r"^## ", text[m.end():], re.M)
        pos = m.end() + nxt.start() if nxt else len(text)
        text = text[:pos].rstrip("\n") + "\n\n" + section + ("\n" + text[pos:] if nxt else "")
    open(path, "w").write(text)


def selftest():
    assert upstream("1:2.2.8-1build3") == "2.2.8"
    assert upstream("2.4.1-3ubuntu0.2") == "2.4.1"
    assert upstream("15.6.2") == "15.6.2"
    assert pgbouncer_tag("1.22.1") == "pgbouncer_1_22_1"
    day = datetime.date(2026, 11, 9)
    assert pick_tag(set(), day) == "v2026.11.09"
    assert pick_tag({"v2026.11.09", "v2026.11.09.2"}, day) == "v2026.11.09.3"
    assert nest_headings("# A\n```\n# keep\n```\n## B") == "#### A\n```\n# keep\n```\n##### B"
    assert clean("thanks @octocat, fixes #12", "o/r") == "thanks `@octocat`, fixes [#12](https://github.com/o/r/issues/12)"
    assert clean("mail me@example.com") == "mail me@example.com"
    same = {key: "1.0" for key, *_ in COMPONENTS}
    table = build(same, {**same, "kea": "2.4.1-3"}, "v2026.01.01", datetime.date(2026, 1, 1))
    assert "| Kea DHCP | | removed | |" in table, table
    print("selftest ok")


def main():
    if "--selftest" in sys.argv:
        return selftest()
    ap = argparse.ArgumentParser()
    ap.add_argument("--containerfile", default="Containerfile")
    ap.add_argument("--packages", required=True, help="file of name=version lines from dpkg-query")
    ap.add_argument("--previous-body", help="body of the previous release (holds the versions marker)")
    ap.add_argument("--existing-tags", help="file with one existing tag per line")
    ap.add_argument("--images", nargs="*", default=[], help="image repositories to list in the release")
    ap.add_argument("--changelog", help="CHANGELOG.md to update in place")
    ap.add_argument("--out-release", default="release.md")
    args = ap.parse_args()

    cur = read_versions(args.containerfile, args.packages)
    prev = {}
    if args.previous_body and os.path.exists(args.previous_body):
        m = MARKER.search(open(args.previous_body).read())
        if m:
            prev = json.loads(m.group(1))
    changed = cur != prev

    existing = set(open(args.existing_tags).read().split()) if args.existing_tags else set()
    today = datetime.datetime.now(datetime.timezone.utc).date()
    tag = pick_tag(existing, today)

    if changed:
        core = build(cur, prev, tag, today)
        pulls = "\n".join(f"- `docker pull {i}:{tag}`" for i in args.images)
        release = (f"## Images\n\n{pulls}\n\n" if pulls else "") + core + f"\n<!-- versions: {json.dumps(cur, sort_keys=True)} -->\n"
        open(args.out_release, "w").write(release)
        if args.changelog:
            insert_changelog(args.changelog, f"## {tag} ({today.isoformat()})", core)

    out = os.environ.get("GITHUB_OUTPUT")
    lines = f"changed={'true' if changed else 'false'}\ntag={tag}\n"
    if out:
        open(out, "a").write(lines)
    print(lines, end="")


if __name__ == "__main__":
    main()
