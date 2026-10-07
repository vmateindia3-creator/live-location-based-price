# Release configuration

1. Generate the platform folders and add the Android/iOS location permissions required by `geolocator`:
   ```bash
   flutter create --platforms=android,ios --project-name live_location_based_price .
   ```
   Android — `android/app/src/main/AndroidManifest.xml`:
   ```xml
   <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
   <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
   ```
   iOS — `ios/Runner/Info.plist`: `NSLocationWhenInUseUsageDescription`.

2. Add your AdMob **application** IDs to the Android manifest and iOS plist, and replace the test **unit** ID in `lib/services/ad_service.dart` with your production interstitial unit ID. Add a consent flow before serving personalised ads.

3. Point the app at your backend with `--dart-define=PRICE_API_BASE_URL=https://your-api.example`. Keep all provider keys server-side.

4. On the backend, set `ALLOWED_ORIGINS` to your app/web origins, set a sensible `RATE_LIMIT_PER_MIN`, and add `GOOGLE_PLACES_API_KEY` if you want Google city search.

5. Every price response already carries `source`, `observedAt`/`updatedAt`, `units` and `sourceUrls`. Keep and surface them so users can verify a rate.

6. Use a licensed market provider or an approved API for production pricing — do not scrape Google results from the client, and treat GoodReturns values as indicative only.
