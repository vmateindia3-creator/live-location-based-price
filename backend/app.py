"""Live Location Based Price — Flask API.

Price data comes from the selected city's GoodReturns page. A scheduled
GitHub Actions job refreshes ``data/price_cache.json``; the API falls back to
that cache when the live page cannot be read, so a rate is never silently
replaced with a different city's value.

Weather uses Open-Meteo by default and needs no key.
"""

import html
import json
import logging
import os
import re
import time
from collections import defaultdict, deque
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from threading import Lock

import requests
from dotenv import load_dotenv
from flask import Flask, jsonify, request
from flask_cors import CORS

load_dotenv()

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger("live-price")

app = Flask(__name__)

# CORS: restrict with ALLOWED_ORIGINS="https://app.example.com,https://other"
_allowed_origins = os.getenv("ALLOWED_ORIGINS", "*").strip()
CORS(app, resources={r"/v1/*": {"origins": _allowed_origins or "*"}})

CACHE_TTL = int(os.getenv("CACHE_TTL_SECONDS", "300"))
WEATHER_URL = os.getenv("WEATHER_PROVIDER_URL", "https://api.open-meteo.com/v1/forecast")
GOODRETURNS = "https://www.goodreturns.in"
CACHE_FILE = Path(__file__).resolve().parent / "data" / "price_cache.json"

# Conservative Indian retail ranges. Anything outside is treated as a parse
# error and dropped rather than shown to the user.
PRICE_RANGES = {
    "petrol": (50.0, 150.0),
    "diesel": (50.0, 150.0),
    "lpg": (300.0, 2500.0),
    "cng": (20.0, 200.0),
    "gold": (5000.0, 30000.0),   # INR per gram
    "silver": (50.0, 1000.0),    # INR per gram
}
PRICE_UNITS = {
    "petrol": "INR/L",
    "diesel": "INR/L",
    "lpg": "INR/cylinder",
    "cng": "INR/kg",
    "gold": "INR/g",
    "silver": "INR/g",
}

# Simple per-IP rate limit (requests per minute). Disable with RATE_LIMIT_PER_MIN=0.
RATE_LIMIT_PER_MIN = int(os.getenv("RATE_LIMIT_PER_MIN", "120"))
_rate_buckets = defaultdict(deque)
_rate_lock = Lock()

cache = {}
cache_lock = Lock()


def sanitize_prices(prices):
    """Keep only plausible INR values; never show an unverified number."""
    clean = {}
    for key, raw_value in (prices or {}).items():
        if key not in PRICE_RANGES:
            continue
        try:
            value = float(raw_value)
        except (TypeError, ValueError):
            continue
        low, high = PRICE_RANGES[key]
        if low <= value <= high:
            clean[key] = round(value, 2)
    return clean


def now_iso():
    return datetime.now(timezone.utc).isoformat()


def cache_get(key):
    with cache_lock:
        item = cache.get(key)
        if item and time.time() - item["saved"] < CACHE_TTL:
            return item["value"]
    return None


def cache_put(key, value):
    with cache_lock:
        cache[key] = {"saved": time.time(), "value": value}


def rate_limited(ip):
    if RATE_LIMIT_PER_MIN <= 0:
        return False
    now = time.time()
    with _rate_lock:
        bucket = _rate_buckets[ip]
        while bucket and now - bucket[0] > 60:
            bucket.popleft()
        if len(bucket) >= RATE_LIMIT_PER_MIN:
            return True
        bucket.append(now)
    return False


def demo_weather():
    return {"temperatureC": 29.0, "condition": "Partly cloudy", "humidity": 48, "windKph": 11.0}


def fetch_weather(lat, lng):
    try:
        params = {"latitude": lat, "longitude": lng, "current": "temperature_2m,relative_humidity_2m,wind_speed_10m,weather_code"}
        response = requests.get(WEATHER_URL, params=params, timeout=5)
        response.raise_for_status()
        current = response.json().get("current", {})
        code = int(current.get("weather_code", 3))
        conditions = {0: "Clear", 1: "Mainly clear", 2: "Partly cloudy", 3: "Overcast", 61: "Rain", 71: "Snow", 95: "Thunderstorm"}
        return {
            "temperatureC": float(current.get("temperature_2m", 29)),
            "condition": conditions.get(code, "Current weather"),
            "humidity": int(current.get("relative_humidity_2m", 48)),
            "windKph": float(current.get("wind_speed_10m", 11)),
        }
    except (requests.RequestException, ValueError, TypeError) as exc:
        logger.warning("weather fetch failed: %s", exc)
        return demo_weather()


