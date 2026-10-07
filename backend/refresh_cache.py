"""Refresh ``data/price_cache.json`` from GoodReturns.

Run daily by ``.github/workflows/price-cache.yml`` and usable manually.

This file is the app's *primary* price source: the API serves these cached
values to every user without making any upstream request, so traffic does not
scale with the number of users. Only cities missing from this file (or older
than ``CACHE_MAX_AGE_SECONDS``) fall back to a throttled live scrape.

Only cities that return at least one plausible value are written; an existing
entry is kept if a refresh fails, so one bad day does not blank the app.
"""

import json
import os
from datetime import datetime, timezone
from pathlib import Path

from app import city_slug, fetch_goodreturns_prices

ROOT = Path(__file__).resolve().parent
CACHE_FILE = ROOT / "data" / "price_cache.json"

DEFAULT_CITIES = [
    # metros
    "Delhi", "New Delhi", "Mumbai", "Kolkata", "Bengaluru", "Chennai", "Hyderabad", "Pune", "Ahmedabad",
    # NCR
    "Gurugram", "Noida", "Ghaziabad", "Faridabad",
    # west
    "Surat", "Vadodara", "Rajkot", "Thane", "Navi Mumbai", "Nashik", "Nagpur", "Aurangabad", "Kolhapur", "Solapur",
    # north
    "Jaipur", "Jodhpur", "Udaipur", "Kota", "Lucknow", "Kanpur", "Varanasi", "Agra", "Meerut", "Chandigarh",
    "Ludhiana", "Amritsar", "Dehradun", "Jammu", "Shimla",
    # central / east
    "Bhopal", "Indore", "Gwalior", "Jabalpur", "Raipur", "Ranchi", "Jamshedpur", "Bhubaneswar", "Cuttack", "Patna",
    "Guwahati", "Siliguri",
    # south
    "Kochi", "Thiruvananthapuram", "Kozhikode", "Coimbatore", "Madurai", "Tiruchirappalli", "Mysuru", "Mangaluru",
    "Visakhapatnam", "Vijayawada", "Guntur", "Tirupati",
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
    print(f"wrote {CACHE_FILE} ({updated}/{len(cities)} cities refreshed, {len(cache)} total)")


if __name__ == "__main__":
    main()
