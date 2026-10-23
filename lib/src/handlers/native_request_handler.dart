import 'package:flutter/foundation.dart';

import 'biometric_provider.dart';
import 'location_provider.dart';
import 'native_request.dart';
import 'push_registration.dart';

/// Answers the page's `onNativeRequest` calls. Never throws: every failure
/// comes back as `{ok: false, error: <code>}` so the page can show a state.
/// Coordinates are returned to the page and are not logged here.
class NativeRequestHandler {
  NativeRequestHandler({
    LocationProvider? location,
    BiometricProvider? biometric,
    this.pushRegistration,
    this.deviceId,
  })  : _location = location ?? const GeolocatorLocationProvider(),
        _biometric = biometric ?? LocalAuthBiometricProvider();

  final LocationProvider _location;
  final BiometricProvider _biometric;
  final PushRegistrationProvider? pushRegistration;
  final String? deviceId;

  DeviceFix? _walkStart;

  Future<Map<String, dynamic>> handle(Object? raw) async {
    final request = NativeRequest.parse(raw);
    if (request == null) return nativeError('unsupported');
    try {
      switch (request.kind) {
        case NativeKind.getLocation:
          return await _getLocation();
        case NativeKind.measureDistance:
          return await _measureDistance(request.params);
        case NativeKind.registerFingerprint:
          return await _registerFingerprint(request.params);
        case NativeKind.checkIn:
          return await _checkIn(request.params);
        case NativeKind.enableNotifications:
          return await _enableNotifications();
      }
    } on LocationUnavailable catch (error) {
      return nativeError(_locationError(error.reason));
    } on Exception catch (error) {
      debugPrint('[aihr_client_onboarding_sdk] ${request.kind.wireName} failed: ${error.runtimeType}');
      return nativeError('failed');
    }
  }

  Future<Map<String, dynamic>> _getLocation() async {
    final fix = await _location.currentFix();
    final address = await _location.addressFor(fix.latitude, fix.longitude);
    return nativeOk({
      'latitude': fix.latitude,
      'longitude': fix.longitude,
      'accuracy': fix.accuracy.round(),
      if (address != null) 'address': address,
    });
  }

  Future<Map<String, dynamic>> _measureDistance(Map<String, dynamic> params) async {
    final phase = params['phase'];
    if (phase == 'start') {
      _walkStart = await _location.currentFix();
      return nativeOk({'distance': 0});
    }
    final start = _walkStart;
    if (start == null || (phase != 'sample' && phase != 'finish')) {
      return nativeError('not_started');
    }
    final now = await _location.currentFix();
    final distance = _location.distanceMeters(start, now);
    if (phase == 'finish') _walkStart = null;
    return nativeOk({'distance': distance.round()});
  }

  Future<Map<String, dynamic>> _checkIn(Map<String, dynamic> params) async {
    final fix = await _location.currentFix();
    final gate = params['gate'];
    if (gate is Map) {
      final latitude = (gate['latitude'] as num?)?.toDouble();
      final longitude = (gate['longitude'] as num?)?.toDouble();
      final radius = (gate['radius'] as num?)?.toDouble();
      if (latitude != null && longitude != null && radius != null) {
        final distance = _location.distanceMeters(
          fix,
          DeviceFix(latitude: latitude, longitude: longitude, accuracy: 0),
        );
        if (distance > radius) {
          return nativeError('outside', {'distance': distance.round()});
        }
      }
    }
    if (params['method'] == 'none') {
      return nativeOk({'latitude': fix.latitude, 'longitude': fix.longitude});
    }
    final reason = params['reason'] is String ? params['reason'] as String : 'Verify it is you';
    switch (await _biometric.verify(reason: reason)) {
      case BiometricOutcome.verified:
        final id = deviceId?.trim() ?? '';
        return nativeOk({
          'latitude': fix.latitude,
          'longitude': fix.longitude,
          if (id.isNotEmpty) 'deviceId': id,
        });
      case BiometricOutcome.noMatch:
        return nativeError('no_match');
      case BiometricOutcome.notEnrolled:
        return nativeError('not_enrolled');
      case BiometricOutcome.unavailable:
        return nativeError('unavailable');
    }
  }

  /// The fingerprint step on its own: only the phone's biometric prompt, no
  /// location. Answers with the device id Nizamy's register-fingerprint needs.
  Future<Map<String, dynamic>> _registerFingerprint(Map<String, dynamic> params) async {
    final reason = params['reason'] is String ? params['reason'] as String : 'Register your fingerprint';
    final outcome = await _biometric.verify(reason: reason);
    if (outcome != BiometricOutcome.verified) return _biometricError(outcome);
    final id = deviceId?.trim() ?? '';
    if (id.isEmpty) return nativeError('no_device_id');
    return nativeOk({'deviceId': id});
  }

  Map<String, dynamic> _biometricError(BiometricOutcome outcome) {
    switch (outcome) {
      case BiometricOutcome.noMatch:
        return nativeError('no_match');
      case BiometricOutcome.notEnrolled:
        return nativeError('not_enrolled');
      case BiometricOutcome.verified:
      case BiometricOutcome.unavailable:
        return nativeError('unavailable');
    }
  }

  Future<Map<String, dynamic>> _enableNotifications() async {
    final provider = pushRegistration;
    if (provider == null) return nativeError('unsupported');
    final registration = await provider();
    if (registration == null) return nativeError('denied');
    return nativeOk({
      'pushToken': registration.token,
      'platform': registration.platform,
      'deviceId': registration.deviceId,
    });
  }

  String _locationError(LocationFailure reason) {
    switch (reason) {
      case LocationFailure.permissionDenied:
        return 'permission_denied';
      case LocationFailure.serviceDisabled:
        return 'location_disabled';
      case LocationFailure.timeout:
        return 'timeout';
      case LocationFailure.failed:
        return 'failed';
    }
  }
}
