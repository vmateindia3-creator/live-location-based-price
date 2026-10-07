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

Price data is fetched from the selected city's GoodReturns pages. Weather uses Open-Meteo by default. The API normalizes fuel to INR/L (CNG INR/kg, LPG INR/cylinder), gold to INR/gram and silver to INR/gram. If a GoodReturns city page cannot be read, that item is omitted rather than replaced with another city's or demo price.

```json
{"prices":{"petrol":111.21,"diesel":97.83,"lpg":941.50,"cng":88.00,"gold":15023,"silver":234.90}}
```

For a long-running deployment, put this behind HTTPS, add a real database/Redis cache, scheduled refresh jobs, request authentication/rate limits, source attribution and monitoring.

GoodReturns values are informational and should be checked on the linked city page before a purchase. The app never silently substitutes a different city, stale cache value or demo value.
