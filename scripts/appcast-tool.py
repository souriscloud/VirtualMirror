#!/usr/bin/env python3
"""
appcast-tool.py — Normalize and verify the Sparkle appcast.

Usage:
    scripts/appcast-tool.py fix    <appcast.xml> <owner/repo>
    scripts/appcast-tool.py check  <appcast.xml> <owner/repo> [--online]

Why this exists: generate_appcast rewrites *every* item's download URL with
the single --download-url-prefix passed for the newest release, so older DMGs
end up pointing at a tag that doesn't contain them. It also emits deltas for
older items that were never uploaded. Only the newest item's deltas are ever
used by Sparkle (it updates to the newest item), so we keep those and drop the
rest.

  fix    rewrites every enclosure URL to .../releases/download/v<item version>/<file>
         and removes <sparkle:deltas> from all but the newest item.
  check  verifies the same invariants without writing; with --online it also
         requests every URL and fails on anything but HTTP 200.
"""

import re
import subprocess
import sys

ITEM_RE = re.compile(r"<item>.*?</item>", re.S)
VERSION_RE = re.compile(r"<sparkle:shortVersionString>([^<]+)</sparkle:shortVersionString>")
URL_RE = re.compile(r'url="([^"]+)"')
DELTAS_RE = re.compile(r"\n?[ \t]*<sparkle:deltas>.*?</sparkle:deltas>", re.S)


def expected_url(repo, version, url):
    filename = url.rsplit("/", 1)[-1]
    return f"https://github.com/{repo}/releases/download/v{version}/{filename}"


def item_version(item):
    match = VERSION_RE.search(item)
    if not match:
        raise SystemExit("ERROR: appcast item without sparkle:shortVersionString")
    return match.group(1)


def fix(text, repo):
    index = 0

    def fix_item(match):
        nonlocal index
        item = match.group(0)
        version = item_version(item)
        if index > 0:
            item = DELTAS_RE.sub("", item)
        index += 1
        return URL_RE.sub(lambda m: f'url="{expected_url(repo, version, m.group(1))}"', item)

    return ITEM_RE.sub(fix_item, text)


def check(text, repo, online):
    problems = []
    urls = []
    for index, item in enumerate(ITEM_RE.findall(text)):
        version = item_version(item)
        if index > 0 and "<sparkle:deltas>" in item:
            problems.append(f"{version}: deltas on a non-newest item")
        for url in URL_RE.findall(item):
            urls.append(url)
            if url != expected_url(repo, version, url):
                problems.append(f"{version}: {url} is not under tag v{version}")

    if online:
        for url in urls:
            status = subprocess.run(
                ["curl", "-sIL", "-o", "/dev/null", "-w", "%{http_code}", url],
                capture_output=True, text=True,
            ).stdout.strip()
            if status != "200":
                problems.append(f"HTTP {status}: {url}")

    for problem in problems:
        print(f"appcast: {problem}", file=sys.stderr)
    if not problems:
        print(f"appcast: OK ({len(urls)} URLs{', all reachable' if online else ''})")
    return 1 if problems else 0


def main(argv):
    if len(argv) < 4 or argv[1] not in ("fix", "check"):
        print(__doc__.strip(), file=sys.stderr)
        return 2
    command, path, repo = argv[1], argv[2], argv[3]
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if command == "fix":
        with open(path, "w", encoding="utf-8") as f:
            f.write(fix(text, repo))
        return check(fix(text, repo), repo, online=False)
    return check(text, repo, online="--online" in argv[4:])


if __name__ == "__main__":
    sys.exit(main(sys.argv))
