import 'package:aihr_client_onboarding_sdk/src/handlers/handlers.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLocation implements LocationProvider {
  _FakeLocation(this.fixes, {this.failure, this.address});

  final List<DeviceFix> fixes;
  final LocationFailure? failure;
  final String? address;
  int _calls = 0;

  @override
  Future<DeviceFix> currentFix() async {
    if (failure != null) throw LocationUnavailable(failure!);
    return fixes[_calls++ < fixes.length ? _calls - 1 : fixes.length - 1];
  }

  @override
  Future<String?> addressFor(double latitude, double longitude) async => address;

  @override
  double distanceMeters(DeviceFix from, DeviceFix to) =>
      ((to.latitude - from.latitude).abs() * 111000) +
      ((to.longitude - from.longitude).abs() * 111000);
}

class _FakeBiometric implements BiometricProvider {
  _FakeBiometric(this.outcome);

  final BiometricOutcome outcome;
  String? lastReason;

  @override
  Future<BiometricOutcome> verify({required String reason}) async {
    lastReason = reason;
    return outcome;
  }
}

const _here = DeviceFix(latitude: 24.7136, longitude: 46.6753, accuracy: 7.6);

NativeRequestHandler _handler({
  LocationProvider? location,
  BiometricOutcome outcome = BiometricOutcome.verified,
  PushRegistrationProvider? push,
  String? deviceId,
}) =>
    NativeRequestHandler(
      location: location ?? _FakeLocation([_here], address: 'Al Malqa, Riyadh'),
      biometric: _FakeBiometric(outcome),
      pushRegistration: push,
      deviceId: deviceId,
    );

