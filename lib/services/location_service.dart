import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../models/market_models.dart';

class LocationService {
  Future<PlaceResult> current() async {
    var serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      serviceEnabled = await _waitForLocationService();
    }
    if (!serviceEnabled) {
      throw Exception('Location is off');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      throw Exception('Location permission denied forever');
    }
    if (permission == LocationPermission.denied) {
      throw Exception('Location permission denied');
    }

    final position = await _fastPosition();
    return PlaceResult(name: 'Current location', latitude: position.latitude, longitude: position.longitude);
  }

  Future<bool> _waitForLocationService() async {
    for (var seconds = 0; seconds < 30; seconds++) {
      if (await Geolocator.isLocationServiceEnabled()) return true;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return false;
  }

  Future<Position> _fastPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 8)),
      );
    } on TimeoutException {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return last;
      rethrow;
    }
  }
}
