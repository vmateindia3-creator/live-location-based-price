# Release configuration

1. Add `PRICE_API_BASE_URL` at build time.
2. Add Android/iOS location permission declarations required by `geolocator`.
3. Replace AdMob test unit in `lib/services/ad_service.dart` with production unit IDs, and add application IDs to AndroidManifest.xml / Info.plist.
4. Keep price and weather provider keys server-side. Add source and `updatedAt` to every response.
5. Add a backend cache and scheduled refresh; never scrape Google results from the mobile client.
6. Before production, add proper city geocoding to `/v1/places/search?q=` and pass the returned coordinates to `/v1/market`.
