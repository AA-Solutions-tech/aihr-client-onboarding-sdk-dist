/// What the onboarding page can ask the phone for. The page sends
/// `{kind, params}` through the `onNativeRequest` JavaScript handler.
enum NativeKind {
  getLocation('get_location'),
  measureDistance('measure_distance'),
  checkIn('check_in'),
  enableNotifications('enable_notifications');

  const NativeKind(this.wireName);

  final String wireName;

  static NativeKind? fromWire(Object? raw) {
    for (final kind in values) {
      if (kind.wireName == raw) return kind;
    }
    return null;
  }
}

class NativeRequest {
  const NativeRequest(this.kind, this.params);

  final NativeKind kind;
  final Map<String, dynamic> params;

  /// Null when the page sent something that is not a known request.
  static NativeRequest? parse(Object? raw) {
    if (raw is! Map) return null;
    final kind = NativeKind.fromWire(raw['kind']);
    if (kind == null) return null;
    final params = raw['params'];
    return NativeRequest(
      kind,
      params is Map ? Map<String, dynamic>.from(params) : const {},
    );
  }
}

Map<String, dynamic> nativeOk([Map<String, dynamic> data = const {}]) =>
    {'ok': true, ...data};

Map<String, dynamic> nativeError(String code, [Map<String, dynamic> data = const {}]) =>
    {'ok': false, 'error': code, ...data};
