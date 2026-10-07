"""Live Location Based Price — Flask API.

Designed to serve many users from cache and hit the upstream site as rarely as
possible:

1. **City cache** (in memory, ``CACHE_TTL_SECONDS``): a city is looked up at
   most once per TTL, no matter how many users ask for it.
2. **Scheduled file cache** (``data/price_cache.json``, refreshed daily): served
   directly, with no upstream request at all.
3. **Live scrape** (throttled, last resort): only for a city that is not in the
   file cache, or whose entry is older than ``CACHE_MAX_AGE_SECONDS``.

Reverse geocoding and weather are cached separately, so a request usually makes
zero outbound calls.
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
from threading import BoundedSemaphore, Lock

import requests
from dotenv import load_dotenv
from flask import Flask, jsonify, request
from flask_cors import CORS

load_dotenv()

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger("live-price")

app = Flask(__name__)

_allowed_origins = os.getenv("ALLOWED_ORIGINS", "*").strip()
CORS(app, resources={r"/v1/*": {"origins": _allowed_origins or "*"}})

# Cache lifetimes (seconds).
CACHE_TTL = int(os.getenv("CACHE_TTL_SECONDS", "1800"))          # city prices: 30 min
GEOCODE_TTL = int(os.getenv("GEOCODE_TTL_SECONDS", "86400"))     # reverse geocode: 24 h
WEATHER_TTL = int(os.getenv("WEATHER_TTL_SECONDS", "900"))       # weather: 15 min
CACHE_MAX_AGE = int(os.getenv("CACHE_MAX_AGE_SECONDS", "129600"))  # file cache: serve up to 36 h

# Upstream protection: at most this many scrape rounds in flight, and at least
# this many seconds between the start of two rounds.
SCRAPE_MIN_INTERVAL = float(os.getenv("SCRAPE_MIN_INTERVAL_SECONDS", "1.0"))
SCRAPE_MAX_CONCURRENCY = int(os.getenv("SCRAPE_MAX_CONCURRENCY", "2"))

WEATHER_URL = os.getenv("WEATHER_PROVIDER_URL", "https://api.open-meteo.com/v1/forecast")
GOODRETURNS = "https://www.goodreturns.in"
CACHE_FILE = Path(__file__).resolve().parent / "data" / "price_cache.json"

HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/131 Safari/537.36",
    "Accept-Language": "en-IN,en;q=0.9",
}

PRICE_RANGES = {
    "petrol": (50.0, 150.0),      # INR per litre
    "diesel": (50.0, 150.0),      # INR per litre
    "lpg": (300.0, 2500.0),       # INR per 14.2 kg domestic cylinder
    "cng": (20.0, 200.0),         # INR per kg
    "gold": (5000.0, 30000.0),    # INR per gram
    "silver": (50.0, 1000.0),     # INR per gram
}
PRICE_UNITS = {
    "petrol": "INR/L",
    "diesel": "INR/L",
    "lpg": "INR/cylinder",
    "cng": "INR/kg",
    "gold": "INR/g",
    "silver": "INR/g",
}

# Fallback city table used when reverse geocoding is unavailable.
CITY_COORDS = {
    "Delhi": (28.6139, 77.2090), "New Delhi": (28.6139, 77.2090), "Gurugram": (28.4595, 77.0266),
    "Noida": (28.5355, 77.3910), "Mumbai": (19.0760, 72.8777), "Thane": (19.2183, 72.9781),
    "Navi Mumbai": (19.0330, 73.0297), "Pune": (18.5204, 73.8567), "Nagpur": (21.1458, 79.0882),
    "Kolkata": (22.5726, 88.3639), "Howrah": (22.5958, 88.2636), "Bengaluru": (12.9716, 77.5946),
    "Chennai": (13.0827, 80.2707), "Hyderabad": (17.3850, 78.4867), "Secunderabad": (17.4399, 78.4983),
    "Ahmedabad": (23.0225, 72.5714), "Surat": (21.1702, 72.8311), "Vadodara": (22.3072, 73.1812),
    "Jaipur": (26.9124, 75.7873), "Lucknow": (26.8467, 80.9462), "Kanpur": (26.4499, 80.3319),
    "Varanasi": (25.3176, 82.9739), "Patna": (25.5941, 85.1376), "Bhopal": (23.2599, 77.4126),
    "Indore": (22.7196, 75.8577), "Raipur": (21.2514, 81.6296), "Chandigarh": (30.7333, 76.7794),
    "Ludhiana": (30.9010, 75.8573), "Amritsar": (31.6340, 74.8723), "Dehradun": (30.3165, 78.0322),
    "Kochi": (9.9312, 76.2673), "Thiruvananthapuram": (8.5241, 76.9366), "Kozhikode": (11.2588, 75.7804),
    "Coimbatore": (11.0168, 76.9558), "Madurai": (9.9252, 78.1198), "Visakhapatnam": (17.6868, 83.2185),
    "Vijayawada": (16.5062, 80.6480), "Bhubaneswar": (20.2961, 85.8245), "Guwahati": (26.1445, 91.7362),
    "Ranchi": (23.3441, 85.3096), "Jodhpur": (26.2389, 73.0243), "Agra": (27.1767, 78.0081),
    "Goa": (15.2993, 74.1240), "Panaji": (15.4909, 73.8278), "Mysuru": (12.2958, 76.6394),
}

# Per-IP request limit (requests per minute). 0 disables it.
RATE_LIMIT_PER_MIN = int(os.getenv("RATE_LIMIT_PER_MIN", "120"))
_rate_buckets = defaultdict(deque)
_rate_lock = Lock()

cache = {}
cache_lock = Lock()

_scrape_sem = BoundedSemaphore(SCRAPE_MAX_CONCURRENCY)
_scrape_lock = Lock()
_last_scrape = 0.0


def sanitize_prices(prices):
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


def normalize_value(key, value):
    """Convert a parsed value to the app's single unit for that item."""
    if key == "silver" and value > PRICE_RANGES["silver"][1]:
        value /= 1000.0  # quoted per kilogram
    if key == "gold" and value > PRICE_RANGES["gold"][1]:
        value /= 10.0  # quoted per 10 grams
    return value


