class MarketData {
  const MarketData({required this.updatedAt, required this.prices, required this.weather, required this.source, required this.currency, this.warning, this.observedKeys = const {}, this.sourceUrls = const {}});
  final DateTime updatedAt;
  final Map<String, double> prices;
  final WeatherData weather;
  final String source;
  final String currency;
  final String? warning;
  final Set<String> observedKeys;
  final Map<String, String> sourceUrls;

  factory MarketData.fromJson(Map<String, dynamic> json) {
    final raw = Map<String, dynamic>.from(json['prices'] as Map? ?? {});
    final weather = Map<String, dynamic>.from(json['weather'] as Map? ?? {});
    return MarketData(
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      prices: raw.map((key, value) => MapEntry(key, (value as num).toDouble())),
      weather: WeatherData.fromJson(weather),
      source: json['source']?.toString() ?? 'unknown',
      currency: json['currency']?.toString() ?? 'INR',
      warning: json['warning']?.toString(),
      observedKeys: ((json['observedKeys'] as List?) ?? const []).map((e) => e.toString()).toSet(),
      sourceUrls: Map<String, String>.from((json['sourceUrls'] as Map?) ?? const {}),
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