void main() {
  group('request parsing', () {
    test('rejects anything that is not a known request', () async {
      final handler = _handler();
      expect(await handler.handle(null), {'ok': false, 'error': 'unsupported'});
      expect(await handler.handle('get_location'), {'ok': false, 'error': 'unsupported'});
      expect(await handler.handle({'kind': 'format_disk'}), {'ok': false, 'error': 'unsupported'});
    });
  });

  group('get_location', () {
    test('returns coordinates, rounded accuracy and the address', () async {
      final result = await _handler().handle({'kind': 'get_location'});
      expect(result['ok'], true);
      expect(result['latitude'], 24.7136);
      expect(result['longitude'], 46.6753);
      expect(result['accuracy'], 8);
      expect(result['address'], 'Al Malqa, Riyadh');
    });

    test('leaves the address out when none is found', () async {
      final handler = _handler(location: _FakeLocation([_here]));
      final result = await handler.handle({'kind': 'get_location'});
      expect(result.containsKey('address'), false);
    });

    test('reports each failure with its own code', () async {
      final expected = {
        LocationFailure.permissionDenied: 'permission_denied',
        LocationFailure.serviceDisabled: 'location_disabled',
        LocationFailure.timeout: 'timeout',
        LocationFailure.failed: 'failed',
      };
      for (final entry in expected.entries) {
        final handler = _handler(location: _FakeLocation([_here], failure: entry.key));
        final result = await handler.handle({'kind': 'get_location'});
        expect(result, {'ok': false, 'error': entry.value});
      }
    });
  });

  group('measure_distance', () {
    test('measures from the start point and ends the walk on finish', () async {
      const away = DeviceFix(latitude: 24.7139, longitude: 46.6753, accuracy: 5);
      final handler = _handler(location: _FakeLocation([_here, away, away]));
      final start = await handler.handle({'kind': 'measure_distance', 'params': {'phase': 'start'}});
      expect(start, {'ok': true, 'distance': 0});
      final sample = await handler.handle({'kind': 'measure_distance', 'params': {'phase': 'sample'}});
      expect(sample['distance'], inInclusiveRange(30, 40));
      final finish = await handler.handle({'kind': 'measure_distance', 'params': {'phase': 'finish'}});
      expect(finish['ok'], true);
      final after = await handler.handle({'kind': 'measure_distance', 'params': {'phase': 'sample'}});
      expect(after, {'ok': false, 'error': 'not_started'});
    });

    test('refuses to sample before a walk was started', () async {
      final result = await _handler().handle({'kind': 'measure_distance', 'params': {'phase': 'sample'}});
      expect(result, {'ok': false, 'error': 'not_started'});
    });
  });

  group('check_in', () {
    test('passes inside the gate when the biometric verifies', () async {
      final result = await _handler().handle({
        'kind': 'check_in',
        'params': {
          'gate': {'latitude': 24.7136, 'longitude': 46.6753, 'radius': 75},
          'reason': 'Check in',
        },
      });
      expect(result, {'ok': true, 'latitude': 24.7136, 'longitude': 46.6753});
    });

    test('returns the device id after a verified biometric, for fingerprint registration', () async {
      final result = await _handler(deviceId: ' phone-1 ').handle({'kind': 'check_in'});
      expect(result, {'ok': true, 'latitude': 24.7136, 'longitude': 46.6753, 'deviceId': 'phone-1'});
    });

    test('never returns the device id without a verified biometric', () async {
      final later = await _handler(deviceId: 'phone-1').handle({
        'kind': 'check_in',
        'params': {'method': 'none'},
      });
      expect(later.containsKey('deviceId'), isFalse);
      final failed = await _handler(deviceId: 'phone-1', outcome: BiometricOutcome.noMatch)
          .handle({'kind': 'check_in'});
      expect(failed, {'ok': false, 'error': 'no_match'});
    });

    test('stops outside the gate before asking for the biometric', () async {
      final biometric = _FakeBiometric(BiometricOutcome.verified);
      final handler = NativeRequestHandler(
        location: _FakeLocation([_here]),
        biometric: biometric,
      );
      final result = await handler.handle({
        'kind': 'check_in',
        'params': {
          'gate': {'latitude': 24.7176, 'longitude': 46.6753, 'radius': 75},
        },
      });
      expect(result['ok'], false);
      expect(result['error'], 'outside');
      expect(result['distance'], greaterThan(75));
      expect(biometric.lastReason, isNull);
    });

    test('skips the biometric prompt when the owner chose to verify later', () async {
      final biometric = _FakeBiometric(BiometricOutcome.noMatch);
      final handler = NativeRequestHandler(location: _FakeLocation([_here]), biometric: biometric);
      final result = await handler.handle({
        'kind': 'check_in',
        'params': {'method': 'none'},
      });
      expect(result, {'ok': true, 'latitude': 24.7136, 'longitude': 46.6753});
      expect(biometric.lastReason, isNull);
    });

    test('maps each biometric outcome to its own code', () async {
      final expected = {
        BiometricOutcome.noMatch: 'no_match',
        BiometricOutcome.notEnrolled: 'not_enrolled',
        BiometricOutcome.unavailable: 'unavailable',
      };
      for (final entry in expected.entries) {
        final result = await _handler(outcome: entry.key).handle({'kind': 'check_in'});
        expect(result, {'ok': false, 'error': entry.value});
      }
    });
  });

  group('enable_notifications', () {
    test('is unsupported when the host gave no push provider', () async {
      final result = await _handler().handle({'kind': 'enable_notifications'});
      expect(result, {'ok': false, 'error': 'unsupported'});
    });

    test('returns the registration from the host app', () async {
      final handler = _handler(
        push: () async => const PushRegistration(token: 't', platform: 'android', deviceId: 'd'),
      );
      expect(await handler.handle({'kind': 'enable_notifications'}),
          {'ok': true, 'pushToken': 't', 'platform': 'android', 'deviceId': 'd'});
    });

    test('is denied when the host returns nothing', () async {
      final handler = _handler(push: () async => null);
      expect(await handler.handle({'kind': 'enable_notifications'}), {'ok': false, 'error': 'denied'});
    });

    test('never throws when the host provider fails', () async {
      final handler = _handler(push: () async => throw Exception('boom'));
      expect(await handler.handle({'kind': 'enable_notifications'}), {'ok': false, 'error': 'failed'});
    });
  });
}
