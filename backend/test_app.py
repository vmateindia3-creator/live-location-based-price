"""Offline, deterministic tests for the API. No test touches the network."""

import unittest
from unittest import mock

import app as app_module
from app import (
    PRICE_RANGES,
    age_seconds,
    app,
    cached_prices,
    candidate_urls,
    city_slug,
    fetch_prices,
    nearest_city,
    normalize_value,
    parse_fuel_value,
    parse_goodreturns_value,
    parse_metal_value,
    resolve_location,
    sanitize_prices,
    table_value,
    weather_for,
)

FULL_PRICES = {"petrol": 94.72, "diesel": 87.62, "lpg": 903.0, "cng": 75.09, "gold": 10250.0, "silver": 128.0}
FULL_WEATHER = {"temperatureC": 28.0, "condition": "Clear", "humidity": 50, "windKph": 10.0}

# Shaped like the real GoodReturns page text (headline = Mumbai, real values in tables).
PETROL_PAGE = (
    "Petrol Price in India Today's petrol price in India (Mumbai) stands at ₹ 111.21 per litre. "
    "Petrol Price in Indian Metro Cities & State Capitals "
    "| City | Price | Price Change | | New Delhi | ₹102.12 | 0.00 | | Lucknow | ₹101.86 | 0.00 | "
    "| Mumbai | ₹111.21 | 0.00 | "
    "State-Wise Petrol Price in India "
    "| Uttar Pradesh | ₹101.86 | 0.00 | | Delhi | ₹102.12 | 0.00 | | Maharashtra | ₹111.21 | 0.00 | "
    "Crude Oil Consumption in India "
)
LPG_PAGE = (
    "LPG Price in India The Domestic LPG (14.2 kg) cylinder price in India (Mumbai) stands at ₹ 941.50. "
    "Today's LPG Price in Indian Metro Cities & State Capitals "
    "| City | Domestic (14.2 Kg) | Commercial (19 Kg) | "
    "| New Delhi | ₹942.00 (0.00) | ₹2,810.00 (+62.50) | | Lucknow | ₹979.50 (0.00) | ₹2,932.50 (+62.50) | "
    "State-Wise LPG Price in India "
    "| Uttar Pradesh | ₹979.50 (0.00) | ₹2,932.50 (+62.50) | | Delhi | ₹942.00 (0.00) | ₹2,810.00 (+62.50) | "
    "LPG rates in India "
)
CNG_PAGE = (
    "CNG Price in India Today's CNG price in India (Mumbai) is ₹86.98 per kg. "
    "CNG Price in Indian Metro Cities & State Capitals | New Delhi | ₹86.98 | 0.00 | "
    "State-Wise CNG Price in India | Delhi | ₹86.98 | 0.00 | About CNG "
)
GOLD_PAGE = (
    "Gold Rate in Delhi Today's gold price in Delhi stands at ₹14,970 per gram for 24 karat gold (99.9% purity). "
    "8 October 2026 24K Gold /g ₹14,970 22K Gold /g ₹13,725 18K Gold /g ₹11,233 "
)
SILVER_PAGE = (
    "Silver Rate in Delhi Today's silver price in Delhi stands at ₹2,35,000 per kg. Silver /kg ₹2,35,000 "
)


