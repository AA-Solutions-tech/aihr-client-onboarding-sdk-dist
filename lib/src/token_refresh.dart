import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Fresh access token from [refreshAccessToken]. The slip itself is never exposed.
class RefreshedAccessToken {
  const RefreshedAccessToken(this.accessToken);

  final String accessToken;
}

/// Why a refresh attempt failed. Never carries token material.
enum RefreshFailure { missingInput, insecureUrl, rejected, unreachable }

/// Thrown when the renewal slip cannot produce a new access token.
class RefreshException implements Exception {
  const RefreshException(this.failure);

  final RefreshFailure failure;

  @override
  String toString() => 'RefreshException($failure)';
}

const bool _kReleaseBuild = bool.fromEnvironment('dart.vm.product');

/// Hosts a debug build may reach over plain http (local development only).
const Set<String> _kDevHosts = {'localhost', '127.0.0.1', '::1', '10.0.2.2'};

/// The refresh token is sent to [url], so it must be https. Plain http is
/// accepted only for local development hosts and never in a release build.
bool isAllowedRefreshBase(String url, {bool release = _kReleaseBuild}) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return false;
  if (uri.scheme == 'https') return true;
  return uri.scheme == 'http' && !release && _kDevHosts.contains(uri.host);
}

/// Trades a Nizamy refresh token for a fresh access token.
///
/// Calls MRHR's public refresh endpoint directly — our backend is never in
/// the path and the slip is never logged. Nizamy does not rotate: the same
/// slip stays valid until expiry/revoke ([RefreshFailure.rejected] → re-login).
/// The whole exchange must finish within [timeout]; a timeout, a failed
/// connection and a non-JSON answer all map to [RefreshFailure.unreachable].
/// [apiBaseUrl] must be https (see [isAllowedRefreshBase]).
Future<RefreshedAccessToken> refreshAccessToken({
  required String apiBaseUrl,
  required String refreshToken,
  HttpClient? client,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final base = apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  if (base.isEmpty || refreshToken.trim().isEmpty) {
    throw const RefreshException(RefreshFailure.missingInput);
  }
  if (!isAllowedRefreshBase(base)) {
    throw const RefreshException(RefreshFailure.insecureUrl);
  }
  final owned = client == null;
  final http = client ?? HttpClient();
  try {
    return await _exchange(http, base, refreshToken).timeout(timeout);
  } on RefreshException {
    rethrow;
  } on TimeoutException {
    throw const RefreshException(RefreshFailure.unreachable);
  } catch (_) {
    throw const RefreshException(RefreshFailure.unreachable);
  } finally {
    if (owned) http.close(force: true);
  }
}

Future<RefreshedAccessToken> _exchange(
  HttpClient http,
  String base,
  String refreshToken,
) async {
  final request = await http.postUrl(Uri.parse('$base/api/Account/refresh'));
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode({'refreshToken': refreshToken}));
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode == 401) {
    throw const RefreshException(RefreshFailure.rejected);
  }
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw const RefreshException(RefreshFailure.unreachable);
  }
  dynamic decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    throw const RefreshException(RefreshFailure.unreachable);
  }
  final access = decoded is Map
      ? (decoded['data'] is Map ? decoded['data']['accessToken'] : null)
      : null;
  if (access is! String || access.isEmpty) {
    throw const RefreshException(RefreshFailure.unreachable);
  }
  return RefreshedAccessToken(access);
}

/// The page's answer to "refresh the token": `{ok: true}` once the new token
/// has been delivered, otherwise `{ok: false, reason}` with `reason` one of
/// `not_configured`, `rejected`, `unreachable`.
typedef RefreshReply = Map<String, Object?>;

typedef RefreshCall = Future<RefreshedAccessToken> Function({
  required String apiBaseUrl,
  required String refreshToken,
});

/// Owns the renewal slip for the SDK. The slip lives here (Dart memory) and is
/// never given to the page, the backend or any log.
///
/// Concurrent requests (company created and a 401 at the same moment) share one
/// call. A network failure is retried once; a rejected slip is not. The whole
/// refresh, retry included, is bounded by [deadline] so the chat is never
/// locked for long on a bad network; a token that arrives after the deadline
/// is dropped, not delivered.
class TokenRefresher {
  TokenRefresher({
    String? apiBaseUrl,
    String? refreshToken,
    RefreshCall refresh = refreshAccessToken,
    Duration retryDelay = const Duration(seconds: 1),
    this.deadline = const Duration(seconds: 20),
    this.onRefreshed,
  })  : _apiBaseUrl = (apiBaseUrl ?? '').trim(),
        _refreshToken = (refreshToken ?? '').trim(),
        _refresh = refresh,
        _retryDelay = retryDelay;

  final String _apiBaseUrl;
  final String _refreshToken;
  final RefreshCall _refresh;
  final Duration _retryDelay;
  final Duration deadline;

  /// Called with the new access token after it reached the page, so the host
  /// app can keep its own copy current. A failing callback never fails the refresh.
  final void Function(String accessToken)? onRefreshed;

  Future<RefreshReply>? _inFlight;

  bool get hasInputs => _apiBaseUrl.isNotEmpty && _refreshToken.isNotEmpty;

  /// True when a refresh can be attempted: both inputs are set and the base URL
  /// is https (or a local development host in a debug build).
  bool get isConfigured => hasInputs && isAllowedRefreshBase(_apiBaseUrl);

  /// Refreshes, hands the new access token to [deliver] (which must put it into
  /// the page), then reports the outcome.
  Future<RefreshReply> run(Future<void> Function(String accessToken) deliver) {
    if (!isConfigured) return Future.value(_failed('not_configured'));
    final attempt = _Attempt();
    return _inFlight ??= _attempt(deliver, attempt)
        .timeout(deadline, onTimeout: () {
      attempt.cancelled = true;
      return _failed('unreachable');
    }).whenComplete(() => _inFlight = null);
  }

  Future<RefreshReply> _attempt(
    Future<void> Function(String accessToken) deliver,
    _Attempt attempt,
  ) async {
    for (var tries = 0; tries < 2; tries++) {
      try {
        final fresh = await _refresh(
          apiBaseUrl: _apiBaseUrl,
          refreshToken: _refreshToken,
        );
        if (attempt.cancelled) return _failed('unreachable');
        await deliver(fresh.accessToken);
        try {
          onRefreshed?.call(fresh.accessToken);
        } catch (_) {}
        return const {'ok': true};
      } on RefreshException catch (error) {
        if (error.failure == RefreshFailure.rejected ||
            error.failure == RefreshFailure.missingInput ||
            error.failure == RefreshFailure.insecureUrl) {
          return _failed('rejected');
        }
        if (tries == 0) await Future<void>.delayed(_retryDelay);
        if (attempt.cancelled) return _failed('unreachable');
      } catch (_) {
        return _failed('unreachable');
      }
    }
    return _failed('unreachable');
  }

  RefreshReply _failed(String reason) => {'ok': false, 'reason': reason};
}

class _Attempt {
  bool cancelled = false;
}
