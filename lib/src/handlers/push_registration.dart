class PushRegistration {
  const PushRegistration({
    required this.token,
    required this.platform,
    required this.deviceId,
  });

  final String token;

  /// 'android' or 'ios'.
  final String platform;
  final String deviceId;
}

/// The host app owns push notifications (Firebase and the notification
/// permission). It returns the device's registration, or null if the owner
/// declined or push is not available.
typedef PushRegistrationProvider = Future<PushRegistration?> Function();