def now_iso():
    return datetime.now(timezone.utc).isoformat()


def age_seconds(iso):
    try:
        dt = datetime.fromisoformat(str(iso).replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return max(0.0, (datetime.now(timezone.utc) - dt).total_seconds())
    except (TypeError, ValueError):
        return float("inf")


def cache_get(key):
    with cache_lock:
        item = cache.get(key)
        if item and time.time() - item["saved"] < item.get("ttl", CACHE_TTL):
            return item["value"]
    return None


def cache_put(key, value, ttl=None):
    with cache_lock:
        cache[key] = {"saved": time.time(), "value": value, "ttl": ttl or CACHE_TTL}


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


def weather_for(lat, lng):
    key = f"weather:{round(lat, 2)}:{round(lng, 2)}"
    hit = cache_get(key)
    if hit is not None:
        return hit
    value = fetch_weather(lat, lng)
    cache_put(key, value, ttl=WEATHER_TTL)
    return value


def city_slug(city):
    aliases = {
        "bengaluru": "bangalore",
        "bengalore": "bangalore",
        "new delhi": "new-delhi",
        "trivandrum": "trivandrum",
        "thiruvananthapuram": "trivandrum",
        "gurugram": "gurgaon",
        "mysuru": "mysore",
        "navi mumbai": "navi-mumbai",
    }
    name = (city or "").strip().lower().split(",")[0]
    name = aliases.get(name, name)
    return re.sub(r"[^a-z0-9]+", "-", name).strip("-")


def candidate_urls(city):
    """Per-item GoodReturns URLs to try in order (city page, then national)."""
    slug = city_slug(city)
    has_city = bool(slug) and slug != "india"
    suffix = f"-in-{slug}.html" if has_city else ".html"
    urls = {
        "petrol": [f"{GOODRETURNS}/petrol-price{suffix}"],
        "diesel": [f"{GOODRETURNS}/diesel-price{suffix}"],
        "lpg": [f"{GOODRETURNS}/lpg-price{suffix}"],
        "cng": [f"{GOODRETURNS}/cng-price{suffix}"],
        "gold": [f"{GOODRETURNS}/gold-rates/{slug}.html" if has_city else f"{GOODRETURNS}/gold-rates/"],
        "silver": [f"{GOODRETURNS}/silver-rates/{slug}.html" if has_city else f"{GOODRETURNS}/silver-rates/"],
    }
    if has_city:
        urls["gold"].append(f"{GOODRETURNS}/gold-rates/")
        urls["silver"].append(f"{GOODRETURNS}/silver-rates/")
    return urls


def goodreturns_urls(city):
    return {key: value[0] for key, value in candidate_urls(city).items()}


def goodreturns_text(raw_html):
    text = re.sub(r"<[^>]+>", " ", raw_html)
    return re.sub(r"\s+", " ", html.unescape(text)).strip()


def parse_goodreturns_value(key, text):
    number = r"([0-9][0-9,]*(?:\.[0-9]{1,2})?)"
    patterns = {
        "petrol": [
            rf"Today's petrol price .*?₹\s*{number}\s*per litre",
            rf"[Pp]etrol [Pp]rice.*?₹\s*{number}\s*(?:per litre|/ ?litre|/ ?L)",
        ],
        "diesel": [
            rf"Today's diesel price .*?₹\s*{number}\s*per litre",
            rf"[Dd]iesel [Pp]rice.*?₹\s*{number}\s*(?:per litre|/ ?litre|/ ?L)",
        ],
        "lpg": [
            rf"Domestic LPG .*? stands at ₹\s*{number}",
            rf"LPG.*?₹\s*{number}\s*(?:per cylinder|/ ?cylinder)",
        ],
        "cng": [
            rf"CNG price .*?₹\s*{number}\s*(?:per kilogram|per kg|/ Kg)",
            rf"CNG.*?₹\s*{number}\s*(?:per kg|/ ?kg)",
        ],
        "gold": [
            rf"24K Gold /g\s*₹\s*{number}",
            rf"Gold ?/? ?g\s*₹\s*{number}",
            rf"24 ?[Kk] Gold.*?₹\s*{number}",
        ],
        "silver": [
            rf"Silver /kg\s*₹\s*{number}",
            rf"Silver ?/? ?kg\s*₹\s*{number}",
            rf"Silver.*?₹\s*{number}",
        ],
    }
    for pattern in patterns[key]:
        match = re.search(pattern, text, flags=re.I)
        if match:
            return normalize_value(key, float(match.group(1).replace(",", "")))
    return None


def fetch_goodreturns_prices(city):
    """Best-effort live scrape of the selected city's GoodReturns pages."""
    urls = candidate_urls(city)

    def read(item):
        key, candidates = item
        for url in candidates:
            try:
                response = requests.get(url, headers=HEADERS, timeout=8)
                response.raise_for_status()
                value = parse_goodreturns_value(key, goodreturns_text(response.text))
                if value is not None:
                    return key, value
            except (requests.RequestException, ValueError, TypeError) as exc:
                logger.debug("goodreturns %s failed for %s (%s): %s", key, city, url, exc)
        return key, None

    with ThreadPoolExecutor(max_workers=6) as pool:
        values = dict(pool.map(read, urls.items()))
    return sanitize_prices({key: value for key, value in values.items() if value is not None})


def scrape_throttled(city):
    """Live scrape, but never more than a couple at once and spaced out."""
    global _last_scrape
    with _scrape_sem:
        with _scrape_lock:
            wait = SCRAPE_MIN_INTERVAL - (time.time() - _last_scrape)
            if wait > 0:
                time.sleep(wait)
            _last_scrape = time.time()
        return fetch_goodreturns_prices(city)


def load_file_cache():
    try:
        data = json.loads(CACHE_FILE.read_text())
        return data if isinstance(data, dict) else {}
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {}


def load_cached_prices(city):
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
    """Scheduled cache first (no upstream call), then a throttled live scrape."""
    cached = load_cached_prices(city)
    if cached and age_seconds(cached.get("updatedAt")) <= CACHE_MAX_AGE:
        return cached["prices"], "scheduled-cache", set(cached["prices"]), cached.get("updatedAt") or now_iso()

    live = scrape_throttled(city)
    if live:
        source = "goodreturns" if len(live) == len(PRICE_RANGES) else "goodreturns-partial"
        return live, source, set(live), now_iso()

    if cached:  # stale is better than nothing
        return cached["prices"], "scheduled-cache-stale", set(cached["prices"]), cached.get("updatedAt") or now_iso()

    return {}, "unavailable", set(), now_iso()


def cached_prices(city):
    """One upstream lookup per city per CACHE_TTL, shared by all users."""
    key = f"prices:{city.strip().lower()}"
    hit = cache_get(key)
    if hit is not None:
        return hit
    result = fetch_prices(city)
    cache_put(key, result)
    return result


def nearest_city(lat, lng):
    best = None
    best_distance = float("inf")
    for name, (clat, clng) in CITY_COORDS.items():
        distance = (clat - lat) ** 2 + (clng - lng) ** 2
        if distance < best_distance:
            best_distance = distance
            best = name
    return best


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
        found = address.get("city") or address.get("town") or address.get("municipality") or address.get("state_district")
        if found:
            return found
    except (requests.RequestException, ValueError, TypeError) as exc:
        logger.debug("reverse geocode failed: %s", exc)
    return nearest_city(lat, lng) or name or "India"


def resolve_city_cached(lat, lng, requested):
    name = (requested or "").strip()
    if name and name.lower() not in {"india", "current location"}:
        return name
    key = f"geo:{round(lat, 2)}:{round(lng, 2)}"
    hit = cache_get(key)
    if hit:
        return hit
    city = resolve_city(lat, lng, requested)
    cache_put(key, city, ttl=GEOCODE_TTL)
    return city


def valid_coords(lat, lng):
    return -90 <= lat <= 90 and -180 <= lng <= 180


@app.before_request
def _apply_rate_limit():
    if request.path.startswith("/v1/"):
        ip = request.headers.get("X-Forwarded-For", request.remote_addr or "unknown").split(",")[0].strip()
        if rate_limited(ip):
            return jsonify({"error": "rate limit exceeded"}), 429
    return None


@app.after_request
def _security_headers(resp):
    resp.headers.setdefault("X-Content-Type-Options", "nosniff")
    resp.headers.setdefault("X-Frame-Options", "DENY")
    resp.headers.setdefault("Referrer-Policy", "no-referrer")
    resp.headers.setdefault("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
    resp.headers.setdefault("Cache-Control", "no-store")
    resp.headers["Server"] = "locarate"
    return resp


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

    city = resolve_city_cached(lat, lng, request.args.get("city", "India")[:80])
    prices, source, observed_keys, observed_at = cached_prices(city)
    response = {
        "updatedAt": now_iso(),
        "observedAt": observed_at,
        "currency": "INR",
        "city": city,
        "source": source,
        "warning": "Indicative rates; verify before purchase" if prices else None,
        "prices": prices,
        "units": {k: PRICE_UNITS[k] for k in prices},
        "observedKeys": sorted(observed_keys),
        "sourceUrls": goodreturns_urls(city),
        "weather": weather_for(lat, lng),
    }
    return jsonify(response)


@app.get("/v1/places/search")
def places_search():
    query = request.args.get("q", "").strip()
    if not query:
        return jsonify({"results": []})
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
