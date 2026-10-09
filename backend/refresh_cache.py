"""Refresh the price cache from GoodReturns.

Run by ``.github/workflows/price-cache.yml`` several times a day, and usable
manually.

Two layers, so every PIN code in India resolves to real prices:

1. **Districts** — every PIN code belongs to a district, and GoodReturns has a
   dedicated page for most of India's districts (Gorakhpur, Bhadohi, Faizabad,
   ...). We fetch those and store them keyed by district, so a PIN gets its
   district's own rate.
2. **States** — the national page carries every state's rate in one fetch, so a
   district without a page still resolves to its state's published rate.

Being a good citizen matters more than being fast. This job:

* fetches only a **slice of districts per run** (the least recently updated
  ones), so the whole country is covered over the day without a big burst;
* pauses between districts and keeps only a few connections open;
* **stops early** when the source starts returning nothing, rather than
  hammering a site that is (rightly) pushing back;
* never overwrites a good cache entry with an empty one.
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
    fetch_bankbazaar_lpg,
    fetch_district_prices,
    fetch_goodreturns_prices,
    fetch_national_state_prices,
)

ROOT = Path(__file__).resolve().parent
CACHE_FILE = ROOT / "data" / "price_cache.json"
DISTRICT_PAGES_FILE = ROOT / "data" / "district_pages.json"
LPG_CACHE_FILE = ROOT / "data" / "lpg_cache.json"

# Spread the load: only this many districts per run, oldest first.
MAX_DISTRICTS_PER_RUN = int(os.getenv("MAX_DISTRICTS_PER_RUN", "260"))
# Pause between districts (seconds).
DISTRICT_DELAY = float(os.getenv("DISTRICT_FETCH_DELAY_SECONDS", "1.2"))
# Give up after this many districts in a row return nothing.
BLOCK_ABORT_AFTER = int(os.getenv("BLOCK_ABORT_AFTER", "6"))

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


def _entry(cache, slug, city, state, prices, refreshed_at):
    return {
        "city": city,
        "state": state,
        "updatedAt": refreshed_at,
        "prices": prices,
        "observedKeys": sorted(prices),
    }


def refresh_cities(cache, refreshed_at):
    cities = [x.strip() for x in os.getenv("PRICE_CACHE_CITIES", ",".join(DEFAULT_CITIES)).split(",") if x.strip()]
    updated = 0
    for city in cities:
        state = CITY_STATE.get(city.lower(), "")
        prices = fetch_goodreturns_prices(city, state) or {}
        # Keep whatever we already had if this fetch came back empty.
        if prices:
            cache[city_slug(city)] = _entry(cache, city_slug(city), city, state, prices, refreshed_at)
            updated += 1
        elif not (cache.get(city_slug(city)) or {}).get("prices"):
            updated += 0
        time.sleep(0.4)
    print(f"cities: {updated}/{len(cities)} refreshed")
    return updated


def refresh_districts(cache, pages, refreshed_at):
    districts = district_list()
    # Least recently updated first, so successive runs sweep the whole country.
    districts.sort(key=lambda pair: (pages.get(city_slug(pair[0])) or {}).get("lastFetchedAt") or "")
    if MAX_DISTRICTS_PER_RUN:
        districts = districts[:MAX_DISTRICTS_PER_RUN]

    added = skipped = streak = 0
    for index, (district, state) in enumerate(districts, start=1):
        slug = city_slug(district)
        entry = pages.get(slug) or {}
        if entry.get("checked") and not entry.get("items"):
            skipped += 1          # known to have no page of its own
            continue
        only = entry.get("items") if entry.get("checked") else None
        prices, items = fetch_district_prices(district, state, only_items=only)

        if not prices:
            # The source is pushing back (or this page is gone). Keep the old
            # entry and, if it keeps happening, stop for today.
            streak += 1
            if streak >= BLOCK_ABORT_AFTER:
                print(f"  stopping: {streak} districts in a row returned nothing - source looks blocked")
                break
            continue
        streak = 0

        pages[slug] = {
            "district": district, "state": state, "items": items,
            "checked": True, "lastFetchedAt": refreshed_at,
        }
        cache[slug] = _entry(cache, slug, district, state, prices, refreshed_at)
        added += 1
        if index % 25 == 0:
            print(f"  districts: {index}/{len(districts)} done ({added} updated)")
        if DISTRICT_DELAY:
            time.sleep(DISTRICT_DELAY)

    print(f"districts: {added} updated, {skipped} skipped (no page), {len(districts)} attempted")
    return added


def refresh_lpg(refreshed_at):
    """LPG comes from BankBazaar: one page per state lists every district."""
    table = fetch_bankbazaar_lpg()
    if not table:
        print("lpg: BankBazaar returned nothing - keeping the previous file")
        return 0
    LPG_CACHE_FILE.write_text(json.dumps(table, indent=2, sort_keys=True) + "\n")
    states = {v.get("state") for v in table.values() if isinstance(v, dict)}
    print(f"lpg: {len(table)} districts across {len(states)} states (BankBazaar)")
    return len(table)


def main():
    CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
    cache = _load(CACHE_FILE)
    pages = _load(DISTRICT_PAGES_FILE)
    refreshed_at = datetime.now(timezone.utc).isoformat()

    refresh_cities(cache, refreshed_at)
    refresh_lpg(refreshed_at)
    refresh_districts(cache, pages, refreshed_at)

    # One national page per item carries every state's rate -> pan-India coverage.
    states = fetch_national_state_prices()
    if states:
        cache["_states"] = states
        print("state table:", {k: len(v) for k, v in states.items()})

    CACHE_FILE.write_text(json.dumps(cache, indent=2, sort_keys=True) + "\n")
    DISTRICT_PAGES_FILE.write_text(json.dumps(pages, indent=2, sort_keys=True) + "\n")
    stored = len([k for k in cache if not k.startswith("_")])
    print(f"wrote {CACHE_FILE} ({stored} locations) and {DISTRICT_PAGES_FILE} ({len(pages)} districts)")


if __name__ == "__main__":
    main()
