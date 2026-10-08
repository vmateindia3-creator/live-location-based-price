import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/market_models.dart';

class MarketService {
  MarketService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const baseUrl = String.fromEnvironment(
    'PRICE_API_BASE_URL',
    defaultValue: 'https://live-location-based-price-api.onrender.com',
  );

  Future<PlaceResult> search(String query) async {
    final trimmed = query.trim();
    if (baseUrl.isNotEmpty && trimmed.isNotEmpty) {
      try {
        final uri = Uri.parse('$baseUrl/v1/places/search').replace(queryParameters: {'q': trimmed});
        final response = await _client.get(uri).timeout(const Duration(seconds: 6));
        if (response.statusCode == 200) {
          final results = (jsonDecode(response.body) as Map<String, dynamic>)['results'] as List<dynamic>;
          if (results.isNotEmpty) {
            final item = Map<String, dynamic>.from(results.first as Map);
            return PlaceResult(
              name: item['name'].toString(),
              latitude: (item['latitude'] as num).toDouble(),
              longitude: (item['longitude'] as num).toDouble(),
            );
          }
        } else {
          debugPrint('places/search ${response.statusCode} for "$trimmed"');
        }
      } catch (error) {
        debugPrint('places/search failed for "$trimmed": $error');
      }
    }
    return _knownPlace(trimmed);
  }

  Future<MarketData> fetch({required double latitude, required double longitude, String? city, String? pincode}) async {
    if (baseUrl.isEmpty) {
      return _fallback();
    }
    try {
      final uri = Uri.parse('$baseUrl/v1/market').replace(queryParameters: {
        'lat': latitude.toString(),
        'lng': longitude.toString(),
        if (city != null && city.isNotEmpty) 'city': city,
        if (pincode != null && pincode.isNotEmpty) 'pincode': pincode,
      });
      final response = await _client.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return MarketData.fromJson(decoded);
        }
      }
      debugPrint('market ${response.statusCode} for $city $pincode');
    } catch (error) {
      debugPrint('market fetch failed for $city $pincode: $error');
    }
    return _fallback();
  }

  /// Look prices up by PIN code — the backend resolves district, state and
  /// coordinates itself, and falls back to the nearest city when a PIN has no
  /// dedicated page.
  Future<MarketData> fetchByPincode(String pincode) =>
      fetch(latitude: 20.5937, longitude: 78.9629, pincode: pincode);

  PlaceResult _knownPlace(String query) {
    const known = <String, List<double>>{
      'delhi': [28.6139, 77.2090],
      'new delhi': [28.6139, 77.2090],
      'mumbai': [19.0760, 72.8777],
      'kolkata': [22.5726, 88.3639],
      'bengaluru': [12.9716, 77.5946],
      'bangalore': [12.9716, 77.5946],
      'chennai': [13.0827, 80.2707],
    };
    final coords = known[query.toLowerCase()] ?? const [20.5937, 78.9629];
    return PlaceResult(name: query.isEmpty ? 'India' : query, latitude: coords[0], longitude: coords[1]);
  }

  MarketData _fallback() => MarketData(
        updatedAt: DateTime.now(),
        prices: const {},
        weather: const WeatherData(temperatureC: 29, condition: 'Partly cloudy', humidity: 48, windKph: 11),
        source: 'unavailable',
        currency: 'INR',
      );
}
