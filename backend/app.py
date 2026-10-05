import os
import time
from datetime import datetime, timezone
from threading import Lock

import requests
import re
import json
from pathlib import Path
from dotenv import load_dotenv
from flask import Flask, jsonify, request
from flask_cors import CORS

load_dotenv()
app = Flask(__name__)
CORS(app, resources={r"/v1/*": {"origins": "*"}})

CACHE_TTL = int(os.getenv("CACHE_TTL_SECONDS", "300"))
WEATHER_URL = os.getenv("WEATHER_PROVIDER_URL", "https://api.open-meteo.com/v1/forecast")
cache = {}
cache_lock = Lock()

DEMO_PRICES = {"petrol": 94.72, "diesel": 87.62, "lpg": 803.0, "cng": 75.09, "gold": 75250.0, "silver": 92500.0}
CACHE_FILE = Path(__file__).resolve().parent / "data" / "price_cache.json"
PRICE_RANGES = {
    "petrol": (80.0, 150.0),
    "diesel": (70.0, 150.0),
    "lpg": (700.0, 1200.0),
    "cng": (20.0, 200.0),
    "gold": (50000.0, 200000.0),
    "silver": (50000.0, 300000.0),
}


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


def demo_weather():
    return {"temperatureC": 29.0, "condition": "Partly cloudy", "humidity": 48, "windKph": 11.0}


def fetch_weather(lat, lng):
    try:
        params = {"latitude": lat, "longitude": lng, "current": "temperature_2m,relative_humidity_2m,wind_speed_10m,weather_code"}
        data = requests.get(WEATHER_URL, params=params, timeout=5).json()
        current = data.get("current", {})
        code = int(current.get("weather_code", 3))
        conditions = {0: "Clear", 1: "Mainly clear", 2: "Partly cloudy", 3: "Overcast", 61: "Rain", 71: "Snow", 95: "Thunderstorm"}
        return {"temperatureC": float(current.get("temperature_2m", 29)), "condition": conditions.get(code, "Current weather"), "humidity": int(current.get("relative_humidity_2m", 48)), "windKph": float(current.get("wind_speed_10m", 11))}
    except (requests.RequestException, ValueError, TypeError):
        return demo_weather()


def fetch_prices(city):
    scheduled = load_scheduled_prices(city)
    if scheduled:
        return scheduled, "google-scheduled-cache", set(scheduled)
    provider = os.getenv("PRICE_PROVIDER_URL", "").strip()
    if provider:
        headers = {"Accept": "application/json"}
        api_key = os.getenv("PRICE_PROVIDER_API_KEY", "").strip()
        if api_key:
            headers["Authorization"] = f"Bearer {api_key}"
        try:
            response = requests.get(provider, params={"city": city or "India"}, headers=headers, timeout=7)
            response.raise_for_status()
            prices = response.json().get("prices", {})
            normalized = {key: float(prices[key]) for key in DEMO_PRICES if key in prices}
            if len(normalized) == len(DEMO_PRICES):
                return normalized, "configured-provider", set(normalized)
        except (requests.RequestException, ValueError, TypeError, KeyError):
            pass
    if os.getenv("GOOGLE_SEARCH_ENABLED", "false").lower() == "true":
        search_prices = fetch_google_indicative_prices(city)
        if search_prices:
            merged = DEMO_PRICES.copy()
            merged.update(search_prices)
            source = "google-search-indicative" if len(search_prices) == len(DEMO_PRICES) else "google-search-partial"
            return merged, source, set(search_prices)
    return DEMO_PRICES.copy(), "demo-fallback", set()


def load_scheduled_prices(city):
    try:
        cache = json.loads(CACHE_FILE.read_text())
        item = cache.get((city or "").strip().lower(), {})
        prices = item.get("prices", {})
        return {key: float(value) for key, value in prices.items() if key in DEMO_PRICES}
    except (FileNotFoundError, json.JSONDecodeError, TypeError, ValueError):
        return {}


def fetch_google_indicative_prices(city):
    """Best-effort snippets only. Google Search is not an official price feed."""
    queries = {
        "petrol": f"petrol price in {city} today India",
        "diesel": f"diesel price in {city} today India",
        "lpg": f"LPG cylinder price in {city} today India",
        "cng": f"CNG price in {city} today India",
        "gold": f"gold rate in {city} today India 24 carat 10 gram",
        "silver": f"silver rate in {city} today India per kg",
    }
    headers = {"User-Agent": "Mozilla/5.0 (compatible; LiveLocationPrice/1.0; +https://github.com/vmateindia3-creator/live-location-based-price)"}
    result = {}
    for key, query in queries.items():
        try:
            html = requests.get("https://www.google.com/search", params={"q": query, "hl": "en", "gl": "in"}, headers=headers, timeout=4).text
            text = re.sub(r"<[^>]+>", " ", html)
            text = re.sub(r"\s+", " ", text)
            amounts = re.findall(r"(?:₹|Rs\.?|INR)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)", text, flags=re.I)
            values = [float(value.replace(",", "")) for value in amounts]
            low, high = PRICE_RANGES[key]
            valid = [value for value in values if low <= value <= high]
            if valid:
                result[key] = valid[0]
        except (requests.RequestException, ValueError, TypeError):
            continue
    return result or None


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
    city = request.args.get("city", "India")[:80]
    cache_key = f"market:{round(lat, 2)}:{round(lng, 2)}:{city.lower()}"
    cached = cache_get(cache_key)
    if cached:
        return jsonify(cached)
    prices, source, observed_keys = fetch_prices(city)
    response = {"updatedAt": now_iso(), "currency": "INR", "city": city, "source": source, "warning": "Indicative Google Search result; verify before use" if source.startswith("google-") else None, "prices": prices, "observedKeys": sorted(observed_keys), "weather": fetch_weather(lat, lng)}
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
            response = requests.get("https://maps.googleapis.com/maps/api/place/textsearch/json", params={"query": f"{query}, India", "key": key}, timeout=6).json()
            results = []
            for item in response.get("results", [])[:5]:
                location = item.get("geometry", {}).get("location", {})
                if "lat" in location and "lng" in location:
                    results.append({"name": item.get("name", query), "latitude": location["lat"], "longitude": location["lng"]})
            if results:
                return jsonify({"results": results})
        except (requests.RequestException, ValueError, TypeError):
            pass
    try:
        geo = requests.get("https://geocoding-api.open-meteo.com/v1/search", params={"name": query, "count": 5, "language": "en", "format": "json"}, timeout=6).json()
        results = []
        for item in geo.get("results", []):
            country = item.get("country_code") or item.get("country", "")
            if str(country).upper() in {"IN", "INDIA"}:
                results.append({"name": item.get("name", query), "latitude": item["latitude"], "longitude": item["longitude"]})
        if results:
            return jsonify({"results": results})
    except (requests.RequestException, ValueError, TypeError, KeyError):
        pass
    known = {"delhi": (28.6139, 77.2090), "mumbai": (19.0760, 72.8777), "kolkata": (22.5726, 88.3639), "bengaluru": (12.9716, 77.5946), "chennai": (13.0827, 80.2707)}
    lat, lng = known.get(query.lower(), (20.5937, 78.9629))
    return jsonify({"results": [{"name": query, "latitude": lat, "longitude": lng}]})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")), debug=os.getenv("FLASK_ENV") == "development")
