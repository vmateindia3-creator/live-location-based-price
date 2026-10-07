import 'package:flutter_test/flutter_test.dart';
import 'package:live_location_based_price/services/market_service.dart';

void main() {
  test('backend fallback never invents a fuel price', () async {
    final data = await MarketService().fetch(latitude: 20.5, longitude: 78.9);
    expect(data.prices, isEmpty);
    expect(data.weather.temperatureC, isNotNull);
  });
}
