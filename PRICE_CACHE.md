# Scheduled price cache

`.github/workflows/price-cache.yml` runs daily at **06:00 IST** (`00:30 UTC`; GitHub can start cron jobs a few minutes late) and can also be started manually. It runs `backend/refresh_cache.py`, which fetches GoodReturns values for the configured India city list and writes `backend/data/price_cache.json`.

Render is configured with `autoDeploy: true`. When the cache commit changes, Render rebuilds the backend Docker image automatically; the image includes `backend/data/price_cache.json`. A concurrency guard prevents overlapping refresh runs.

## How the backend uses it

`app.fetch_prices(city)` tries the live GoodReturns page first. If that returns nothing, it reads the scheduled cache for the same city and returns `source: scheduled-cache` with the cached `observedAt` timestamp. It never falls back to another city's rate. If neither source has data, `prices` is empty and `source` is `unavailable`.

Only cities that return at least one plausible value are written; an existing entry is kept if a refresh fails.

This is an indicative cache, not an official live price feed. GoodReturns can block automated requests, return stale or mixed-unit results, or change page markup. Exact accuracy requires a licensed provider or an approved API.

To expand the scheduled list, edit `PRICE_CACHE_CITIES` (in the workflow and/or `.env`). To run it immediately, use GitHub Actions → Scheduled Price Cache → Run workflow.
