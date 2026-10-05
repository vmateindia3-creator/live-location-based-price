import 'package:flutter_test/flutter_test.dart';
import 'package:live_location_based_price/services/market_service.dart';
void main(){test('demo market data is available without backend',() async {final data=await MarketService().fetch(latitude:20.5,longitude:78.9);expect(data.prices['petrol'],isPositive);expect(data.weather.temperatureC,isNotNull);});}
