# Live Location Based Price

Flutter app for India: location-aware petrol, diesel, LPG, CNG, gold, silver and weather in a compact WhatsApp-inspired UI.

## Run

```bash
flutter pub get
flutter run --dart-define=PRICE_API_BASE_URL=https://your-api.example.com
```

The app runs with safe demo fallback when the backend is unavailable. **Do not put provider keys in Flutter.** Keep Google Weather/Places, fuel and bullion credentials on your server.

## Backend contract

- `GET /v1/market?lat=28.61&lng=77.20&city=Delhi`
- Response: `{ "updatedAt": "2026-10-05T12:00:00Z", "currency": "INR", "prices": {"petrol": 94.72, "diesel": 87.62, "lpg": 803.0, "cng": 75.09, "gold": 75250.0, "silver": 92500.0}, "weather": {"temperatureC": 31.0, "condition": "Sunny", "humidity": 42, "windKph": 12} }`

A long-term deployment should use a scheduled server-side fetch, source timestamps, provider health checks, caching, rate limits, and a visible “last updated” label. “Google live data” is not a single official price feed; use licensed/current providers behind this API.

## AdMob

`AdService` is wired for non-blocking interstitials. Add your Android/iOS AdMob app IDs in platform manifests and replace test ad unit IDs before release. Never show ads on every tap; the current policy uses a tab-switch cooldown.

## Structure

`lib/services` contains APIs, location and ads; `lib/providers` owns state; `lib/screens` owns pages; `lib/widgets` contains reusable cards. This keeps provider changes independent from UI.
