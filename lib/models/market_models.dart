/// Shared, conservative Indian retail ranges (INR). Kept in one place so the
/// model, the UI and the backend all agree. Anything outside is treated as a
/// parse error and dropped rather than shown.
const Map<String, List<double>> kPriceRanges = {
  'petrol': [50, 150],
  'diesel': [50, 150],
  'lpg': [300, 2500],
  'cng': [20, 200],
  'gold': [5000, 30000],
  'silver': [50, 1000],
};

/// Display unit suffix for each key.
const Map<String, String> kPriceUnits = {
  'petrol': '/L',
  'diesel': '/L',
  'lpg': '/cyl',
  'cng': '/kg',
  'gold': '/g',
  'silver': '/g',
};

bool isPlausiblePrice(String key, double value) {
  final range = kPriceRanges[key];
  return range != null && value >= range[0] && value <= range[1];
}

class MarketData {
  const MarketData({
    required this.updatedAt,
    required this.prices,
    required this.weather,
    required this.source,
    required this.currency,
    this.city = 'India',
    this.state = '',
    this.pincode,
    this.warning,
    this.observedKeys = const {},
    this.sourceUrls = const {},
    this.units = const {},
  });

  final DateTime updatedAt;
  final Map<String, double> prices;
  final WeatherData weather;
  final String source;
  final String currency;
  final String city;
  final String state;
  final String? pincode;
  final String? warning;
  final Set<String> observedKeys;
  final Map<String, String> sourceUrls;
  final Map<String, String> units;

  factory MarketData.fromJson(Map<String, dynamic> json) {
    final raw = Map<String, dynamic>.from(json['prices'] as Map? ?? {});
    final weather = Map<String, dynamic>.from(json['weather'] as Map? ?? {});
    final safePrices = <String, double>{};
    for (final entry in raw.entries) {
      final value = entry.value is num ? (entry.value as num).toDouble() : null;
      if (value != null && isPlausiblePrice(entry.key, value)) {
        safePrices[entry.key] = value;
      }
    }
    return MarketData(
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      prices: safePrices,
      weather: WeatherData.fromJson(weather),
      source: json['source']?.toString() ?? 'unknown',
      currency: json['currency']?.toString() ?? 'INR',
      city: json['city']?.toString() ?? 'India',
      state: json['state']?.toString() ?? '',
      pincode: json['pincode']?.toString(),
      warning: json['warning']?.toString(),
      observedKeys: ((json['observedKeys'] as List?) ?? const []).map((e) => e.toString()).toSet(),
      sourceUrls: Map<String, String>.from((json['sourceUrls'] as Map?) ?? const {}),
      units: Map<String, String>.from((json['units'] as Map?) ?? const {}),
    );
  }
}

class WeatherData {
  const WeatherData({required this.temperatureC, required this.condition, required this.humidity, required this.windKph});
  final double temperatureC;
  final String condition;
  final int humidity;
  final double windKph;

  factory WeatherData.fromJson(Map<String, dynamic> json) => WeatherData(
        temperatureC: (json['temperatureC'] as num? ?? 28).toDouble(),
        condition: json['condition']?.toString() ?? 'Clear',
        humidity: (json['humidity'] as num? ?? 45).toInt(),
        windKph: (json['windKph'] as num? ?? 10).toDouble(),
      );
}

class PlaceResult {
  const PlaceResult({required this.name, required this.latitude, required this.longitude});
  final String name;
  final double latitude;
  final double longitude;
}
