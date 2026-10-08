# Release checklist

## Done in the repo
- [x] Flask health, market and places endpoints
- [x] PIN-code lookup (19,586 PINs) + state-wise and nearest-city fallbacks
- [x] Pan-India coverage: every state's rate from the national pages
- [x] Daily cache refresh (06:00 / 18:00 IST) + throttled live scrape
- [x] City-keyed cache so users do not scale upstream traffic
- [x] Real AdMob app + banner + interstitial IDs wired in
- [x] App icon generated from `assets/icon.png` (or a default)
- [x] Android package name `com.vmate.locarate` (Play rejects `com.example.*`)
- [x] targetSdk 35, minSdk 21, v1 + v2 signed release builds
- [x] CI builds APKs **and** a Play-ready AAB, and publishes them to the release
- [x] Optional release signing from keystore secrets (PKCS12 supported)
- [x] Security headers, rate limiting, secret-safe `.gitignore`
- [x] Privacy policy, terms of use, AdMob + Play guides
- [x] Offline backend tests (40) and Flutter analyze/test

## You need to do
- [ ] Add the four signing secrets (see `KEYSTORE_INFO.txt` / `PLAY_STORE_GUIDE.md`)
- [ ] Create the AdMob consent message (Privacy & messaging)
- [ ] Play Console: create app, upload the AAB, listing + data safety + content rating
- [ ] Host the privacy policy at a public URL and paste it in the listing
- [ ] Take phone screenshots for the store listing
- [ ] Decide the data-source question (licensed feed or written permission)
- [ ] Never tap your own real ads; keep the keystore backed up
