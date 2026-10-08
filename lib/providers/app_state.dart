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
  PlaceResult? place;
  bool loading = false;
  bool pricesRevealed = false;
  String? error;
  String language = 'en';

  bool get hasLocation => place != null;

  String _msg(String hi, String en) => language == 'hi' ? hi : en;

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

  /// Resolve the location (from [target] or the device) and load weather.
  /// Prices stay hidden until [updatePrices] is called.
  Future<void> load({PlaceResult? target}) async {
    loading = true;
    error = null;
    pricesRevealed = false;
    notifyListeners();

    try {
      place = target ?? await _location.current();
    } catch (_) {
      if (target == null) {
        place = null;
        error = _msg('पहले location चुनें', 'Select location first');
        loading = false;
        notifyListeners();
        return;
      }
    }

    if (place != null) {
      try {
        final loaded = await _market.fetch(latitude: place!.latitude, longitude: place!.longitude, city: place!.name);
        data = loaded;
        if (target == null && loaded.city.trim().isNotEmpty && loaded.city != 'India') {
          place = PlaceResult(name: loaded.city, latitude: place!.latitude, longitude: place!.longitude);
        }
      } catch (_) {
        error ??= _msg('डेटा अभी उपलब्ध नहीं है', 'Data is unavailable right now');
      }
    }

    loading = false;
    notifyListeners();
  }

  /// Fetch the latest rates for the selected location and reveal them.
  Future<void> updatePrices() async {
    final current = place;
    if (current == null) {
      error = _msg('पहले location चुनें', 'Select location first');
      notifyListeners();
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      data = await _market.fetch(latitude: current.latitude, longitude: current.longitude, city: current.name);
      pricesRevealed = true;
    } catch (_) {
      error = _msg('रेट अभी उपलब्ध नहीं हैं', 'Rates are unavailable right now');
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
      error = _msg('शहर नहीं मिला', 'City not found');
      loading = false;
      notifyListeners();
    }
  }

  /// Look up prices by PIN code and reveal them straight away.
  Future<void> searchPincode(String pin) async {
    final trimmed = pin.trim();
    if (!RegExp(r'^[1-9][0-9]{5}$').hasMatch(trimmed)) {
      error = _msg('6 अंकों का सही PIN डालें', 'Enter a valid 6-digit PIN code');
      notifyListeners();
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      final loaded = await _market.fetchByPincode(trimmed);
      data = loaded;
      place = PlaceResult(
        name: loaded.city.isNotEmpty ? loaded.city : trimmed,
        latitude: place?.latitude ?? 20.5937,
        longitude: place?.longitude ?? 78.9629,
      );
      pricesRevealed = true;
    } catch (_) {
      error = _msg('इस PIN का डेटा नहीं मिला', 'No data found for this PIN');
    }
    loading = false;
    notifyListeners();
  }

  Future<void> openLocationSettings() => _location.openSettings();

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
