# Play Store launch guide — LocaRate

Everything on the code side is done. These are the steps only you can do
(accounts, secrets, store listing).

## 1. Add the signing secrets (5 minutes) — required

I generated your upload key: **`locarate-upload.p12`** (details in
`KEYSTORE_INFO.txt`). Add these four secrets in
**GitHub → Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the whole text of `locarate-keystore-base64.txt` |
| `ANDROID_KEYSTORE_PASSWORD` | the *Store password* in `KEYSTORE_INFO.txt` |
| `ANDROID_KEY_ALIAS` | `locarate` |
| `ANDROID_KEY_PASSWORD` | the *Key password* in `KEYSTORE_INFO.txt` |

Then re-run the **Flutter CI** workflow (Actions → Flutter CI → Run workflow).
CI will sign the build with your key and the **`locarate-play-aab`** artifact
becomes the file you upload to Play.

**Back up `locarate-upload.p12` and `KEYSTORE_INFO.txt`** (password manager +
offline copy). Never commit the `.p12` — it is gitignored.

## 2. Package name

Google Play **rejects `com.example.*`**, so CI now builds with
`com.vmate.locarate`. If you want a different one, edit the one line in
`.github/workflows/flutter.yml` (`Set Android package name`) **before your first
upload** — Play never lets you change it later.

## 3. AdMob consent (recommended before scaling)

In AdMob → **Privacy & messaging**, create a **GDPR/consent message** for the
app. Until then ads still serve, but a consent form is required in some regions
and is good practice for India's DPDP Act.

## 4. Play Console

1. Create the app: name **LocaRate**, default language English, app, free.
2. **Internal testing → Create release → upload `app-release.aab`** (from the
   `locarate-play-aab` artifact).
3. Store listing:
   - App icon: `play_icon_512.png`
   - Feature graphic: `play_feature_1024x500.png`
   - Screenshots: at least 2 phone screenshots (take them from the installed app)
   - Short + full description (below)
4. **Privacy policy URL** — host `PRIVACY_POLICY.md` publicly. Free option:
   create a `gh-pages` branch (or use the repo's Pages settings) and publish it;
   the URL is then `https://vmateindia3-creator.github.io/live-location-based-price/PRIVACY_POLICY.html`.
5. **Data safety** form: the app uses **approximate location**, shows **ads
   (AdMob)**, collects **no account data**, and stores only your language choice
   on the device.
6. **Content rating** questionnaire → then **Ads: yes**.
7. Move the release from Internal → Closed → Production when ready.

### Suggested description
> LocaRate shows today's petrol, diesel, LPG, CNG, gold and silver rates plus
> live weather for any location in India — by GPS or by PIN code. Enter an
> amount and see exactly how much fuel or gold it buys. Rates are updated daily;
> weather updates through the day.

## 5. After launch

- Watch **AdMob** for fill rate and **Render** logs for abuse.
- The daily workflow keeps prices and the PIN index fresh (06:00 / 18:00 IST).
- Never tap your own real ads.

## 6. The one thing to decide

The app derives rates from a third-party public website. For a **commercial**
launch, use a licensed/official feed or written permission. This is the only
open item that carries real risk; everything else above is mechanical.
