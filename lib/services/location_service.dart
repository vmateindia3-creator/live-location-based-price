import 'package:geolocator/geolocator.dart';
import '../models/market_models.dart';

class LocationService {
  Future<PlaceResult> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Location is off');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw Exception('Location permission denied');
    }
    final p = await Geolocator.getCurrentPosition();
    return PlaceResult(name: 'Current location', latitude: p.latitude, longitude: p.longitude);
  }
}