def city_slug(city):
    aliases = {
        "bengaluru": "bangalore",
        "bengalore": "bangalore",
        "new delhi": "new-delhi",
        "trivandrum": "trivandrum",
        "thiruvananthapuram": "trivandrum",
    }
    name = (city or "").strip().lower().split(",")[0]
    name = aliases.get(name, name)
    return re.sub(r"[^a-z0-9]+", "-", name).strip("-")


def goodreturns_urls(city):
    slug = city_slug(city)
    suffix = f"-in-{slug}.html" if slug and slug != "india" else ".html"
    return {
        "petrol": f"{GOODRETURNS}/petrol-price{suffix}",
        "diesel": f"{GOODRETURNS}/diesel-price{suffix}",
        "lpg": f"{GOODRETURNS}/lpg-price{suffix}",
        "cng": f"{GOODRETURNS}/cng-price{suffix}",
        "gold": f"{GOODRETURNS}/gold-rates/{slug}.html" if slug and slug != "india" else f"{GOODRETURNS}/gold-rates/",
        "silver": f"{GOODRETURNS}/silver-rates/{slug}.html" if slug and slug != "india" else f"{GOODRETURNS}/silver-rates/",
    }


def goodreturns_text(raw_html):
    text = re.sub(r"<[^>]+>", " ", raw_html)
    return re.sub(r"\s+", " ", html.unescape(text)).strip()


def parse_goodreturns_value(key, text):
    number = r"([0-9][0-9,]*(?:\.[0-9]{1,2})?)"
    patterns = {
        "petrol": rf"Today's petrol price .*?₹\s*{number}\s*per litre",
        "diesel": rf"Today's diesel price .*?₹\s*{number}\s*per litre",
        "lpg": rf"Domestic LPG .*? stands at ₹\s*{number}",
        "cng": rf"CNG price .*?₹\s*{number}\s*(?:per kilogram|per kg|/ Kg)",
        "gold": rf"24K Gold /g\s*₹\s*{number}",
        "silver": rf"Silver /kg\s*₹\s*{number}",
    }
    match = re.search(patterns[key], text, flags=re.I)
    if not match:
        return None
    value = float(match.group(1).replace(",", ""))
    if key == "silver":
        value /= 1000.0  # GoodReturns reports silver per kilogram; we store per gram.
    return value


def fetch_goodreturns_prices(city):
    """Best-effort live scrape of the selected city's GoodReturns pages."""
    urls = goodreturns_urls(city)

    def read(item):
        key, url = item
        try:
            response = requests.get(
                url,
                headers={
                    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/131 Safari/537.36",
                    "Accept-Language": "en-IN,en;q=0.9",
                },
                timeout=8,
            )
            response.raise_for_status()
            return key, parse_goodreturns_value(key, goodreturns_text(response.text))
        except (requests.RequestException, ValueError, TypeError) as exc:
            logger.debug("goodreturns %s failed for %s: %s", key, city, exc)
            return key, None

    with ThreadPoolExecutor(max_workers=6) as pool:
        values = dict(pool.map(read, urls.items()))
    return sanitize_prices({key: value for key, value in values.items() if value is not None})


def load_file_cache():
    try:
        data = json.loads(CACHE_FILE.read_text())
        return data if isinstance(data, dict) else {}
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {}


def load_cached_prices(city):
    """Read the scheduled cache for a city (keyed by slug, falling back to name)."""
    data = load_file_cache()
    slug = city_slug(city)
    entry = data.get(slug) or data.get((city or "").strip().lower())
    if not entry:
        return None
    prices = sanitize_prices(entry.get("prices"))
    if not prices:
        return None
    return {"prices": prices, "updatedAt": entry.get("updatedAt")}


def fetch_prices(city):
    """Live GoodReturns first, then the scheduled cache; never another city's rate."""
    live = fetch_goodreturns_prices(city)
    if live:
        source = "goodreturns" if len(live) == len(PRICE_RANGES) else "goodreturns-partial"
        return live, source, set(live), now_iso()

    cached = load_cached_prices(city)
    if cached:
        return cached["prices"], "scheduled-cache", set(cached["prices"]), cached.get("updatedAt") or now_iso()

    return {}, "unavailable", set(), now_iso()


