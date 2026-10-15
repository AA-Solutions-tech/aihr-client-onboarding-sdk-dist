import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class DeviceFix {
  const DeviceFix({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
  });

  final double latitude;
  final double longitude;
  final double accuracy;
}

enum LocationFailure { permissionDenied, serviceDisabled, timeout, failed }

class LocationUnavailable implements Exception {
  const LocationUnavailable(this.reason);

  final LocationFailure reason;
}

/// Where the phone is. The host app can pass its own implementation.
abstract class LocationProvider {
  Future<DeviceFix> currentFix();

  /// A short readable place name for a point, or null when none is available.
  Future<String?> addressFor(double latitude, double longitude);

  double distanceMeters(DeviceFix from, DeviceFix to);
}

class GeolocatorLocationProvider implements LocationProvider {
  const GeolocatorLocationProvider({this.timeout = const Duration(seconds: 15)});

  final Duration timeout;

  @override
  Future<DeviceFix> currentFix() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationUnavailable(LocationFailure.serviceDisabled);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const LocationUnavailable(LocationFailure.permissionDenied);
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: timeout,
        ),
      );
      return DeviceFix(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );
    } on Exception {
      throw const LocationUnavailable(LocationFailure.timeout);
    }
  }

  @override
  Future<String?> addressFor(double latitude, double longitude) async {
    try {
      final places = await Geocoding().placemarkFromCoordinates(latitude, longitude);
      if (places.isEmpty) return null;
      final place = places.first;
      final parts = <String>[
        if ((place.subLocality ?? '').isNotEmpty) place.subLocality!,
        if ((place.locality ?? '').isNotEmpty) place.locality!,
      ];
      if (parts.isEmpty && (place.street ?? '').isNotEmpty) return place.street;
      return parts.isEmpty ? null : parts.join(', ');
    } on Exception {
      return null;
    }
  }

  @override
  double distanceMeters(DeviceFix from, DeviceFix to) => Geolocator.distanceBetween(
        from.latitude,
        from.longitude,
        to.latitude,
        to.longitude,
      );
}
