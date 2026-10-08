import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_location_based_price/main.dart';
import 'package:live_location_based_price/models/market_models.dart';
import 'package:live_location_based_price/providers/app_state.dart';
import 'package:live_location_based_price/services/ad_service.dart';

/// Lets the test fire a state change the way the app does.
class _TestState extends AppState {
  void bump() => notifyListeners();
}

MarketData _data(double temperature) => MarketData(
      updatedAt: DateTime.now(),
      prices: const {'petrol': 100.0, 'diesel': 90.0, 'lpg': 1000.0, 'cng': 90.0},
      weather: WeatherData(temperatureC: temperature, condition: 'Clear', humidity: 50, windKph: 5),
      source: 'test',
      currency: 'INR',
      city: 'Shimla',
      state: 'Himachal Pradesh',
    );

void main() {
  group('temperature theme', () {
    test('differs for cold and warm, and is not a fixed green', () {
      final cold = themeForTemperature(18).accent;
      final warm = themeForTemperature(30).accent;

      expect(cold, isNot(equals(warm)));
      // 18 C must be blue-dominant...
      expect(cold.b, greaterThan(cold.r));
      expect(cold.b, greaterThan(cold.g));
      // ...and 30 C green-dominant, so the two can never look the same.
      expect(warm.g, greaterThan(warm.r));
    });

    test('every degree shifts the accent', () {
      final a = themeForTemperature(24).accent;
      final b = themeForTemperature(25).accent;
      final c = themeForTemperature(26).accent;
      expect(a, isNot(equals(b)));
      expect(b, isNot(equals(c)));
    });

    test('missing temperature gives the neutral theme, never a fake green', () {
      expect(themeForTemperature(null).accent, kNeutralTheme.accent);
      expect(themeForTemperature(double.nan).accent, kNeutralTheme.accent);
    });
  });

  testWidgets('the header gradient follows the state temperature', (tester) async {
    final state = _TestState()
      ..place = const PlaceResult(name: 'Shimla', latitude: 31.1, longitude: 77.17)
      ..data = _data(18);

    await tester.pumpWidget(
      MaterialApp(home: Home(state: state, ads: AdService(), showAds: false)),
    );
    await tester.pump();

    Color headerAccent() {
      final container = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('appBackground')),
      );
      final decoration = container.decoration as BoxDecoration;
      return (decoration.gradient as LinearGradient).colors.first;
    }

    // Cold city -> the cold accent.
    expect(headerAccent(), themeForTemperature(18).accent);

    // Warm the same screen up: the gradient must move, which is the whole point.
    state.data = _data(33);
    state.bump();
    await tester.pump();

    expect(headerAccent(), themeForTemperature(33).accent);
    expect(headerAccent(), isNot(equals(themeForTemperature(18).accent)));

    // And with no temperature at all it falls back to neutral, not green.
    state.data = _data(double.nan);
    state.bump();
    await tester.pump();
    expect(headerAccent(), kNeutralTheme.accent);
  });
}
