"""Refresh the price cache from GoodReturns.

Run daily by ``.github/workflows/price-cache.yml`` and usable manually.

Two layers, so every PIN code in India resolves to real prices:

1. **Districts** — every PIN code belongs to a district, and GoodReturns has a
   dedicated page for a large share of India's districts (Gorakhpur, Bhadohi,
   Faizabad, ...). We fetch those and store them keyed by district, so a PIN
   gets its district's own rate. Districts with no page are remembered and never
   retried, which keeps the daily load small.
2. **States** — the national page carries every state's rate in one fetch, so a
   district without a page still resolves to its state's published rate.

Everything is throttled: a small delay between districts, at most a few
connections at once, and a normal browser user-agent — so the source is not
hammered.
"""

import json
import os
import time
from datetime import datetime, timezone
from pathlib import Path

from app import (
    CITY_STATE,
    city_slug,
    district_list,
    fetch_district_prices,
    fetch_goodreturns_prices,
    fetch_national_state_prices,
)

ROOT = Path(__file__).resolve().parent
CACHE_FILE = ROOT / "data" / "price_cache.json"
DISTRICT_PAGES_FILE = ROOT / "data" / "district_pages.json"

# Be a good citizen: pause between districts and cap the run if asked.
DISTRICT_DELAY = float(os.getenv("DISTRICT_FETCH_DELAY_SECONDS", "0.6"))
MAX_DISTRICTS = int(os.getenv("MAX_DISTRICTS", "0"))  # 0 = all districts

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
    # smaller towns (these rely on the state-wise table)
    "Amethi", "Sultanpur", "Prayagraj", "Gorakhpur", "Gaya", "Muzaffarpur", "Ujjain", "Bhilai", "Dhanbad",
    "Haridwar", "Jalandhar", "Thrissur", "Nellore", "Warangal", "Hubballi", "Panaji",
]


def _load(path):
    try:
        data = json.loads(path.read_text())
        return data if isinstance(data, dict) else {}
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {}


def refresh_cities(cache, refreshed_at):
    cities = [x.strip() for x in os.getenv("PRICE_CACHE_CITIES", ",".join(DEFAULT_CITIES)).split(",") if x.strip()]
    updated = 0
    for city in cities:
        state = CITY_STATE.get(city.lower(), "")
        prices = fetch_goodreturns_prices(city, state) or {}
        if prices:
            cache[city_slug(city)] = {
                "city": city, "state": state, "updatedAt": refreshed_at,
                "prices": prices, "observedKeys": sorted(prices),
            }
            updated += 1
    print(f"cities: {updated}/{len(cities)} refreshed")
    return updated


def refresh_districts(cache, pages, refreshed_at):
    districts = district_list()
    if MAX_DISTRICTS:
        districts = districts[:MAX_DISTRICTS]
    added = skipped = 0
    for index, (district, state) in enumerate(districts, start=1):
        slug = city_slug(district)
        entry = pages.get(slug)
        if entry and entry.get("checked") and not entry.get("items"):
            skipped += 1          # known to have no page of its own
            continue
        only = entry.get("items") if entry and entry.get("checked") else None
        prices, items = fetch_district_prices(district, state, only_items=only)
        pages[slug] = {"district": district, "state": state, "items": items, "checked": True}
        if items and prices:
            cache[slug] = {
                "city": district, "state": state, "updatedAt": refreshed_at,
                "prices": prices, "observedKeys": sorted(prices),
            }
            added += 1
        if index % 50 == 0:
            print(f"  districts: {index}/{len(districts)} done ({added} with own pages)")
        if DISTRICT_DELAY:
            time.sleep(DISTRICT_DELAY)
    print(f"districts: {added} stored, {skipped} skipped (no page), {len(districts)} total")
    return added


def main():
    CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
    cache = _load(CACHE_FILE)
    pages = _load(DISTRICT_PAGES_FILE)
    refreshed_at = datetime.now(timezone.utc).isoformat()

    refresh_cities(cache, refreshed_at)
    refresh_districts(cache, pages, refreshed_at)

    # One national page per item carries every state's rate -> pan-India coverage.
    states = fetch_national_state_prices()
    if states:
        cache["_states"] = states
        print("state table:", {k: len(v) for k, v in states.items()})

    CACHE_FILE.write_text(json.dumps(cache, indent=2, sort_keys=True) + "\n")
    DISTRICT_PAGES_FILE.write_text(json.dumps(pages, indent=2, sort_keys=True) + "\n")
    stored = len([k for k in cache if not k.startswith("_")])
    print(f"wrote {CACHE_FILE} ({stored} locations) and {DISTRICT_PAGES_FILE} ({len(pages)} districts checked)")


if __name__ == "__main__":
    main()