class ApiTests(unittest.TestCase):
    def setUp(self):
        self.client = app.test_client()
        self._price_patch = mock.patch.object(app_module, "fetch_prices", return_value=(FULL_PRICES, "goodreturns", set(FULL_PRICES), "2026-01-01T00:00:00+00:00"))
        self._weather_patch = mock.patch.object(app_module, "fetch_weather", return_value=dict(FULL_WEATHER))
        self._geo_patch = mock.patch.object(app_module, "reverse_geocode", return_value=("Delhi", "Delhi"))
        self._price_patch.start()
        self._weather_patch.start()
        self._geo_patch.start()
        app_module.cache.clear()

    def tearDown(self):
        self._price_patch.stop()
        self._weather_patch.stop()
        self._geo_patch.stop()

    def test_health(self):
        self.assertTrue(self.client.get("/health").json["ok"])

    def test_market_contract(self):
        payload = self.client.get("/v1/market?lat=28.61&lng=77.20&city=Delhi").json
        self.assertEqual(payload["currency"], "INR")
        self.assertEqual(set(payload["prices"]), set(FULL_PRICES))
        self.assertEqual(payload["units"]["petrol"], "INR/L")
        self.assertEqual(payload["city"], "Delhi")
        self.assertEqual(payload["state"], "Delhi")
        self.assertIn("weather", payload)

    def test_market_returns_wealth_keys(self):
        prices = self.client.get("/v1/market?lat=28.61&lng=77.20&city=Delhi").json["prices"]
        self.assertIn("gold", prices)
        self.assertIn("silver", prices)

    def test_market_when_source_unavailable(self):
        # Even then the app must not show blank cards: the nearest covered
        # location fills every item, and says where it came from.
        cache = {"noida": {"city": "Noida", "prices": {"petrol": 102.12}, "updatedAt": None}}
        with mock.patch.object(app_module, "fetch_prices", return_value=({}, "unavailable", set(), "2026-01-01T00:00:00+00:00")), \
                mock.patch.object(app_module, "load_file_cache", return_value=cache):
            payload = self.client.get("/v1/market?lat=28.61&lng=77.20&city=Delhi").json
        self.assertEqual(payload["source"], "unavailable")
        self.assertEqual(payload["prices"]["petrol"], 102.12)
        self.assertEqual(payload["approximate"]["petrol"], "Noida")

    def test_invalid_and_out_of_range_coordinates(self):
        self.assertEqual(self.client.get("/v1/market?lat=nope").status_code, 400)
        self.assertEqual(self.client.get("/v1/market?lat=200&lng=77").status_code, 400)

    def test_places_search_falls_back_to_builtin(self):
        with mock.patch.object(app_module.requests, "get", side_effect=app_module.requests.RequestException("offline")):
            response = self.client.get("/v1/places/search?q=Mumbai")
        self.assertEqual(response.json["results"][0]["name"], "Mumbai")


class FuelParsingTests(unittest.TestCase):
    def test_state_row_used_for_small_town(self):
        # Amethi has no city page -> the state row is the correct value, not Mumbai.
        self.assertEqual(parse_fuel_value("petrol", PETROL_PAGE, "Amethi", "Uttar Pradesh"), 101.86)

    def test_city_row_wins_when_present(self):
        self.assertEqual(parse_fuel_value("petrol", PETROL_PAGE, "Lucknow", "Uttar Pradesh"), 101.86)
        self.assertEqual(parse_fuel_value("lpg", LPG_PAGE, "Lucknow", "Uttar Pradesh"), 979.50)

    def test_delhi_uses_new_delhi_row(self):
        self.assertEqual(parse_fuel_value("petrol", PETROL_PAGE, "Delhi", "Delhi"), 102.12)

    def test_never_returns_mumbai_headline_when_city_known(self):
        # Mumbai's headline is 111.21; a known city/state must not fall back to it.
        self.assertNotEqual(parse_fuel_value("petrol", PETROL_PAGE, "Amethi", "Uttar Pradesh"), 111.21)
        self.assertNotEqual(parse_fuel_value("lpg", LPG_PAGE, "Amethi", "Uttar Pradesh"), 941.50)

    def test_cng_does_not_fall_back_to_another_city(self):
        self.assertIsNone(parse_fuel_value("cng", CNG_PAGE, "Amethi", "Uttar Pradesh"))
        self.assertEqual(parse_fuel_value("cng", CNG_PAGE, "Delhi", "Delhi"), 86.98)

    def test_national_page_headline_is_never_another_city_s_price(self):
        # The India page's headline is Mumbai's rate. An unknown town must get
        # nothing from it (the caller then uses a genuinely nearby city),
        # never Mumbai's figure dressed up as its own.
        text = "Today's petrol price in India (Mumbai) stands at ₹ 111.21 per litre."
        self.assertIsNone(parse_fuel_value("petrol", text, "Nowhere", ""))

    def test_town_with_own_page_uses_its_own_headline(self):
        page = (
            "Petrol Price in Varanasi Today's petrol price in Varanasi stands at ₹102.23 per litre. "
            "Metro Cities & State Capitals | Lucknow | ₹101.86 | 0.00 | "
            "State-Wise Petrol Price in India | Uttar Pradesh | ₹101.86 | 0.00 | "
        )
        self.assertEqual(parse_fuel_value("petrol", page, "Varanasi", "Uttar Pradesh"), 102.23)

    def test_generic_page_is_not_mistaken_for_city_page(self):
        # Amethi's URL serves the generic page, so the state row must be used.
        self.assertEqual(parse_fuel_value("petrol", PETROL_PAGE, "Amethi", "Uttar Pradesh"), 101.86)

    def test_state_alias_handles_goodreturns_spelling(self):
        page = (
            "Petrol Price in India Today's petrol price in India (Mumbai) stands at ₹ 111.21 per litre. "
            "Metro Cities & State Capitals | New Delhi | ₹102.12 | 0.00 | "
            "State-Wise Petrol Price in India | Chhatisgarh | ₹108.06 | 0.00 | "
        )
        self.assertEqual(parse_fuel_value("petrol", page, "Bhilai", "Chhattisgarh"), 108.06)

    def test_table_value_helper(self):
        self.assertEqual(table_value(" | Lucknow | ₹101.86 | 0.00 | ", "Lucknow"), 101.86)
        self.assertIsNone(table_value(" | Lucknow | ₹101.86 | ", "Amethi"))


