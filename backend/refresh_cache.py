"""Refresh ``data/price_cache.json`` from GoodReturns.

Run by the scheduled GitHub Actions workflow (``.github/workflows/price-cache.yml``)
and usable manually. Only cities that return at least one plausible value are
written; existing entries are kept if a refresh fails.
"""

import json
import os
from datetime import datetime, timezone
from pathlib import Path

from app import city_slug, fetch_goodreturns_prices

ROOT = Path(__file__).resolve().parent
CACHE_FILE = ROOT / "data" / "price_cache.json"
DEFAULT_CITIES = [
    "Delhi", "Mumbai", "Kolkata", "Bengaluru", "Chennai", "Hyderabad",
    "Pune", "Ahmedabad", "Jaipur", "Lucknow", "Patna", "Bhopal",
]


def main():
    cities = [x.strip() for x in os.getenv("PRICE_CACHE_CITIES", ",".join(DEFAULT_CITIES)).split(",") if x.strip()]
    CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
    try:
        cache = json.loads(CACHE_FILE.read_text())
        if not isinstance(cache, dict):
            cache = {}
    except (FileNotFoundError, json.JSONDecodeError):
        cache = {}

    refreshed_at = datetime.now(timezone.utc).isoformat()
    updated = 0
    for city in cities:
        prices = fetch_goodreturns_prices(city) or {}
        if prices:
            cache[city_slug(city)] = {"city": city, "updatedAt": refreshed_at, "prices": prices, "observedKeys": sorted(prices)}
            updated += 1
            print(f"{city}: {', '.join(sorted(prices))}")
        else:
            print(f"{city}: no usable values (kept previous entry if any)")

    CACHE_FILE.write_text(json.dumps(cache, indent=2, sort_keys=True) + "\n")
    print(f"wrote {CACHE_FILE} ({updated}/{len(cities)} cities refreshed)")


if __name__ == "__main__":
    main()
