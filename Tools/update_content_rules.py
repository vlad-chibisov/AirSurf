#!/usr/bin/env python3
"""Builds the browser's ad-blocking rules (a WebKit content blocker list).

Inputs (both in this folder):
  adservers.txt          Peter Lowe's ad and tracking server list, one domain per line.
                         Refresh it with --download.
  extra-ad-domains.txt   Hand-maintained additions for streaming sites.

Outputs:
  ../AirSurf/Resources/ContentRules-Ads.json
  ../AirSurf/Resources/ContentRulesInfo.plist   (rule count shown in the menu)

Usage:
  python3 Tools/update_content_rules.py [--download]
"""
import json
import plistlib
import re
import sys
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
RESOURCES = HERE.parent / "AirSurf" / "Resources"
SOURCE_URL = "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=nohtml&showintro=0&mimetype=plaintext"
DOMAIN = re.compile(r"^(?=.{4,253}$)([a-z0-9-]+\.)+[a-z][a-z0-9-]+$")

# Hosts that must never be blocked even if a list mentions them: blocking these breaks
# ordinary sites or video playback.
NEVER_BLOCK = {
    "google.com", "www.google.com", "youtube.com", "www.youtube.com", "googlevideo.com",
    "yandex.ru", "ya.ru", "gstatic.com", "apple.com", "icloud.com",
}

COSMETIC_SELECTORS = [
    "ins.adsbygoogle",
    "div[id^='google_ads_iframe']",
    "div[id^='yandex_rtb']",
    "div[id^='adfox_']",
    "iframe[src*='googlesyndication.com']",
    "iframe[src*='an.yandex.ru']",
]


def read_domains(path):
    domains = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip().lower()
        if line and DOMAIN.match(line) and line not in NEVER_BLOCK:
            domains.append(line)
    return domains


def read_host_patterns(path):
    """Lines like "re:moviead[0-9]*\\.ru": host regexes for networks that rotate domains."""
    patterns = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("re:") and len(line) > 3:
            pattern = line[3:]
            if any(token in pattern for token in ("|", "{", "}", "\\d", "\\w", "\\s")):
                sys.exit(f"Unsupported in WebKit content rules: {pattern}")
            patterns.append(pattern)
    return patterns


def main():
    adservers = HERE / "adservers.txt"
    if "--download" in sys.argv:
        request = urllib.request.Request(SOURCE_URL, headers={"User-Agent": "content-rules-builder"})
        with urllib.request.urlopen(request, timeout=30) as response:
            adservers.write_bytes(response.read())

    domains = sorted(set(read_domains(adservers)) | set(read_domains(HERE / "extra-ad-domains.txt")))
    # Drop subdomains whose parent is already listed; the parent rule covers them.
    listed = set(domains)
    domains = [d for d in domains if not any(d.endswith("." + p) for p in listed if p != d)]

    rules = []
    for domain in domains:
        rules.append({
            "trigger": {
                "url-filter": "^https?://([^/]+\\.)?" + re.escape(domain).replace("\\-", "-") + "[:/]",
                "load-type": ["third-party"],
            },
            "action": {"type": "block"},
        })
    for pattern in read_host_patterns(HERE / "extra-ad-domains.txt"):
        rules.append({
            "trigger": {"url-filter": "^https?://([^/]+\\.)?" + pattern + "[:/]", "load-type": ["third-party"]},
            "action": {"type": "block"},
        })
    rules.append({
        "trigger": {"url-filter": ".*"},
        "action": {"type": "css-display-none", "selector": ", ".join(COSMETIC_SELECTORS)},
    })

    RESOURCES.mkdir(parents=True, exist_ok=True)
    (RESOURCES / "ContentRules-Ads.json").write_text(json.dumps(rules, separators=(",", ":")), encoding="utf-8")
    with open(RESOURCES / "ContentRulesInfo.plist", "wb") as handle:
        plistlib.dump({"ruleCount": len(rules), "domainCount": len(domains)}, handle)
    print(f"{len(domains)} domains, {len(rules)} rules")


if __name__ == "__main__":
    main()