class MetalParsingTests(unittest.TestCase):
    def test_gold_per_gram(self):
        self.assertEqual(parse_metal_value("gold", GOLD_PAGE), 14970.0)

    def test_silver_per_kg_normalised(self):
        self.assertEqual(parse_metal_value("silver", SILVER_PAGE), 235.0)

    def test_backwards_compatible_entry_point(self):
        self.assertEqual(parse_goodreturns_value("gold", "24K Gold /g ₹10,250"), 10250.0)
        self.assertEqual(parse_goodreturns_value("petrol", "Today's petrol price in Delhi is ₹94.72 per litre."), 94.72)


class ValueTests(unittest.TestCase):
    def test_sanitize(self):
        clean = sanitize_prices({"petrol": 47, "gold": 20, "silver": 2000, "cng": 88, "banana": 10})
        self.assertEqual(clean, {"cng": 88})

    def test_normalize(self):
        self.assertEqual(normalize_value("gold", 10250.0), 10250.0)
        self.assertEqual(normalize_value("silver", 235000.0), 235.0)

    def test_ranges(self):
        self.assertFalse(PRICE_RANGES["petrol"][0] <= 47 <= PRICE_RANGES["petrol"][1])
        self.assertFalse(PRICE_RANGES["silver"][0] <= 2000 <= PRICE_RANGES["silver"][1])

    def test_city_slug(self):
        self.assertEqual(city_slug("Bengaluru"), "bangalore")
        self.assertEqual(city_slug("New Delhi"), "new-delhi")
        self.assertEqual(city_slug("Amethi"), "amethi")

    def test_age_seconds(self):
        self.assertLess(age_seconds(app_module.now_iso()), 5)
        self.assertEqual(age_seconds("not-a-date"), float("inf"))


class CachingTests(unittest.TestCase):
    def setUp(self):
        app_module.cache.clear()

    def test_fetch_prices_prefers_fresh_file_cache(self):
        fresh = {"prices": {"petrol": 100.0}, "updatedAt": app_module.now_iso()}
        with mock.patch.object(app_module, "load_cached_prices", return_value=fresh), \
             mock.patch.object(app_module, "scrape_throttled") as scrape:
            prices, source, _, _ = fetch_prices("Delhi", "Delhi")
        self.assertEqual(source, "scheduled-cache")
        scrape.assert_not_called()

    def test_fetch_prices_scrapes_when_stale(self):
        stale = {"prices": {"petrol": 90.0}, "updatedAt": "2020-01-01T00:00:00+00:00"}
        with mock.patch.object(app_module, "load_cached_prices", return_value=stale), \
             mock.patch.object(app_module, "scrape_throttled", return_value={"petrol": 95.0}) as scrape:
            prices, source, _, _ = fetch_prices("Delhi", "Delhi")
        scrape.assert_called_once()
        self.assertEqual(prices, {"petrol": 95.0})

    def test_cached_prices_hits_upstream_once_per_city(self):
        with mock.patch.object(app_module, "fetch_prices", return_value=({"petrol": 1.0}, "x", {"petrol"}, "t")) as fp:
            cached_prices("Delhi", "Delhi")
            cached_prices("Delhi", "Delhi")
        self.assertEqual(fp.call_count, 1)

    def test_weather_cached_by_coordinates(self):
        with mock.patch.object(app_module, "fetch_weather", return_value=dict(FULL_WEATHER)) as fw:
            weather_for(28.61, 77.20)
            weather_for(28.61, 77.20)
        self.assertEqual(fw.call_count, 1)


