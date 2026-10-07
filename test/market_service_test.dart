import 'package:flutter_test/flutter_test.dart';
import 'package:live_location_based_price/services/market_service.dart';

void main() {
  test('backend returns only plausible normalized prices', () async {
    final data = await MarketService().fetch(latitude: 20.5, longitude: 78.9);
    for (final entry in data.prices.entries) {
      expect(entry.value.isFinite, isTrue);
      if (entry.key == 'petrol' || entry.key == 'diesel') {
        expect(entry.value, inInclusiveRange(50, 150));
      }
      if (entry.key == 'gold') {
        expect(entry.value, inInclusiveRange(5000, 30000));
      }
      if (entry.key == 'silver') {
        expect(entry.value, inInclusiveRange(50, 1000));
      }
    }
    expect(data.weather.temperatureC, isNotNull);
  });
}
