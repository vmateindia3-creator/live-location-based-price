# Where to distribute the app (and what is free)

## Already working for you, free

- **Your own GitHub Release** — the CI already publishes `locarate-arm64.apk` and
  `locarate-universal.apk` there. Share that link directly (WhatsApp, website).
  This is the fastest way to get users today and costs nothing.
- **Firebase App Distribution** — free, made for handing builds to testers by
  email. Good before a public launch.

## Mainstream stores

| Store | Cost | Notes |
|---|---|---|
| **Google Play** | **US$25 one-time** (not free) | The one that matters for India. Needs the AAB, privacy policy URL, data-safety form, content rating. |
| **Amazon Appstore** | Free developer account | Small reach in India but free and easy. |
| **Samsung Galaxy Store** | Free | Good reach on Samsung phones, which are common in India. |
| **Huawei AppGallery** | Free | Only matters if you care about Huawei phones. |

## Free third-party stores (use with care)

- **Aptoide**, **APKPure**, **APKMirror (self-upload)** — free, but they often
  re-host your APK; you lose control and updates can lag.
- **F-Droid** — free, but it requires the app to be fully **open source**. Yours
  is not, so this is not an option unless you open-source it.
- **XDA forums** — free, good for early feedback from enthusiasts.

## Recommendation

1. Launch on **Google Play** (the $25 is worth it — it is where Indian users look).
2. In parallel, share the **GitHub Release APK link** so people can install today.
3. Add **Samsung Galaxy Store** and **Amazon Appstore** later — both free.

## Important for stores

- Google Play requires a **signed AAB** and a **privacy policy URL**. Host
  `PRIVACY_POLICY.md` publicly (GitHub Pages is free) and paste the link.
- Keep one **package name** (`com.example.live_location_based_price`) for the
  lifetime of the app. Before your first upload, change it to something you own
  (for example `com.vmate.locarate`) — Play does not let you change it later.
- Every update must be signed with the **same keystore**. Back it up.
