"""Live Location Based Price — Flask API.

Price data comes from GoodReturns. The tricky part is that GoodReturns only has
dedicated pages for bigger cities: for a smaller town the city URL quietly
returns the generic "Price in India" page, whose headline figure is **Mumbai's**
rate. Blindly reading that headline is what made every town show Mumbai prices.

So for fuel we resolve, in order:
  1. the city's row in the page's "Metro Cities & State Capitals" table,
  2. the **state's** row in the "State-Wise" table,
  3. only then the headline (marked as approximate).

Gold and silver are effectively national rates, so their city page is used
directly with a national fallback.

Caching keeps the number of users from scaling the requests to the source:
a city is looked up at most once per CACHE_TTL, the scheduled file cache is
served without any upstream call, and any live scrape is throttled.
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
WEATHER_TTL = int(os.getenv("WEATHER_TTL_SECONDS", "900"))       # weather: 15 min (fresher than hourly)
CACHE_MAX_AGE = int(os.getenv("CACHE_MAX_AGE_SECONDS", "129600"))  # file cache: serve up to 36 h

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

# Cities that appear in GoodReturns' metro/state-capital table, mapped to the
# name used there.
CITY_TABLE_ALIASES = {
    "new delhi": "New Delhi", "delhi": "New Delhi",
    "gurugram": "Gurgaon", "gurgaon": "Gurgaon",
    "noida": "Noida",
    "mumbai": "Mumbai", "thane": "Mumbai", "navi mumbai": "Mumbai",
    "kolkata": "Kolkata", "howrah": "Kolkata",
    "chennai": "Chennai",
    "hyderabad": "Hyderabad", "secunderabad": "Hyderabad",
    "bengaluru": "Bangalore", "bangalore": "Bangalore",
    "bhubaneswar": "Bhubaneswar", "cuttack": "Bhubaneswar",
    "chandigarh": "Chandigarh",
    "jaipur": "Jaipur",
    "lucknow": "Lucknow",
    "patna": "Patna",
    "thiruvananthapuram": "Thiruvananthapuram", "trivandrum": "Thiruvananthapuram",
}

# name -> (lat, lng, state). Used for nearest-city fallback and for the
# state-wise lookup when reverse geocoding is unavailable.
CITY_COORDS = {
    "Amethi": (26.1536, 81.8108, "Uttar Pradesh"),
    "Sultanpur": (26.2649, 82.0727, "Uttar Pradesh"),
    "Delhi": (28.6139, 77.2090, "Delhi"),
    "New Delhi": (28.6139, 77.2090, "Delhi"),
    "Gurugram": (28.4595, 77.0266, "Haryana"),
    "Faridabad": (28.4089, 77.3178, "Haryana"),
    "Noida": (28.5355, 77.3910, "Uttar Pradesh"),
    "Ghaziabad": (28.6692, 77.4538, "Uttar Pradesh"),
    "Mumbai": (19.0760, 72.8777, "Maharashtra"),
    "Thane": (19.2183, 72.9781, "Maharashtra"),
    "Navi Mumbai": (19.0330, 73.0297, "Maharashtra"),
    "Pune": (18.5204, 73.8567, "Maharashtra"),
    "Nagpur": (21.1458, 79.0882, "Maharashtra"),
    "Nashik": (19.9975, 73.7898, "Maharashtra"),
    "Aurangabad": (19.8762, 75.3433, "Maharashtra"),
    "Kolhapur": (16.7050, 74.2433, "Maharashtra"),
    "Solapur": (17.6599, 75.9064, "Maharashtra"),
    "Kolkata": (22.5726, 88.3639, "West Bengal"),
    "Howrah": (22.5958, 88.2636, "West Bengal"),
    "Siliguri": (26.7271, 88.3953, "West Bengal"),
    "Bengaluru": (12.9716, 77.5946, "Karnataka"),
    "Mysuru": (12.2958, 76.6394, "Karnataka"),
    "Mangaluru": (12.9141, 74.8560, "Karnataka"),
    "Hubballi": (15.3647, 75.1240, "Karnataka"),
    "Chennai": (13.0827, 80.2707, "Tamil Nadu"),
    "Coimbatore": (11.0168, 76.9558, "Tamil Nadu"),
    "Madurai": (9.9252, 78.1198, "Tamil Nadu"),
    "Tiruchirappalli": (10.7905, 78.7047, "Tamil Nadu"),
    "Salem": (11.6643, 78.1460, "Tamil Nadu"),
    "Hyderabad": (17.3850, 78.4867, "Telangana"),
    "Secunderabad": (17.4399, 78.4983, "Telangana"),
    "Warangal": (17.9689, 79.5941, "Telangana"),
    "Ahmedabad": (23.0225, 72.5714, "Gujarat"),
    "Surat": (21.1702, 72.8311, "Gujarat"),
    "Vadodara": (22.3072, 73.1812, "Gujarat"),
    "Rajkot": (22.3039, 70.8022, "Gujarat"),
    "Jamnagar": (22.4707, 70.0577, "Gujarat"),
    "Gandhinagar": (23.2156, 72.6369, "Gujarat"),
    "Jaipur": (26.9124, 75.7873, "Rajasthan"),
    "Jodhpur": (26.2389, 73.0243, "Rajasthan"),
    "Udaipur": (24.5854, 73.7125, "Rajasthan"),
    "Kota": (25.2138, 75.8648, "Rajasthan"),
    "Ajmer": (26.4499, 74.6399, "Rajasthan"),
    "Lucknow": (26.8467, 80.9462, "Uttar Pradesh"),
    "Kanpur": (26.4499, 80.3319, "Uttar Pradesh"),
    "Varanasi": (25.3176, 82.9739, "Uttar Pradesh"),
    "Agra": (27.1767, 78.0081, "Uttar Pradesh"),
    "Meerut": (28.9845, 77.7064, "Uttar Pradesh"),
    "Prayagraj": (25.4358, 81.8463, "Uttar Pradesh"),
    "Gorakhpur": (26.7606, 83.3732, "Uttar Pradesh"),
    "Patna": (25.5941, 85.1376, "Bihar"),
    "Gaya": (24.7955, 85.0002, "Bihar"),
    "Muzaffarpur": (26.1209, 85.3647, "Bihar"),
    "Bhopal": (23.2599, 77.4126, "Madhya Pradesh"),
    "Indore": (22.7196, 75.8577, "Madhya Pradesh"),
    "Gwalior": (26.2183, 78.1828, "Madhya Pradesh"),
    "Jabalpur": (23.1815, 79.9864, "Madhya Pradesh"),
    "Ujjain": (23.1793, 75.7849, "Madhya Pradesh"),
    "Raipur": (21.2514, 81.6296, "Chhattisgarh"),
    "Bhilai": (21.1938, 81.3509, "Chhattisgarh"),
    "Ranchi": (23.3441, 85.3096, "Jharkhand"),
    "Jamshedpur": (22.8046, 86.2029, "Jharkhand"),
    "Dhanbad": (23.7957, 86.4304, "Jharkhand"),
    "Bhubaneswar": (20.2961, 85.8245, "Odisha"),
    "Cuttack": (20.4625, 85.8830, "Odisha"),
    "Chandigarh": (30.7333, 76.7794, "Chandigarh"),
    "Ludhiana": (30.9010, 75.8573, "Punjab"),
    "Amritsar": (31.6340, 74.8723, "Punjab"),
    "Jalandhar": (31.3260, 75.5762, "Punjab"),
    "Dehradun": (30.3165, 78.0322, "Uttarakhand"),
    "Haridwar": (29.9457, 78.1642, "Uttarakhand"),
    "Shimla": (31.1048, 77.1734, "Himachal Pradesh"),
    "Jammu": (32.7266, 74.8570, "Jammu & Kashmir"),
    "Srinagar": (34.0837, 74.7973, "Jammu & Kashmir"),
    "Guwahati": (26.1445, 91.7362, "Assam"),
    "Kochi": (9.9312, 76.2673, "Kerala"),
    "Thiruvananthapuram": (8.5241, 76.9366, "Kerala"),
    "Kozhikode": (11.2588, 75.7804, "Kerala"),
    "Thrissur": (10.5276, 76.2144, "Kerala"),
    "Visakhapatnam": (17.6868, 83.2185, "Andhra Pradesh"),
    "Vijayawada": (16.5062, 80.6480, "Andhra Pradesh"),
    "Guntur": (16.3067, 80.4365, "Andhra Pradesh"),
    "Tirupati": (13.6288, 79.4192, "Andhra Pradesh"),
    "Nellore": (14.4426, 79.9865, "Andhra Pradesh"),
    "Goa": (15.2993, 74.1240, "Goa"),
    "Panaji": (15.4909, 73.8278, "Goa"),
}

CITY_STATE = {name.lower(): state for name, (_, _, state) in CITY_COORDS.items()}

RATE_LIMIT_PER_MIN = int(os.getenv("RATE_LIMIT_PER_MIN", "120"))
_rate_buckets = defaultdict(deque)
_rate_lock = Lock()

cache = {}
cache_lock = Lock()

_scrape_sem = BoundedSemaphore(SCRAPE_MAX_CONCURRENCY)
_scrape_lock = Lock()
_last_scrape = 0.0


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #

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
        params = {
            "latitude": lat,
            "longitude": lng,
            "current": "temperature_2m,relative_humidity_2m,wind_speed_10m,weather_code",
            "timezone": "auto",
        }
        response = requests.get(WEATHER_URL, params=params, timeout=6)
        response.raise_for_status()
        current = response.json().get("current", {})
        code = int(current.get("weather_code", 3))
        conditions = {
            0: "Clear", 1: "Mainly clear", 2: "Partly cloudy", 3: "Overcast",
            45: "Fog", 48: "Fog", 51: "Drizzle", 53: "Drizzle", 55: "Drizzle",
            61: "Light rain", 63: "Rain", 65: "Heavy rain", 71: "Snow", 73: "Snow",
            80: "Showers", 81: "Showers", 82: "Heavy showers", 95: "Thunderstorm",
            96: "Thunderstorm", 99: "Thunderstorm",
        }
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


# --------------------------------------------------------------------------- #
# location resolution (city + state)
# --------------------------------------------------------------------------- #

def nearest_city(lat, lng):
    """Closest known city -> (name, state)."""
    best = None
    best_distance = float("inf")
    for name, (clat, clng, state) in CITY_COORDS.items():
        distance = (clat - lat) ** 2 + (clng - lng) ** 2
        if distance < best_distance:
            best_distance = distance
            best = (name, state)
    return best


def reverse_geocode(lat, lng):
    """(city, state) from coordinates, or (None, None)."""
    try:
        response = requests.get(
            "https://nominatim.openstreetmap.org/reverse",
            params={"lat": lat, "lon": lng, "format": "jsonv2", "zoom": 10, "addressdetails": 1},
            headers={"User-Agent": "LiveLocationPrice/1.0"},
            timeout=6,
        )
        response.raise_for_status()
        address = response.json().get("address", {})
        city = (address.get("city") or address.get("town") or address.get("municipality")
                or address.get("county") or address.get("state_district") or address.get("village"))
        state = address.get("state")
        return city, state
    except (requests.RequestException, ValueError, TypeError) as exc:
        logger.debug("reverse geocode failed: %s", exc)
        return None, None


def resolve_location(lat, lng, requested):
    """Resolve (city, state) for a request.

    A searched city name is trusted for the city, but the state is still taken
    from the coordinates so the state-wise table can be used for small towns.
    """
    key = f"geo:{round(lat, 2)}:{round(lng, 2)}"
    cached = cache_get(key)
    if cached:
        geo_city, geo_state = cached
    else:
        geo_city, geo_state = reverse_geocode(lat, lng)
        if not geo_city and not geo_state:
            fallback = nearest_city(lat, lng)
            if fallback:
                geo_city, geo_state = fallback
        cache_put(key, (geo_city, geo_state), ttl=GEOCODE_TTL)

    name = (requested or "").strip()
    if name and name.lower() not in {"india", "current location"}:
        city = name
        state = geo_state or CITY_STATE.get(name.lower(), "")
    else:
        city = geo_city or "India"
        state = geo_state or ""

    if not state:
        state = CITY_STATE.get(city.lower(), "")
    return city, state


def valid_coords(lat, lng):
    return -90 <= lat <= 90 and -180 <= lng <= 180


# --------------------------------------------------------------------------- #
# GoodReturns fetching and parsing
# --------------------------------------------------------------------------- #

def candidate_urls(city):
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


def section(text, start_marker, end_marker=None):
    """Slice the page text between two markers."""
    i = text.find(start_marker)
    if i < 0:
        return ""
    i += len(start_marker)
    if end_marker:
        j = text.find(end_marker, i)
        if j >= 0:
            return text[i:j]
    return text[i:]


def table_value(text, label):
    """First number that follows `label` in a table row."""
    if not text or not label:
        return None
    pattern = rf"{re.escape(label)}\b\s*[|\-]?\s*₹?\s*([0-9][0-9,]*(?:\.[0-9]{{1,2}})?)"
    match = re.search(pattern, text, flags=re.I)
    if not match:
        return None
    return float(match.group(1).replace(",", ""))


HEADLINE_PATTERNS = {
    "petrol": [rf"Today's petrol price .*?₹\s*([0-9][0-9,]*(?:\.[0-9]{{1,2}})?)\s*per litre"],
    "diesel": [rf"Today's diesel price .*?₹\s*([0-9][0-9,]*(?:\.[0-9]{{1,2}})?)\s*per litre"],
    "lpg": [rf"Domestic LPG \(14\.2 kg\) cylinder price .*?₹\s*([0-9][0-9,]*(?:\.[0-9]{{1,2}})?)"],
    "cng": [rf"CNG price .*?₹\s*([0-9][0-9,]*(?:\.[0-9]{{1,2}})?)\s*(?:per kilogram|per kg)"],
}

METAL_PATTERNS = {
    "gold": [
        rf"24K Gold /g\s*₹\s*([0-9][0-9,]*(?:\.[0-9]{{1,2}})?)",
        rf"gold price in .*? stands at ₹\s*([0-9][0-9,]*(?:\.[0-9]{{1,2}})?)\s*per gram",
    ],
    "silver": [
        rf"Silver /kg\s*₹\s*([0-9][0-9,]*(?:\.[0-9]{{1,2}})?)",
        rf"silver price in .*? stands at ₹\s*([0-9][0-9,]*(?:\.[0-9]{{1,2}})?)\s*per gram",
    ],
}

# GoodReturns spells some states differently from Nominatim.
STATE_ALIASES = {
    "chhattisgarh": "Chhatisgarh",
    "orissa": "Odisha",
    "uttaranchal": "Uttarakhand",
    "pondicherry": "Pondicherry",
    "puducherry": "Pondicherry",
    "nct of delhi": "Delhi",
    "jammu and kashmir": "Jammu & Kashmir",
}


def state_labels(state):
    """Spellings to try for the state-wise table row."""
    if not state:
        return []
    labels = []
    alias = STATE_ALIASES.get(state.strip().lower())
    if alias:
        labels.append(alias)
    labels.append(state.strip())
    return labels


CITY_HEADLINE_LABELS = {
    "petrol": "Today's petrol price in {city}",
    "diesel": "Today's diesel price in {city}",
    "lpg": "Domestic LPG (14.2 kg) cylinder price in {city}",
    "cng": "CNG price in {city}",
}


def city_headline_value(key, text, city):
    """A town with its own page quotes its own rate in the headline."""
    if not city or city.strip().lower() in {"india", "current location"}:
        return None
    label = CITY_HEADLINE_LABELS[key].format(city=re.escape(city.strip()))
    pattern = label + r"\b.*?₹\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)"
    match = re.search(pattern, text[:3000], flags=re.I)
    if not match:
        return None
    return normalize_value(key, float(match.group(1).replace(",", "")))


def parse_fuel_value(key, text, city, state):
    """City table row -> city headline -> state row -> generic headline.

    Never silently returns Mumbai's headline for a different city.
    """
    metro = section(text, "Metro Cities & State Capitals", "State-Wise")
    city_label = CITY_TABLE_ALIASES.get((city or "").strip().lower())
    if city_label:
        value = table_value(metro, city_label)
        if value is not None:
            return normalize_value(key, value)

    value = city_headline_value(key, text, city)
    if value is not None:
        return value

    state_section = section(text, "State-Wise", "Crude Oil")
    for label in state_labels(state):
        value = table_value(state_section, label)
        if value is not None:
            return normalize_value(key, value)

    # CNG genuinely differs per city; a missing city row must not fall back to
    # another city's rate.
    if key == "cng":
        return None

    for pattern in HEADLINE_PATTERNS[key]:
        match = re.search(pattern, text, flags=re.I)
        if match:
            return normalize_value(key, float(match.group(1).replace(",", "")))
    return None


def parse_metal_value(key, text):
    for pattern in METAL_PATTERNS[key]:
        match = re.search(pattern, text, flags=re.I)
        if match:
            return normalize_value(key, float(match.group(1).replace(",", "")))
    return None


def parse_goodreturns_value(key, text, city="", state=""):
    """Backwards-compatible single entry point."""
    if key in ("gold", "silver"):
        return parse_metal_value(key, text)
    return parse_fuel_value(key, text, city, state)


def fetch_goodreturns_prices(city, state=""):
    urls = candidate_urls(city)

    def read(item):
        key, candidates = item
        for url in candidates:
            try:
                response = requests.get(url, headers=HEADERS, timeout=8)
                response.raise_for_status()
                value = parse_goodreturns_value(key, goodreturns_text(response.text), city, state)
                if value is not None:
                    return key, value
            except (requests.RequestException, ValueError, TypeError) as exc:
                logger.debug("goodreturns %s failed for %s (%s): %s", key, city, url, exc)
        return key, None

    with ThreadPoolExecutor(max_workers=6) as pool:
        values = dict(pool.map(read, urls.items()))
    return sanitize_prices({key: value for key, value in values.items() if value is not None})


def scrape_throttled(city, state=""):
    global _last_scrape
    with _scrape_sem:
        with _scrape_lock:
            wait = SCRAPE_MIN_INTERVAL - (time.time() - _last_scrape)
            if wait > 0:
                time.sleep(wait)
            _last_scrape = time.time()
        return fetch_goodreturns_prices(city, state)


# --------------------------------------------------------------------------- #
# caching / price assembly
# --------------------------------------------------------------------------- #

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


def fetch_prices(city, state=""):
    cached = load_cached_prices(city)
    if cached and age_seconds(cached.get("updatedAt")) <= CACHE_MAX_AGE:
        return cached["prices"], "scheduled-cache", set(cached["prices"]), cached.get("updatedAt") or now_iso()

    live = scrape_throttled(city, state)
    if live:
        source = "goodreturns" if len(live) == len(PRICE_RANGES) else "goodreturns-partial"
        return live, source, set(live), now_iso()

    if cached:
        return cached["prices"], "scheduled-cache-stale", set(cached["prices"]), cached.get("updatedAt") or now_iso()

    return {}, "unavailable", set(), now_iso()


def cached_prices(city, state=""):
    key = f"prices:{city.strip().lower()}|{(state or '').strip().lower()}"
    hit = cache_get(key)
    if hit is not None:
        return hit
    result = fetch_prices(city, state)
    cache_put(key, result)
    return result


# --------------------------------------------------------------------------- #
# routes
# --------------------------------------------------------------------------- #

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

    city, state = resolve_location(lat, lng, request.args.get("city", "India")[:80])
    prices, source, observed_keys, observed_at = cached_prices(city, state)
    response = {
        "updatedAt": now_iso(),
        "observedAt": observed_at,
        "currency": "INR",
        "city": city,
        "state": state,
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