class LocationTests(unittest.TestCase):
    def setUp(self):
        app_module.cache.clear()

    def test_nearest_city_returns_name_and_state(self):
        self.assertEqual(nearest_city(26.15, 81.81), ("Amethi", "Uttar Pradesh"))
        self.assertEqual(nearest_city(28.61, 77.20)[1], "Delhi")

    def test_resolve_location_prefers_requested_city_but_keeps_geo_state(self):
        with mock.patch.object(app_module, "reverse_geocode", return_value=("Amethi", "Uttar Pradesh")):
            self.assertEqual(resolve_location(26.15, 81.81, "Amethi")[:2], ("Amethi", "Uttar Pradesh"))

    def test_resolve_location_uses_geocode_for_current_location(self):
        with mock.patch.object(app_module, "reverse_geocode", return_value=("Amethi", "Uttar Pradesh")):
            self.assertEqual(resolve_location(26.15, 81.81, "Current location")[:2], ("Amethi", "Uttar Pradesh"))

    def test_resolve_location_falls_back_to_nearest_city(self):
        with mock.patch.object(app_module, "reverse_geocode", return_value=(None, None)):
            self.assertEqual(resolve_location(26.15, 81.81, "Current location")[:2], ("Amethi", "Uttar Pradesh"))

    def test_candidate_urls_has_national_fallback_for_gold(self):
        urls = candidate_urls("Delhi")
        self.assertTrue(urls["gold"][0].endswith("/gold-rates/delhi.html"))
        self.assertTrue(urls["gold"][1].endswith("/gold-rates/"))


class PanIndiaTests(unittest.TestCase):
    def setUp(self):
        app_module.cache.clear()

    def test_parse_state_table(self):
        text = " | Bihar | ₹113.37 | 0.00 | | Uttar Pradesh | ₹101.86 | 0.00 | "
        out = app_module.parse_state_table(text)
        self.assertEqual(out.get("Bihar"), 113.37)
        self.assertEqual(out.get("Uttar Pradesh"), 101.86)

    def test_pin_lookup_resolves_district_and_state(self):
        info = app_module.pin_lookup("227405")  # Amethi, Uttar Pradesh
        self.assertIsNotNone(info)
        self.assertEqual(info["state"].lower(), "uttar pradesh")
        self.assertIn("amethi", info["district"].lower())

    def test_pin_lookup_rejects_bad_input(self):
        self.assertIsNone(app_module.pin_lookup("12345"))
        self.assertIsNone(app_module.pin_lookup("abc"))

    def test_resolve_location_uses_pincode(self):
        city, state, lat, lng = resolve_location(0.0, 0.0, "", "227405")
        self.assertEqual(state.lower(), "uttar pradesh")
        self.assertGreater(lat, 20.0)
        self.assertGreater(lng, 70.0)

    def test_state_price_payload(self):
        with mock.patch.object(app_module, "load_state_prices", return_value={"petrol": {"uttar pradesh": 101.86}, "lpg": {"uttar pradesh": 979.5}}):
            self.assertEqual(app_module.state_price_payload("Uttar Pradesh"), {"petrol": 101.86, "lpg": 979.5})

    def test_state_price_payload_handles_goodreturns_spelling(self):
        with mock.patch.object(app_module, "load_state_prices", return_value={"petrol": {"chhatisgarh": 108.06}}):
            self.assertEqual(app_module.state_price_payload("Chhattisgarh"), {"petrol": 108.06})

    def test_fetch_prices_falls_back_to_state_table(self):
        with mock.patch.object(app_module, "load_cached_prices", return_value=None), \
             mock.patch.object(app_module, "scrape_throttled", return_value={}), \
             mock.patch.object(app_module, "load_state_prices", return_value={"petrol": {"uttar pradesh": 101.86}}):
            prices, source, _, _ = fetch_prices("Amethi", "Uttar Pradesh")
        self.assertEqual(source, "state-table")
        self.assertEqual(prices, {"petrol": 101.86})


if __name__ == "__main__":
    unittest.main()


