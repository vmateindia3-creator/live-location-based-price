# Release configuration

## 1. App icon (and how to update it later)

Put your artwork at **`assets/icon.png`** in the repository — a square PNG,
ideally **1024×1024**, no rounded corners (Android rounds them itself).

CI picks it up automatically on every build and generates all the launcher
sizes. If the file is missing, a default LocaRate icon is drawn.

To change the icon later: replace `assets/icon.png` and push. Done.

## 2. AdMob

See **ADMOB_SETUP.md**. Short version: create the account, add the app, create a
banner and an interstitial unit, then add three repo secrets
(`ADMOB_APP_ID`, `ADMOB_BANNER_ID`, `ADMOB_INTERSTITIAL_ID`). CI wires them in.

## 3. Signing for Play Store

Play needs an **AAB signed with your own keystore**.

```bash
keytool -genkey -v -keystore locarate-release.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias locarate
```

Then add four repo secrets and CI signs the release build for you:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 locarate-release.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | your store password |
| `ANDROID_KEY_ALIAS` | `locarate` |
| `ANDROID_KEY_PASSWORD` | your key password |

With those set, CI patches the Gradle signing config and produces
`locarate-play-aab` (the file you upload to Play). Without them the build stays
debug-signed, which is fine for testing but not for the store.

**Back up the keystore and its passwords.** Losing them means you cannot update
the app on Play.

## 4. Package name

The app currently uses the default `com.example.live_location_based_price`.
Change it to something you own **before the first Play upload** (Play will not let
you change it later). Search the repo for `com.example` and update the
`applicationId`, the Kotlin package folder and the manifest.

## 5. Play Console

- Create the app, name **LocaRate**, upload the AAB to an **internal test** track first.
- Add the **privacy policy URL** (host `PRIVACY_POLICY.md` publicly) and link `TERMS.md`.
- Complete **Data safety** (approximate location; ads via AdMob; no account data).
- Complete **Content rating** and the **Ads** declaration.
- Store listing: 512×512 icon, feature graphic, screenshots, description.

## 6. Backend

- Set `ALLOWED_ORIGINS` and keep `RATE_LIMIT_PER_MIN` on (see `SECURITY.md`).
- Confirm live rates on your Render deployment.

## 7. Data source

The app derives rates from a third-party public website. Before a commercial
launch, confirm your use is permitted (see the README). The safe path is a
licensed/official feed or written permission.
