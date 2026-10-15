import 'package:local_auth/local_auth.dart';

enum BiometricOutcome { verified, noMatch, notEnrolled, unavailable }

/// Face or fingerprint check done by the phone's own system prompt.
/// Nothing is captured by this SDK; the result is only pass or fail.
abstract class BiometricProvider {
  Future<BiometricOutcome> verify({required String reason});
}

class LocalAuthBiometricProvider implements BiometricProvider {
  LocalAuthBiometricProvider({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<BiometricOutcome> verify({required String reason}) async {
    try {
      if (!await _auth.isDeviceSupported()) return BiometricOutcome.unavailable;
      final passed = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      return passed ? BiometricOutcome.verified : BiometricOutcome.noMatch;
    } on LocalAuthException catch (error) {
      switch (error.code) {
        case LocalAuthExceptionCode.noBiometricsEnrolled:
        case LocalAuthExceptionCode.noCredentialsSet:
          return BiometricOutcome.notEnrolled;
        case LocalAuthExceptionCode.userCanceled:
        case LocalAuthExceptionCode.timeout:
          return BiometricOutcome.noMatch;
        default:
          return BiometricOutcome.unavailable;
      }
    } on Exception {
      return BiometricOutcome.unavailable;
    }
  }
}
