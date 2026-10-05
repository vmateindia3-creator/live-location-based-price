# Real rate provider activation

The deployed backend is healthy and weather is live. Market prices intentionally remain `demo-fallback` until a licensed provider is configured.

## Render

In the web service Environment settings, add:

```text
PRICE_PROVIDER_URL=https://your-licensed-provider.example/v1/prices
PRICE_PROVIDER_API_KEY=<secret entered in Render only>
```

The provider must return:

```json
{"prices":{"petrol":94.72,"diesel":87.62,"lpg":803,"cng":75.09,"gold":75250,"silver":92500}}
```

After saving, Render redeploys. Verify `/v1/market` contains `source: configured-provider`.

Do not put secrets in GitHub, Flutter `--dart-define`, screenshots, or chat. Do not scrape Google Search; use a licensed feed or an internal scheduled ingestion service with source attribution and timestamps.
