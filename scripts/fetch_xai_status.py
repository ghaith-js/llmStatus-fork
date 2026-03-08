#!/usr/bin/env python3
"""Fetch xAI (Grok) status using StealthyFetcher to bypass Cloudflare.

Outputs JSON to stdout:
  {"status": "operational"|"degraded"|"majorOutage"|"critical"|"unknown",
   "incidents": [{"id": "...", "name": "..."}]}

Requires: pip install "scrapling[all]" && scrapling install
"""

import json
import sys
import logging

# Suppress scrapling's noisy logging
logging.disable(logging.WARNING)

try:
    from scrapling.fetchers import StealthyFetcher
except ImportError:
    print(json.dumps({"status": "unknown", "incidents": [], "error": "scrapling not installed"}))
    sys.exit(0)


def fetch_xai_status():
    try:
        page = StealthyFetcher.fetch(
            "https://status.x.ai/",
            headless=True,
            solve_cloudflare=True,
            network_idle=True,
        )
        html = page.body.decode() if isinstance(page.body, bytes) else str(page.body)
    except Exception as e:
        return {"status": "unknown", "incidents": [], "error": str(e)}

    lower = html.lower()

    # Detect status from page content
    status = "unknown"
    if "no incidents declared" in lower or "no known incidents" in lower:
        status = "operational"
    elif "major outage" in lower or "major_outage" in lower:
        status = "majorOutage"
    elif "degraded" in lower or "partial outage" in lower:
        status = "degraded"
    elif "incidents declared" in lower:
        # There are incidents but we can't determine severity
        status = "degraded"

    # Extract incident names if any
    incidents = []
    if status != "operational":
        import re
        # Look for incident headings in the HTML
        matches = re.findall(r'heading-3["\s>]+([^<]+)', html)
        for name in matches:
            name = name.strip()
            if name and "No incidents" not in name:
                incidents.append({"id": name[:32], "name": name})

    return {"status": status, "incidents": incidents}


if __name__ == "__main__":
    result = fetch_xai_status()
    print(json.dumps(result))
