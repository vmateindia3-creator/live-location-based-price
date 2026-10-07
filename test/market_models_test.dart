import 'package:flutter_test/flutter_test.dart';
import 'package:live_location_based_price/models/market_models.dart';

void main() {
  test('keeps GoodReturns normalized units and rejects impossible values', () {
    final data = MarketData.fromJson({
      'city': 'Mumbai',
      'prices': {
        'petrol': 111.21,
        'diesel': 97.83,
        'gold': 15023,
        'silver': 234.90,
        'lpg': 941.50,
        'cng': 88.00,
        'invalid': 202.4,
      },
      'weather': {
        'temperatureC': 28,
        'condition': 'Clear',
        'humidity': 50,
        'windKph': 10,
      },
      'source': 'goodreturns',
      'currency': 'INR',
    });

    expect(data.city, 'Mumbai');
    expect(data.prices['petrol'], 111.21);
    expect(data.prices['silver'], 234.90);
    expect(data.prices.containsKey('invalid'), isFalse);
  });
}
