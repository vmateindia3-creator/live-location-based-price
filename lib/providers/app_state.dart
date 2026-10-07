import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/market_models.dart';
import '../services/location_service.dart';
import '../services/market_service.dart';

class AppState extends ChangeNotifier {
  AppState({MarketService? market, LocationService? location})
      : _market = market ?? MarketService(),
        _location = location ?? LocationService() {
    _restoreLanguage();
  }

  final MarketService _market;
  final LocationService _location;

  MarketData? data;
  PlaceResult place = const PlaceResult(name: 'India', latitude: 20.5937, longitude: 78.9629);
  bool loading = false;
  String? error;
  String language = 'hi';

  Future<void> _restoreLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('language');
      if ((saved == 'en' || saved == 'hi') && saved != language) {
        language = saved!;
        notifyListeners();
      }
    } catch (_) {
      // Preferences are optional; fall back to the default language.
    }
  }

  Future<void> load({PlaceResult? target}) async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      place = target ?? await _location.current();
    } catch (_) {
      error = language == 'hi' ? 'Location उपलब्ध नहीं है' : 'Location unavailable';
    }

    try {
      final loaded = await _market.fetch(latitude: place.latitude, longitude: place.longitude, city: place.name);
      data = loaded;
      if (target == null && loaded.city.trim().isNotEmpty && loaded.city != 'India') {
        place = PlaceResult(name: loaded.city, latitude: place.latitude, longitude: place.longitude);
      }
    } catch (_) {
      // Keep the last successful data rather than blanking the screen.
      error ??= language == 'hi' ? 'Rates अभी उपलब्ध नहीं हैं' : 'Rates are unavailable';
    }

    loading = false;
    notifyListeners();
  }

  Future<void> searchCity(String query) async {
    if (query.trim().isEmpty) {
      await load();
      return;
    }
    try {
      await load(target: await _market.search(query));
    } catch (_) {
      error = language == 'hi' ? 'शहर नहीं मिला' : 'City not found';
      loading = false;
      notifyListeners();
    }
  }

  void toggleLanguage() {
    language = language == 'hi' ? 'en' : 'hi';
    notifyListeners();
    _persistLanguage();
  }

  Future<void> _persistLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('language', language);
    } catch (_) {
      // Ignore persistence failures; the in-memory choice still applies.
    }
  }
}
