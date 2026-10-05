# Live Location Based Price

Flutter app for India: location-aware petrol, diesel, LPG, CNG, gold, silver and weather in a compact WhatsApp-inspired UI.

## Run Flutter

```bash
flutter pub get
flutter run
```

The app now defaults to the deployed HTTPS backend at `https://live-location-based-price-api.onrender.com`. You can override it for local development with `--dart-define=PRICE_API_BASE_URL=http://10.0.2.2:8080`. The app runs with a safe demo fallback when the backend is unavailable. **Do not put provider keys in Flutter.** Keep Google Places, weather, fuel and bullion credentials on your server.

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

The backend uses Open-Meteo by default for weather and safe demo prices until a licensed market provider is configured. “Google live data” is not one official price feed; do not scrape Google results for production pricing.

## AdMob

`AdService` is wired for non-blocking interstitials. Add your Android/iOS AdMob app IDs in platform manifests and replace test ad unit IDs before release. Never show ads on every tap; the current policy uses a tab-switch cooldown.

## Structure

`lib/services` contains APIs, location and ads; `lib/providers` owns state; `lib/screens` contains future page modules; `lib/widgets` contains future reusable components; `backend` contains the server API and provider adapters. This keeps provider changes independent from UI.
