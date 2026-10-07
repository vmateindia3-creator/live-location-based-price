# Price caching — how the app survives heavy traffic

The API is built so that the number of **users** does not scale the number of
requests to the source site. Three tiers sit in front of it:

| Tier | What | Lifetime | Upstream calls |
|---|---|---|---|
| 1. City cache (in memory) | prices keyed by **city only** | `CACHE_TTL_SECONDS` (default 30 min) | one per city per 30 min, shared by all users |
| 2. Scheduled file cache (`backend/data/price_cache.json`) | ~60 cities, refreshed twice a day | served while younger than `CACHE_MAX_AGE_SECONDS` (36 h) | none |
| 3. Live scrape | only cities missing from tier 2, or older than 36 h | — | throttled (see below) |

Weather is cached separately by rounded coordinates (15 min) and reverse
geocoding for 24 h, so a typical request makes **zero** outbound calls.

## Why the city cache matters

Previously the cache key included the user's coordinates, so every user in a
city produced a different key and the cache barely helped — each request
scraped the source. Keying by city fixes that.

Measured locally: **200 requests across 40 coordinates in one city → 1 price
scrape** (previously 200).

## Upstream protection

Live scraping is a last resort and is rate-limited:

- `SCRAPE_MIN_INTERVAL_SECONDS` (default 1.0) — minimum gap between scrape rounds.
- `SCRAPE_MAX_CONCURRENCY` (default 2) — at most this many rounds in flight.
- `RATE_LIMIT_PER_MIN` (default 120) — per-IP limit on the API itself, so one
  client cannot burn your server's capacity.

## The scheduled refresh

`.github/workflows/price-cache.yml` runs `backend/refresh_cache.py` at **06:00
and 18:00 IST** and commits `backend/data/price_cache.json`. Render
(`autoDeploy: true`) redeploys with the new file, and every user is then served
from it with no live scraping at all.

Only cities that return at least one plausible value are written, and an
existing entry is kept if a refresh fails — so one bad day does not blank the
app.

To change the city list, set `PRICE_CACHE_CITIES` (workflow or `.env`); otherwise
the built-in list of ~60 Indian cities is used.

## Tunables

`CACHE_TTL_SECONDS`, `GEOCODE_TTL_SECONDS`, `WEATHER_TTL_SECONDS`,
`CACHE_MAX_AGE_SECONDS`, `SCRAPE_MIN_INTERVAL_SECONDS`, `SCRAPE_MAX_CONCURRENCY`,
`RATE_LIMIT_PER_MIN` — see `backend/.env.example`.

## Honest limits

This keeps the app fast and reduces load on the source site, but it does not
change the fact that the data comes from a third-party website. For a commercial
launch, use a licensed/official feed or obtain written permission — that is the
only way to be safe at scale, technically and legally.
