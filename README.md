# Live Location Based Price

Flutter app for India: location-aware petrol, diesel, LPG, CNG, gold, silver and weather in a compact WhatsApp-inspired UI.

## Run Flutter

```bash
flutter pub get
flutter run
```

The app defaults to the deployed HTTPS backend at `https://live-location-based-price-api.onrender.com`. Override it for local development with `--dart-define=PRICE_API_BASE_URL=http://10.0.2.2:8080`. The app shows an empty state (never fake numbers) when the backend is unavailable. **Do not put provider keys in Flutter.** Keep Google Places, weather and any future market credentials on your server.

> **Platform folders:** `android/` and `ios/` are generated in CI (`flutter create`), not committed. Run `flutter create --platforms=android,ios --project-name live_location_based_price .` once locally before `flutter run`, then add the location permissions and AdMob application IDs listed in `CONFIGURATION.md`.

## Backend

A Flask API is included in [`backend/`](backend/):

```bash
cd backend
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
python app.py
```

Endpoints:

- `GET /health`
- `GET /v1/market?lat=28.61&lng=77.20&city=Delhi`
- `GET /v1/places/search?q=Mumbai`

The backend reads the selected city's GoodReturns page, and falls back to the daily-refreshed `backend/data/price_cache.json` when the live page cannot be read. It never substitutes another city's value or a demo number. Weather uses Open-Meteo by default and needs no key.

## Data accuracy

GoodReturns rates are **indicative**. They are informational and should be checked on the linked city page before any purchase. Do not scrape Google results for production pricing — use a licensed feed or an approved API. See `PRICE_CACHE.md` for the scheduled cache and `CONFIGURATION.md` for release setup.

## AdMob

`AdService` is wired for non-blocking interstitials with a 3-minute tab-switch cooldown. Replace the test ad unit ID in `lib/services/ad_service.dart` and add your Android/iOS AdMob application IDs to the platform manifests before release. Never show ads on every tap.

## Structure

`lib/services` contains APIs, location and ads; `lib/providers` owns state; `lib/models` holds the API contract and shared price ranges; `backend` contains the server API, provider adapters and the scheduled cache refresher. This keeps provider changes independent from the UI.
