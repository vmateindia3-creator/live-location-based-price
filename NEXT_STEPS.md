# Next steps

## Current mode

The backend is live on Render. Google Search mode is enabled and shows any extracted category immediately. Missing categories remain fallback values and are visibly labeled in the app.

## When a provider API is available

Add the provider URL and secret in Render environment settings:

```text
PRICE_PROVIDER_URL=...
PRICE_PROVIDER_API_KEY=...
```

After redeploy, verify `/v1/market` returns `source: configured-provider`. The Flutter app already supports this response without a UI change.

## Product hardening

- Add Android/iOS location permission manifests.
- Build and test the Flutter app on a real phone.
- Replace AdMob test IDs before release.
- Add privacy policy and consent messaging.
- Add source links and units for gold/silver (10g vs kg) before financial use.
- Add scheduled caching/monitoring when traffic grows.
