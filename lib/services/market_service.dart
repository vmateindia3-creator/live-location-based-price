import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/market_models.dart';

class MarketService {
  MarketService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static const baseUrl = String.fromEnvironment('PRICE_API_BASE_URL');

  Future<PlaceResult> search(String query) async {
    if (baseUrl.isNotEmpty) {
      try {
        final uri = Uri.parse('$baseUrl/v1/places/search').replace(queryParameters: {'q': query});
        final response = await _client.get(uri).timeout(const Duration(seconds: 6));
        if (response.statusCode == 200) {
          final results = (jsonDecode(response.body) as Map<String, dynamic>)['results'] as List<dynamic>;
          if (results.isNotEmpty) {
            final item = Map<String, dynamic>.from(results.first as Map);
            return PlaceResult(name: item['name'].toString(), latitude: (item['latitude'] as num).toDouble(), longitude: (item['longitude'] as num).toDouble());
          }
        }
      } catch (_) {}
    }
    const Map<String, List<double>> known = {'delhi': [28.6139, 77.2090], 'mumbai': [19.0760, 72.8777], 'kolkata': [22.5726, 88.3639], 'bengaluru': [12.9716, 77.5946], 'chennai': [13.0827, 80.2707]};
    final List<double> coords = known[query.trim().toLowerCase()] ?? [20.5937, 78.9629];
    return PlaceResult(name: query.trim().isEmpty ? 'India' : query.trim(), latitude: coords[0], longitude: coords[1]);
  }

  Future<MarketData> fetch({required double latitude, required double longitude, String? city}) async {
    if (baseUrl.isEmpty) return _demo();
    try {
      final uri = Uri.parse('$baseUrl/v1/market').replace(queryParameters: {
        'lat': latitude.toString(), 'lng': longitude.toString(), if (city != null) 'city': city,
      });
      final response = await _client.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) return MarketData.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } catch (_) {}
    return _demo();
  }

  MarketData _demo() => MarketData(
    updatedAt: DateTime.now(),
    prices: const {'petrol': 94.72, 'diesel': 87.62, 'lpg': 803, 'cng': 75.09, 'gold': 75250, 'silver': 92500},
    weather: const WeatherData(temperatureC: 29, condition: 'Partly cloudy', humidity: 48, windKph: 11),
  );
}
