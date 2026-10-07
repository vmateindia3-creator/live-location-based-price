# AdMob setup — step by step

Ads are already wired in the app; you only need your own IDs. Until you add
them the app shows Google **test** ads (which earn nothing).

## 1. Create the AdMob account

1. Go to https://admob.google.com and sign in with a Google account.
2. Complete the sign-up (country **India**, time zone IST).

## 2. Add your app

1. **Apps → Add app → Android**.
2. "Is the app listed on a supported app store?" → **No** for now.
3. App name: `LocaRate` → **Add**.
4. AdMob shows your **App ID**, like `ca-app-pub-1234567890123456~9876543210`.
   Copy it.

## 3. Create the two ad units

1. **Ad units → Add ad unit**.
2. Choose **Banner** → name `LocaRate banner` → Create. Copy the **unit ID**
   (`ca-app-pub-1234567890123456/1111111111`).
3. Repeat with **Interstitial** → name `LocaRate interstitial`. Copy its unit ID.

## 4. Put the IDs into GitHub (never in the code)

Repo → **Settings → Secrets and variables → Actions → New repository secret**:

| Secret name | Value |
|---|---|
| `ADMOB_APP_ID` | `ca-app-pub-...~...` (app ID, tilde `~`) |
| `ADMOB_BANNER_ID` | `ca-app-pub-.../...` (banner unit ID) |
| `ADMOB_INTERSTITIAL_ID` | `ca-app-pub-.../...` (interstitial unit ID) |

CI reads these on every build: it injects the app ID into the Android manifest
and passes the unit IDs via `--dart-define`. No code change needed.

## 5. Get paid

In AdMob: **Payments → Add payment method**, fill in your address and tax
details. Earnings pay out once you cross the payment threshold (about US$100).
Payments go to your bank account.

## Honest notes

- **Ads may not serve immediately.** AdMob usually keeps a new app in a limited
  state until it is live on a store. Keep the app installed from your own
  download for testing — you will still see test ads.
- Never tap your own real ads — that gets the account suspended. Use the test
  IDs for your own testing.
- The app must have a **consent flow** for personalised ads in some regions; add
  one before scaling (a Google UMP / consent SDK step).
- Keep the app's ad placements non-intrusive (the app already caps interstitials
  to one per 3 minutes and shows a single bottom banner).
