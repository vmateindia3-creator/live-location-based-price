import json
import os
from datetime import datetime, timezone
from pathlib import Path

from app import fetch_google_indicative_prices

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
    except (FileNotFoundError, json.JSONDecodeError):
        cache = {}
    refreshed_at = datetime.now(timezone.utc).isoformat()
    for city in cities:
        prices = fetch_google_indicative_prices(city) or {}
        if prices:
            cache[city.lower()] = {"city": city, "updatedAt": refreshed_at, "prices": prices, "observedKeys": sorted(prices)}
            print(f"{city}: {', '.join(sorted(prices))}")
        else:
            print(f"{city}: no usable Google values")
    CACHE_FILE.write_text(json.dumps(cache, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
