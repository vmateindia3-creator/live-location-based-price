# Scheduled price cache

The repository now has a GitHub Actions workflow at `.github/workflows/price-cache.yml`. It runs at **06:00 IST** (`00:30 UTC`) and can also be started manually. It fetches best-effort Google Search values for the configured India city list and commits `backend/data/price_cache.json`.

The backend uses a saved city cache first and returns `source: google-scheduled-cache` with `observedKeys`. Values outside conservative Indian retail ranges are discarded. The Flutter app shows only observed keys; it does not present fallback demo values as real rates.

This is an indicative cache, not an official live price feed. Google can block automated searches, return stale or mixed-unit results, or change page markup. Exact accuracy requires a licensed provider or an approved Google API. Firebase/Firestore can be added later as durable storage for arbitrary user-searched cities; the current repository cache covers the configured city list and the backend's best-effort on-demand search.

To expand the scheduled list, edit `PRICE_CACHE_CITIES` in the workflow. To run it immediately, use GitHub Actions → Scheduled Price Cache → Run workflow.
