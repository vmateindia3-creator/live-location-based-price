import os
import unittest

os.environ['GOOGLE_SEARCH_ENABLED'] = 'false'
from app import PRICE_RANGES, app


class ApiTests(unittest.TestCase):
    def setUp(self):
        self.client = app.test_client()

    def test_health(self):
        response = self.client.get('/health')
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json['ok'])

    def test_market_contract(self):
        response = self.client.get('/v1/market?lat=28.61&lng=77.20&city=Delhi')
        self.assertEqual(response.status_code, 200)
        payload = response.json
        self.assertEqual(payload['currency'], 'INR')
        self.assertEqual(set(payload['prices']), {'petrol', 'diesel', 'lpg', 'cng', 'gold', 'silver'})
        self.assertIn('weather', payload)
        self.assertIn('observedKeys', payload)
        self.assertIn('sourceUrls', payload)
        self.assertIn('petrol', payload['sourceUrls'])

    def test_places_search(self):
        response = self.client.get('/v1/places/search?q=Mumbai')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json['results'][0]['name'], 'Mumbai')

    def test_places_search_returns_coordinates(self):
        response = self.client.get('/v1/places/search?q=Delhi')
        result = response.json['results'][0]
        self.assertGreater(result['latitude'], 27.0)
        self.assertLess(result['latitude'], 30.0)
        self.assertGreater(result['longitude'], 76.0)
        self.assertLess(result['longitude'], 78.5)

    def test_invalid_coordinates(self):
        self.assertEqual(self.client.get('/v1/market?lat=nope').status_code, 400)

    def test_price_ranges_reject_obviously_wrong_search_values(self):
        self.assertFalse(PRICE_RANGES['petrol'][0] <= 47 <= PRICE_RANGES['petrol'][1])
        self.assertFalse(PRICE_RANGES['gold'][0] <= 20 <= PRICE_RANGES['gold'][1])
        self.assertFalse(PRICE_RANGES['silver'][0] <= 861 <= PRICE_RANGES['silver'][1])


if __name__ == '__main__':
    unittest.main()
