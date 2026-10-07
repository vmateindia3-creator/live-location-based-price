# Next steps

## Current mode

The backend is live on Render. Prices come from GoodReturns, with the daily scheduled cache (`backend/data/price_cache.json`) as a fallback when a live page cannot be read. Weather is live via Open-Meteo. When no source has data for a city, the app shows an empty state rather than a placeholder number.

## When a licensed provider is available

A licensed feed would remove the scraping dependency. To add one, extend `fetch_prices()` in `backend/app.py` to query the provider first and fall back to GoodReturns, then set its URL/key in the Render environment. The Flutter app already renders whatever the API returns (`source`, `prices`, `units`) without a UI change.

## Product hardening

- Commit the generated `android/` and `ios/` folders with the location permissions and AdMob application IDs (see `CONFIGURATION.md`).
- Replace the AdMob test unit ID and add a consent flow before release.
- Build and test the app on real phones: location off, slow network, backend down.
- Add source links and units for gold/silver (per gram vs per 10g) before any financial use.
- Add a durable cache (Redis/Postgres) and request monitoring when traffic grows.
