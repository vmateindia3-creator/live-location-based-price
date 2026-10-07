"""Offline, deterministic tests for the API.

No test here touches the network: price, weather and geocoding calls are
patched, so CI is not flaky when GoodReturns or a geocoder is slow or blocking.
"""

import unittest
from unittest import mock

import app as app_module
from app import (
    PRICE_RANGES,
    app,
    candidate_urls,
    city_slug,
    nearest_city,
    normalize_value,
    parse_goodreturns_value,
    sanitize_prices,
)

FULL_PRICES = {"petrol": 94.72, "diesel": 87.62, "lpg": 903.0, "cng": 75.09, "gold": 10250.0, "silver": 128.0}
FULL_WEATHER = {"temperatureC": 28.0, "condition": "Clear", "humidity": 50, "windKph": 10.0}


class ApiTests(unittest.TestCase):
    def setUp(self):
        self.client = app.test_client()
        self._price_patch = mock.patch.object(app_module, "fetch_prices", return_value=(FULL_PRICES, "goodreturns", set(FULL_PRICES), "2026-01-01T00:00:00+00:00"))
        self._weather_patch = mock.patch.object(app_module, "fetch_weather", return_value=dict(FULL_WEATHER))
        self._price_patch.start()
        self._weather_patch.start()
        app_module.cache.clear()

    def tearDown(self):
        self._price_patch.stop()
        self._weather_patch.stop()

    def test_health(self):
        response = self.client.get("/health")
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json["ok"])

    def test_market_contract(self):
        response = self.client.get("/v1/market?lat=28.61&lng=77.20&city=Delhi")
        self.assertEqual(response.status_code, 200)
        payload = response.json
        self.assertEqual(payload["currency"], "INR")
        self.assertEqual(set(payload["prices"]), set(FULL_PRICES))
        self.assertEqual(set(payload["observedKeys"]), set(FULL_PRICES))
        self.assertIn("weather", payload)
        self.assertIn("units", payload)
        self.assertEqual(payload["units"]["petrol"], "INR/L")
        self.assertIn("petrol", payload["sourceUrls"])
        self.assertEqual(payload["source"], "goodreturns")

    def test_market_returns_wealth_keys(self):
        response = self.client.get("/v1/market?lat=28.61&lng=77.20&city=Delhi")
        prices = response.json["prices"]
        self.assertIn("gold", prices)
        self.assertIn("silver", prices)

    def test_market_when_source_unavailable(self):
        with mock.patch.object(app_module, "fetch_prices", return_value=({}, "unavailable", set(), "2026-01-01T00:00:00+00:00")):
            response = self.client.get("/v1/market?lat=28.61&lng=77.20&city=Delhi")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json["prices"], {})
        self.assertEqual(response.json["source"], "unavailable")

    def test_invalid_coordinates(self):
        self.assertEqual(self.client.get("/v1/market?lat=nope").status_code, 400)

    def test_out_of_range_coordinates(self):
        self.assertEqual(self.client.get("/v1/market?lat=200&lng=77").status_code, 400)
        self.assertEqual(self.client.get("/v1/market?lat=28&lng=999").status_code, 400)

    def test_places_search_falls_back_to_builtin(self):
        with mock.patch.object(app_module.requests, "get", side_effect=app_module.requests.RequestException("offline")):
            response = self.client.get("/v1/places/search?q=Mumbai")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json["results"][0]["name"], "Mumbai")
        self.assertAlmostEqual(response.json["results"][0]["latitude"], 19.0760, places=3)

    def test_places_search_empty_query(self):
        self.assertEqual(self.client.get("/v1/places/search?q=").json["results"], [])


class ParserTests(unittest.TestCase):
    def test_sanitize_rejects_implausible_values(self):
        clean = sanitize_prices({"petrol": 47, "gold": 20, "silver": 2000, "cng": 88})
        self.assertNotIn("petrol", clean)
        self.assertNotIn("gold", clean)
        self.assertNotIn("silver", clean)
        self.assertEqual(clean["cng"], 88)

    def test_sanitize_drops_unknown_keys(self):
        self.assertEqual(sanitize_prices({"banana": 10}), {})

    def test_sanitize_handles_bad_types(self):
        self.assertEqual(sanitize_prices({"petrol": "abc", "diesel": None}), {})

    def test_parse_petrol(self):
        text = "Today's petrol price in Delhi is ₹94.72 per litre in Delhi."
        self.assertEqual(parse_goodreturns_value("petrol", text), 94.72)

    def test_parse_silver_normalises_kg_to_gram(self):
        text = "Silver /kg ₹1,28,000"
        self.assertEqual(parse_goodreturns_value("silver", text), 128.0)

    def test_parse_gold_normalises_10g_to_gram(self):
        # A per-10g quote (~₹75,000) should become ~₹7,500 per gram.
        text = "24K Gold ₹75,000"
        self.assertEqual(parse_goodreturns_value("gold", text), 7500.0)

    def test_parse_gold_per_gram_unchanged(self):
        text = "24K Gold /g ₹10,250"
        self.assertEqual(parse_goodreturns_value("gold", text), 10250.0)

    def test_normalize_value_keeps_in_range(self):
        self.assertEqual(normalize_value("gold", 10250.0), 10250.0)
        self.assertEqual(normalize_value("petrol", 94.72), 94.72)

    def test_parse_returns_none_on_missing_pattern(self):
        self.assertIsNone(parse_goodreturns_value("petrol", "no rate here"))

    def test_price_ranges_reject_obviously_wrong_values(self):
        self.assertFalse(PRICE_RANGES["petrol"][0] <= 47 <= PRICE_RANGES["petrol"][1])
        self.assertFalse(PRICE_RANGES["gold"][0] <= 20 <= PRICE_RANGES["gold"][1])
        self.assertFalse(PRICE_RANGES["silver"][0] <= 2000 <= PRICE_RANGES["silver"][1])

    def test_city_slug_aliases(self):
        self.assertEqual(city_slug("Bengaluru"), "bangalore")
        self.assertEqual(city_slug("New Delhi"), "new-delhi")
        self.assertEqual(city_slug("Thiruvananthapuram"), "trivandrum")
        self.assertEqual(city_slug("Gurugram"), "gurgaon")


class LocationTests(unittest.TestCase):
    def test_nearest_city_matches_major_city(self):
        self.assertEqual(nearest_city(28.61, 77.20), "Delhi")
        self.assertEqual(nearest_city(19.07, 72.87), "Mumbai")

    def test_candidate_urls_has_national_fallback_for_gold(self):
        urls = candidate_urls("Delhi")
        self.assertGreaterEqual(len(urls["gold"]), 2)
        self.assertTrue(urls["gold"][0].endswith("/gold-rates/delhi.html"))
        self.assertTrue(urls["gold"][1].endswith("/gold-rates/"))

    def test_candidate_urls_india_uses_national_pages(self):
        urls = candidate_urls("India")
        self.assertTrue(urls["petrol"][0].endswith("/petrol-price.html"))

    def test_resolve_city_prefers_requested_name(self):
        self.assertEqual(app_module.resolve_city(28.6, 77.2, "Jaipur"), "Jaipur")

    def test_resolve_city_falls_back_to_nearest_city(self):
        with mock.patch.object(app_module.requests, "get", side_effect=app_module.requests.RequestException("offline")):
            self.assertEqual(app_module.resolve_city(28.61, 77.20, "Current location"), "Delhi")


if __name__ == "__main__":
    unittest.main()