class AliasTests(unittest.TestCase):
    """A renamed place must still find its page under the old name."""

    def test_alias_page_is_tried_after_the_place_s_own_slug(self):
        urls = candidate_urls("Ayodhya")
        self.assertIn("https://www.goodreturns.in/petrol-price-in-ayodhya.html", urls["petrol"])
        self.assertIn("https://www.goodreturns.in/petrol-price-in-faizabad.html", urls["petrol"])

    def test_prayagraj_falls_back_to_allahabad(self):
        self.assertIn("https://www.goodreturns.in/petrol-price-in-allahabad.html", candidate_urls("Prayagraj")["petrol"])

    def test_a_place_without_an_alias_only_has_its_own_page(self):
        urls = candidate_urls("Amethi")
        self.assertEqual([u for u in urls["petrol"] if "petrol-price-in" in u], ["https://www.goodreturns.in/petrol-price-in-amethi.html"])

    def test_headline_names_include_the_alias(self):
        self.assertEqual(app_module.headline_names("Prayagraj"), ["Prayagraj", "Allahabad"])
        self.assertEqual(app_module.headline_names("Amethi"), ["Amethi"])

    def test_headline_is_read_under_the_alias_name(self):
        text = "LPG Price in Faizabad The Domestic LPG (14.2 kg) cylinder price in Faizabad stands at ₹ 1004.50."
        self.assertEqual(app_module.city_headline_value("lpg", text, "Ayodhya"), 1004.5)


class NearestFillTests(unittest.TestCase):
    """No card is ever blank: a missing item comes from the nearest place."""

    CACHE = {
        "amethi": {"city": "Amethi", "prices": {"lpg": 979.5}, "updatedAt": None},
        "lucknow": {"city": "Lucknow", "prices": {"lpg": 979.5, "cng": 90.0}, "updatedAt": None},
    }

    def test_missing_item_is_filled_from_the_nearest_location(self):
        with mock.patch.object(app_module, "load_file_cache", return_value=self.CACHE):
            filled, approximate = app_module.fill_missing_items({"lpg": 979.5}, 26.85, 80.95)
        self.assertEqual(filled["cng"], 90.0)
        self.assertEqual(approximate["cng"], "Lucknow")

    def test_a_present_value_is_never_overwritten(self):
        with mock.patch.object(app_module, "load_file_cache", return_value=self.CACHE):
            filled, approximate = app_module.fill_missing_items({"lpg": 979.5, "cng": 12.5}, 26.85, 80.95)
        self.assertEqual(filled["cng"], 12.5)
        self.assertNotIn("cng", approximate)

    def test_the_source_location_is_never_used_for_itself(self):
        with mock.patch.object(app_module, "load_file_cache", return_value=self.CACHE):
            found = app_module.nearest_item_source("lpg", 26.85, 80.95, exclude="lucknow")
        self.assertEqual(found[0], "Amethi")


class RealPageShapeTests(unittest.TestCase):
    """Real pages carry ~100 KB of <head> before the headline."""

    def test_headline_found_after_a_long_metadata_head(self):
        page = ("var gr_db_canonical_url = \"https://www.goodreturns.in/x\"; " * 2000) + (
            "The Domestic LPG (14.2 kg) cylinder price in Gorakhpur stands at ₹ 1004.00. No change")
        self.assertGreater(len(page), 100000)
        self.assertEqual(parse_fuel_value("lpg", page, "Gorakhpur", "Uttar Pradesh"), 1004.0)

    def test_headline_found_under_an_alias_after_a_long_head(self):
        page = ("x " * 60000) + "The Domestic LPG (14.2 kg) cylinder price in Faizabad stands at ₹ 1004.50."
        self.assertEqual(parse_fuel_value("lpg", page, "Ayodhya", "Uttar Pradesh"), 1004.5)

    def test_a_distant_number_is_not_mistaken_for_the_headline(self):
        page = "The Domestic LPG (14.2 kg) cylinder price in Gorakhpur stands at ₹ 1004.00. " + ("filler " * 400) + "₹ 9999.00"
        self.assertEqual(parse_fuel_value("lpg", page, "Gorakhpur", "Uttar Pradesh"), 1004.0)


