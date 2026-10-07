# Release configuration

## 1. AdMob (so ads serve and earn)

1. Create an account at https://admob.google.com and add an app (Android).
2. Create two ad units: one **Banner** and one **Interstitial**.
3. In the GitHub repo, add these **Actions secrets** (Settings → Secrets and variables → Actions):
   - `ADMOB_APP_ID` — the AdMob **app** ID, looks like `ca-app-pub-XXXXXXXX~YYYYYYYY`
   - `ADMOB_BANNER_ID` — the banner **unit** ID, `ca-app-pub-XXXXXXXX/BBBBBBBBBB`
   - `ADMOB_INTERSTITIAL_ID` — the interstitial **unit** ID, `ca-app-pub-XXXXXXXX/IIIIIIIIII`

CI injects the app ID into the manifest and passes the unit IDs to the build via
`--dart-define`. Until the secrets exist, the build uses Google's **test** IDs
(ads show as test ads and earn nothing).

## 2. Signing (for Play Store)

Play Store needs an **AAB signed with your own keystore** (not the debug key).

```bash
keytool -genkey -v -keystore locarate-release.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias locarate
```

Then either:
- build locally: set `android/key.properties` pointing at the keystore and
  `flutter build appbundle --release`, or
- add CI secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
  `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` and configure the release signing
  config in `android/app/build.gradle(.kts)`.

**Keep the keystore and its passwords safe and backed up.** If you lose them you
cannot publish updates to the same app.

## 3. Play Console checklist

- Create the app, set the display name **LocaRate**, upload the AAB to an
  internal-test track first.
- Add a **Privacy Policy URL** (host `PRIVACY_POLICY.md` publicly, e.g. GitHub
  Pages) and link `TERMS.md`.
- Complete the **Data safety** form: the app uses approximate location, shows
  ads (AdMob), and collects no account data.
- Complete **Content rating** and the **Ads** declaration.
- Add store listing assets: 512×512 icon, feature graphic, screenshots.

## 4. App icon

CI generates the launcher icon automatically (`mipmap-*` PNGs) so the app is not
the default Flutter logo. To use your own, replace the generated files with your
artwork at the same sizes (48/72/96/144/192 px).

## 5. Data source — important

The app currently derives rates from a third-party public website. Before a
commercial launch, confirm that your use is permitted (see the README and the
discussion in the repo). The safest path is a licensed/official data feed or
written permission from the source. Play Store also requires you to own or have
the right to use any data and content in the app.

## 6. Backend

Set `ALLOWED_ORIGINS` and a sensible `RATE_LIMIT_PER_MIN` on the server, and
confirm live rates on your Render deployment.