def resolve_city(lat, lng, requested):
    name = (requested or "").strip()
    if name and name.lower() not in {"india", "current location"}:
        return name
    try:
        response = requests.get(
            "https://nominatim.openstreetmap.org/reverse",
            params={"lat": lat, "lon": lng, "format": "jsonv2", "zoom": 10},
            headers={"User-Agent": "LiveLocationPrice/1.0"},
            timeout=5,
        )
        response.raise_for_status()
        address = response.json().get("address", {})
        return address.get("city") or address.get("town") or address.get("municipality") or address.get("state_district") or name or "India"
    except (requests.RequestException, ValueError, TypeError) as exc:
        logger.debug("reverse geocode failed: %s", exc)
        return name or "India"


def valid_coords(lat, lng):
    return -90 <= lat <= 90 and -180 <= lng <= 180


@app.before_request
def _apply_rate_limit():
    if request.path.startswith("/v1/"):
        ip = request.headers.get("X-Forwarded-For", request.remote_addr or "unknown").split(",")[0].strip()
        if rate_limited(ip):
            return jsonify({"error": "rate limit exceeded"}), 429
    return None


@app.get("/health")
def health():
    return jsonify({"ok": True, "service": "live-location-based-price-api", "time": now_iso()})


@app.get("/v1/market")
def market():
    try:
        lat = float(request.args.get("lat", "20.5937"))
        lng = float(request.args.get("lng", "78.9629"))
    except ValueError:
        return jsonify({"error": "lat and lng must be numbers"}), 400
    if not valid_coords(lat, lng):
        return jsonify({"error": "lat must be -90..90 and lng must be -180..180"}), 400

    city = resolve_city(lat, lng, request.args.get("city", "India")[:80])
    cache_key = f"market:{round(lat, 2)}:{round(lng, 2)}:{city.lower()}"
    cached = cache_get(cache_key)
    if cached:
        return jsonify(cached)

    prices, source, observed_keys, observed_at = fetch_prices(city)
    response = {
        "updatedAt": now_iso(),
        "observedAt": observed_at,
        "currency": "INR",
        "city": city,
        "source": source,
        "warning": "GoodReturns indicative rates; verify on the linked city page" if source.startswith("goodreturns") else ("Scheduled cache value; verify before use" if source == "scheduled-cache" else None),
        "prices": prices,
        "units": {k: PRICE_UNITS[k] for k in prices},
        "observedKeys": sorted(observed_keys),
        "sourceUrls": goodreturns_urls(city),
        "weather": fetch_weather(lat, lng),
    }
    cache_put(cache_key, response)
    return jsonify(response)


@app.get("/v1/places/search")
def places_search():
    query = request.args.get("q", "").strip()
    if not query:
        return jsonify({"results": []})
    # Google Places is optional; keep the key on the server.
    key = os.getenv("GOOGLE_PLACES_API_KEY", "").strip()
    if key:
        try:
            response = requests.get(
                "https://maps.googleapis.com/maps/api/place/textsearch/json",
                params={"query": f"{query}, India", "key": key},
                timeout=6,
            )
            response.raise_for_status()
            results = []
            for item in response.json().get("results", [])[:5]:
                location = item.get("geometry", {}).get("location", {})
                if "lat" in location and "lng" in location:
                    results.append({"name": item.get("name", query), "latitude": location["lat"], "longitude": location["lng"]})
            if results:
                return jsonify({"results": results})
        except (requests.RequestException, ValueError, TypeError) as exc:
            logger.debug("google places failed: %s", exc)
    try:
        geo = requests.get(
            "https://geocoding-api.open-meteo.com/v1/search",
            params={"name": query, "count": 5, "language": "en", "format": "json"},
            timeout=6,
        )
        geo.raise_for_status()
        results = []
        for item in geo.json().get("results", []):
            country = item.get("country_code") or item.get("country", "")
            if str(country).upper() in {"IN", "INDIA"}:
                results.append({"name": item.get("name", query), "latitude": item["latitude"], "longitude": item["longitude"]})
        if results:
            return jsonify({"results": results})
    except (requests.RequestException, ValueError, TypeError, KeyError) as exc:
        logger.debug("open-meteo geocode failed: %s", exc)

    known = {"delhi": (28.6139, 77.2090), "mumbai": (19.0760, 72.8777), "kolkata": (22.5726, 88.3639), "bengaluru": (12.9716, 77.5946), "chennai": (13.0827, 80.2707)}
    lat, lng = known.get(query.lower(), (20.5937, 78.9629))
    return jsonify({"results": [{"name": query, "latitude": lat, "longitude": lng}]})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")), debug=os.getenv("FLASK_ENV") == "development")
