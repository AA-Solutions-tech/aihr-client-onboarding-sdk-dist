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

/// `permissionBlocked`: denied for good (Android no longer shows the prompt); only the app settings can allow it.
enum LocationFailure { permissionDenied, permissionBlocked, serviceDisabled, timeout, failed }

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

/// Optional: a provider that can also return the phone's last known position at once (no GPS wait).
/// Used to centre the map as soon as the location card opens; a fresh fix follows.
abstract class LastKnownLocation {
  /// The last known position, or null when the phone has none. Asks for permission like [LocationProvider.currentFix].
  Future<DeviceFix?> lastKnownFix();
}

class GeolocatorLocationProvider implements LocationProvider, LastKnownLocation {
  const GeolocatorLocationProvider({this.timeout = const Duration(seconds: 15)});

  final Duration timeout;

  Future<void> _ensureAllowed() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationUnavailable(LocationFailure.serviceDisabled);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationUnavailable(LocationFailure.permissionBlocked);
    }
    if (permission == LocationPermission.denied) {
      throw const LocationUnavailable(LocationFailure.permissionDenied);
    }
  }

  @override
  Future<DeviceFix?> lastKnownFix() async {
    await _ensureAllowed();
    final position = await Geolocator.getLastKnownPosition();
    if (position == null) return null;
    return DeviceFix(latitude: position.latitude, longitude: position.longitude, accuracy: position.accuracy);
  }

  @override
  Future<DeviceFix> currentFix() async {
    await _ensureAllowed();
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
