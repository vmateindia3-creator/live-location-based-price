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

The API does not scrape Google Search. Weather uses Open-Meteo by default. Set `PRICE_PROVIDER_URL` to a licensed Indian fuel/bullion provider or an internal scheduled ingestion service. The provider response must contain:

```json
{"prices":{"petrol":94.72,"diesel":87.62,"lpg":803,"cng":75.09,"gold":75250,"silver":92500}}
```

For a long-running deployment, put this behind HTTPS, add a real database/Redis cache, scheduled refresh jobs, request authentication/rate limits, source attribution and monitoring.

## Google Search indicative mode

Render enables `GOOGLE_SEARCH_ENABLED=true` through `render.yaml`. The backend makes India-specific search queries and only uses extracted values when at least four categories are found. Results are labeled `google-search-indicative` with a `warning`; otherwise the API keeps the safe demo fallback. Google may block automated requests or change markup, so these values must be verified before use.
