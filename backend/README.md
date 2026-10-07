# Live Location Based Price API

Flask backend for the Flutter app. It keeps provider keys server-side, caches responses, and returns a predictable contract even when an upstream is unavailable.

## Run locally

```bash
cd backend
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
python app.py
```

## Test

Tests are offline and deterministic (no network):

```bash
cd backend
python -m unittest discover -s . -p 'test_*.py'
```

## Deploy on Render

1. Open Render and choose **New → Blueprint**.
2. Connect the GitHub repository `vmateindia3-creator/live-location-based-price`.
3. Render detects the root `render.yaml` and creates `live-location-based-price-api`.
4. Add secret values in the Render environment settings; never commit `.env`.
5. Wait for `/health` to become healthy.
6. Use the generated HTTPS URL as Flutter's `PRICE_API_BASE_URL`.

The repository also contains `backend/Dockerfile` for Railway, Fly.io or any Docker host.

## Endpoints

- `GET /health`
- `GET /v1/market?lat=28.6139&lng=77.2090&city=Delhi`
- `GET /v1/places/search?q=Mumbai`

## Provider policy

Prices come from the selected city's GoodReturns pages. If the live page cannot be read, the API falls back to the daily-refreshed `data/price_cache.json` (`source: scheduled-cache`). It never substitutes a different city's value or a demo number; if neither source has data, `prices` is empty and `source` is `unavailable`. Weather uses Open-Meteo by default.

The API normalizes fuel to INR/L (CNG INR/kg, LPG INR/cylinder), and gold and silver to INR/gram. Ranges outside conservative Indian retail bands are dropped.

```json
{"prices":{"petrol":94.72,"diesel":87.62,"lpg":903.00,"cng":75.09,"gold":10250.00,"silver":128.00},
 "units":{"petrol":"INR/L","gold":"INR/g"},
 "source":"goodreturns","observedKeys":["petrol","diesel","lpg","cng","gold","silver"]}
```

GoodReturns values are informational and should be checked on the linked city page before a purchase.

## Operations

- In-memory cache with `CACHE_TTL_SECONDS` (per worker, cleared on restart).
- Simple per-IP rate limit via `RATE_LIMIT_PER_MIN` (0 disables it).
- Restrict browser origins with `ALLOWED_ORIGINS` in production.

For a long-running deployment, put this behind HTTPS, add a real database/Redis cache, request authentication, source attribution and monitoring.
