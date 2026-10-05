import os
import time
from datetime import datetime, timezone
from threading import Lock

import requests
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
    provider = os.getenv("PRICE_PROVIDER_URL", "").strip()
    if not provider:
        return DEMO_PRICES.copy(), "demo-fallback"
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
            return normalized, "configured-provider"
    except (requests.RequestException, ValueError, TypeError, KeyError):
        pass
    return DEMO_PRICES.copy(), "demo-fallback"


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
    prices, source = fetch_prices(city)
    response = {"updatedAt": now_iso(), "currency": "INR", "city": city, "source": source, "prices": prices, "weather": fetch_weather(lat, lng)}
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
    known = {"delhi": (28.6139, 77.2090), "mumbai": (19.0760, 72.8777), "kolkata": (22.5726, 88.3639), "bengaluru": (12.9716, 77.5946), "chennai": (13.0827, 80.2707)}
    lat, lng = known.get(query.lower(), (20.5937, 78.9629))
    return jsonify({"results": [{"name": query, "latitude": lat, "longitude": lng}]})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")), debug=os.getenv("FLASK_ENV") == "development")
