# Security & secrets — keeping the code and data safe

## Golden rule

**No secret ever goes in the repository.** Keys live in GitHub Actions secrets
(for builds) or Render environment variables (for the server). The `.gitignore`
already blocks `.env`, `key.properties`, `*.jks`, `*.keystore`, `google-services.json`.

## GitHub

- **Turn on 2FA** for your account (Settings → Password and authentication).
- **Protect `master`**: Settings → Branches → add a rule for `master` (require a
  pull request, block force-pushes). Then a leaked password cannot rewrite history.
- **Secret scanning + push protection**: Settings → Code security → enable. GitHub
  then refuses a push that contains a key.
- **Dependabot alerts** (Code security): gets you notified about vulnerable
  dependencies.
- **CodeQL / code scanning**: enable the default setup for extra safety.
- **Token hygiene**: if you ever pasted a token or password anywhere (chat,
  screenshot, commit), rotate it immediately. Prefer fine-grained tokens with the
  smallest scope.
- **Don't commit the keystore.** Keep it in a password manager + an offline backup.
  If it leaks, anyone can publish updates as you.

## Render

- Keep every secret in **Environment → Environment Variables** (the `render.yaml`
  uses `sync: false` for `GOOGLE_PLACES_API_KEY` — set it in the dashboard).
- Set **`ALLOWED_ORIGINS`** to your real origins instead of `*` once you have a
  website.
- Keep **`RATE_LIMIT_PER_MIN`** and the scrape throttles on — they stop one
  client from burning your server or getting the source site to block you.
- Render serves HTTPS automatically; the API already sends
  `Strict-Transport-Security`, `X-Content-Type-Options`, `X-Frame-Options`.
- Never run the server with `FLASK_ENV=development` in production (that enables
  the debugger, which is remote-code-execution risk).
- Watch the Render logs for repeated 4xx/5xx — that is usually abuse.

## The app

- Never put a real API key in the Flutter app. Anything shipped in an APK can be
  extracted. When you buy a price API later, the key belongs on the **server**,
  and the app keeps calling your backend.
- Keep dependencies updated (`flutter pub outdated`, `pip list --outdated`).

## Data

- Location is used only to look up rates/weather and is not stored beyond a
  short-lived cache.
- The app collects no account data. This is what the Play Store **Data safety**
  form should say.
- Publish `PRIVACY_POLICY.md` at a public URL and link `TERMS.md` in the listing.
