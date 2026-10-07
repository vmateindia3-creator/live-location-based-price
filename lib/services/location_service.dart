import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../models/market_models.dart';

class LocationService {
  /// Request permission (if needed) and return the current position.
  /// Throws when the service is off or permission is denied, so the UI can
  /// show the "select location first" prompt instead of hanging.
  Future<PlaceResult> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Location service is off');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permission denied forever');
    }
    if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) {
      throw Exception('Location permission denied');
    }

    final position = await _fastPosition();
    return PlaceResult(name: 'Current location', latitude: position.latitude, longitude: position.longitude);
  }

  /// Open the right settings screen so the user can enable location access.
  Future<void> openSettings() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
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
