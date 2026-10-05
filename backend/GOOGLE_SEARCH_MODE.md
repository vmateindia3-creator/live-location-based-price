# Google Search indicative mode

Set `GOOGLE_SEARCH_ENABLED=true` to enable best-effort snippet extraction for fuel, LPG, CNG, gold and silver queries. The API returns:

```json
{"source":"google-search-indicative","warning":"Indicative Google Search result; verify before use"}
```

This is not an official or guaranteed live feed. Google may return no result, a stale result, a different unit (for example gold per 10g or silver per kg), rate-limit the request, or change its markup. The backend now uses every extracted category immediately. Missing categories are filled by fallback values and labeled `google-search-partial`; if all categories are extracted, the response is labeled `google-search-indicative`.

The Flutter app displays `Google Search estimate • verify before use`. Do not represent these values as guaranteed accurate and do not use them for financial transactions without checking the original source.