class BankBazaarLpgTests(unittest.TestCase):
    """LPG now comes from BankBazaar's district tables, not GoodReturns."""

    TABLE = (
        "<h2>Domestic LPG Price in Test State</h2><table>"
        "<tr><th>City</th><th>Price</th></tr>"
        "<tr><td>Amethi/CSM Nagar</td><td>Rs.967.00</td></tr>"
        "<tr><td>Allahabad (Prayagraj)</td><td>Rs.1,015.00</td></tr>"
        "<tr><td>Gorakhpur</td><td>₹975.00</td></tr>"
        "</table><p>Elsewhere the price is Rs 1140.50 for a cylinder.</p>"
    )

    def test_district_table_is_parsed(self):
        table = app_module.parse_bankbazaar_lpg(self.TABLE)
        self.assertEqual(table["Gorakhpur"], 975.0)
        self.assertEqual(table["Amethi/CSM Nagar"], 967.0)
        self.assertEqual(table["Allahabad (Prayagraj)"], 1015.0)

    def test_the_header_row_is_skipped(self):
        self.assertNotIn("City", app_module.parse_bankbazaar_lpg(self.TABLE))

    def test_prose_elsewhere_is_not_taken_as_a_rate(self):
        self.assertNotIn(1140.5, app_module.parse_bankbazaar_lpg(self.TABLE).values())

    def test_no_table_means_no_data(self):
        self.assertEqual(app_module.parse_bankbazaar_lpg("<p>no table here</p>"), {})

    def test_lpg_is_no_longer_fetched_from_goodreturns(self):
        self.assertNotIn("lpg", candidate_urls("Amethi"))
        self.assertNotIn("lpg", app_module.GOODRETURNS_KEYS)

    def test_lpg_lookup_prefers_the_place_itself(self):
        with mock.patch.object(app_module, "load_lpg_cache", return_value={
            "amethi": {"name": "Amethi/CSM Nagar", "state": "Uttar Pradesh", "price": 967.0, "url": "u1"},
            "lucknow": {"name": "Lucknow", "state": "Uttar Pradesh", "price": 950.5, "url": "u2"},
        }):
            price, place, _ = app_module.bankbazaar_lpg("Amethi", 26.15, 81.80)
        self.assertEqual(price, 967.0)
        self.assertEqual(place, "Amethi/CSM Nagar")

    def test_lpg_lookup_falls_back_to_the_nearest(self):
        with mock.patch.object(app_module, "load_lpg_cache", return_value={
            "lucknow": {"name": "Lucknow", "state": "Uttar Pradesh", "price": 950.5, "url": "u2"},
        }):
            price, place, _ = app_module.bankbazaar_lpg("Nowhere", 26.85, 80.95)
        self.assertEqual(price, 950.5)
        self.assertEqual(place, "Lucknow")

    def test_no_lpg_cache_means_no_value(self):
        with mock.patch.object(app_module, "load_lpg_cache", return_value={}):
            self.assertEqual(app_module.bankbazaar_lpg("Amethi", 26.15, 81.80), (None, None, None))


class WeatherTests(unittest.TestCase):
    """The weather must be real, or honestly absent - never a made-up 29 C."""

    def test_first_provider_that_answers_wins(self):
        with mock.patch.object(app_module, "_weather_open_meteo", return_value=None), \
                mock.patch.object(app_module, "_weather_wttr",
                                  return_value={"temperatureC": 16.0, "condition": "Clear", "humidity": 40, "windKph": 5.0}):
            value = app_module.fetch_weather(31.1, 77.17)
        self.assertEqual(value["temperatureC"], 16.0)
        self.assertFalse(value["estimated"])

    def test_all_providers_failing_is_reported_not_invented(self):
        with mock.patch.object(app_module, "_weather_open_meteo", side_effect=ValueError("nope")), \
                mock.patch.object(app_module, "_weather_wttr", side_effect=ValueError("nope")):
            value = app_module.fetch_weather(31.1, 77.17)
        self.assertIsNone(value["temperatureC"])
        self.assertTrue(value["estimated"])

    def test_different_coordinates_give_different_weather(self):
        with mock.patch.object(app_module, "_weather_open_meteo",
                               side_effect=lambda lat, lng: {"temperatureC": lat, "condition": "Clear", "humidity": 1, "windKph": 1}):
            self.assertNotEqual(app_module.fetch_weather(13.0, 80.0)["temperatureC"],
                                app_module.fetch_weather(31.0, 77.0)["temperatureC"])

    def test_a_slash_or_bracket_name_registers_under_every_part(self):
        self.assertEqual(app_module.bankbazaar_keys("Amethi/CSM Nagar"),
                         ["amethi-csm-nagar", "amethi", "csm-nagar"])
        self.assertEqual(app_module.bankbazaar_keys("Allahabad (Prayagraj)"),
                         ["allahabad-prayagraj", "allahabad", "prayagraj"])

    def test_amethi_resolves_through_its_bankbazaar_name(self):
        with mock.patch.object(app_module, "load_lpg_cache", return_value={
            "amethi": {"name": "Amethi/CSM Nagar", "state": "Uttar Pradesh", "price": 967.0, "url": "u"},
        }):
            self.assertEqual(app_module.bankbazaar_lpg("Amethi", 26.15, 81.80)[0], 967.0)
