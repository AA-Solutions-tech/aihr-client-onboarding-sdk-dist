// `flutter_inappwebview`'s InAppWebView needs a real platform and cannot be
// mounted in a plain `flutter test`, so these tests cover the pure logic. The
// widget itself is verified on a device via the example app.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aihr_client_onboarding_sdk/aihr_client_onboarding_sdk.dart';
import 'package:aihr_client_onboarding_sdk/src/navigation_policy.dart';
import 'package:aihr_client_onboarding_sdk/src/onboarding_scripts.dart';
import 'package:aihr_client_onboarding_sdk/src/token_refresh.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildSetAuthTokenScript', () {
    test('embeds the token as an escaped JS string literal', () {
      expect(
        buildSetAuthTokenScript('abc.def.ghi'),
        'window.AIHR_ONBOARDING && window.AIHR_ONBOARDING.setAuthToken("abc.def.ghi");',
      );
    });

    test('cannot be broken out of with quotes or backslashes', () {
      final quoted = buildSetAuthTokenScript('a"b');
      expect(quoted, contains(r'a\"b'));
      final slashed = buildSetAuthTokenScript(r'a\b');
      expect(slashed, contains(r'a\\b'));
    });
  });

  group('buildSetApiEnvironmentScript', () {
    test('embeds the base URL as an escaped JS string literal', () {
      expect(
        buildSetApiEnvironmentScript('https://api.nizamy.app'),
        'window.AIHR_ONBOARDING && window.AIHR_ONBOARDING.setApiEnvironment("https://api.nizamy.app");',
      );
    });

    test('cannot be broken out of with quotes or backslashes', () {
      expect(buildSetApiEnvironmentScript('a"b'), contains(r'a\"b'));
      expect(buildSetApiEnvironmentScript(r'a\b'), contains(r'a\\b'));
    });
  });

  group('buildSetLanguageScript', () {
    test('calls setLanguage with the language', () {
      expect(
        buildSetLanguageScript('ar'),
        'window.AIHR_ONBOARDING && window.AIHR_ONBOARDING.setLanguage("ar");',
      );
    });
  });

  group('OnboardingResult.fromHandlerArgs', () {
    test('reads the access token', () {
      final result = OnboardingResult.fromHandlerArgs([
        {'accessToken': 'tok'}
      ]);
      expect(result.accessToken, 'tok');
    });

    test('is empty for missing, empty or malformed arguments', () {
      expect(OnboardingResult.fromHandlerArgs([]).accessToken, isNull);
      expect(OnboardingResult.fromHandlerArgs(['x']).accessToken, isNull);
      expect(
        OnboardingResult.fromHandlerArgs([
          {'accessToken': ''}
        ]).accessToken,
        isNull,
      );
      expect(
        OnboardingResult.fromHandlerArgs([
          {'accessToken': 5}
        ]).accessToken,
        isNull,
      );
    });
  });

  group('isAllowedNavigation', () {
    final base = Uri.parse('https://hr.example.com/HR/aihr-client-onboarding-app');

    test('allows the same origin', () {
      expect(isAllowedNavigation(Uri.parse('https://hr.example.com/HR/x?y=1'), base), isTrue);
    });

    test('blocks other hosts, schemes and ports', () {
      expect(isAllowedNavigation(Uri.parse('https://evil.example.com/'), base), isFalse);
      expect(isAllowedNavigation(Uri.parse('http://hr.example.com/'), base), isFalse);
      expect(isAllowedNavigation(Uri.parse('https://hr.example.com:8443/'), base), isFalse);
      expect(isAllowedNavigation(Uri.parse('javascript:alert(1)'), base), isFalse);
      expect(isAllowedNavigation(null, base), isFalse);
    });

    test('allows only about:blank among about: URLs', () {
      expect(isAllowedNavigation(Uri.parse('about:blank'), base), isTrue);
      expect(isAllowedNavigation(Uri.parse('about:srcdoc'), base), isFalse);
    });
  });

  group('refreshAccessToken', () {
    late HttpServer server;
    late String base;
    int status = 200;
    String body = '';

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${server.port}';
      status = 200;
      body = '';
      server.listen((request) async {
        request.response.statusCode = status;
        request.response.headers.contentType = ContentType.json;
        request.response.write(body);
        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('returns the new access token on success', () async {
      body = jsonEncode({
        'data': {'accessToken': 'new-access', 'refreshToken': 'same-slip'}
      });
      final result = await refreshAccessToken(
        apiBaseUrl: base,
        refreshToken: 'slip',
      );
      expect(result.accessToken, 'new-access');
    });

    test('rejects empty inputs without any network call', () async {
      await server.close(force: true);
      expect(
        refreshAccessToken(apiBaseUrl: '', refreshToken: 'slip'),
        throwsA(isA<RefreshException>().having(
          (e) => e.failure,
          'failure',
          RefreshFailure.missingInput,
        )),
      );
      expect(
        refreshAccessToken(apiBaseUrl: base, refreshToken: '  '),
        throwsA(isA<RefreshException>().having(
          (e) => e.failure,
          'failure',
          RefreshFailure.missingInput,
        )),
      );
    });

    test('maps 401 to rejected (dead slip, host must re-authenticate)',
        () async {
      status = 401;
      body = 'Invalid or expired refresh token.';
      expect(
        refreshAccessToken(apiBaseUrl: base, refreshToken: 'dead'),
        throwsA(isA<RefreshException>().having(
          (e) => e.failure,
          'failure',
          RefreshFailure.rejected,
        )),
      );
    });

    test('maps server errors and malformed bodies to unreachable', () async {
      status = 500;
      body = 'boom';
      expect(
        refreshAccessToken(apiBaseUrl: base, refreshToken: 'slip'),
        throwsA(isA<RefreshException>().having(
          (e) => e.failure,
          'failure',
          RefreshFailure.unreachable,
        )),
      );
      status = 200;
      body = jsonEncode({
        'data': {'refreshToken': 'same-slip'}
      });
      expect(
        refreshAccessToken(apiBaseUrl: base, refreshToken: 'slip'),
        throwsA(isA<RefreshException>().having(
          (e) => e.failure,
          'failure',
          RefreshFailure.unreachable,
        )),
      );
    });
  });

  group('TokenRefresher', () {
    const fast = Duration(milliseconds: 1);

    test('is not configured without a slip or a base URL', () async {
      var delivered = false;
      for (final refresher in [
        TokenRefresher(),
        TokenRefresher(apiBaseUrl: 'https://x', refreshToken: ' '),
        TokenRefresher(apiBaseUrl: '', refreshToken: 'slip'),
      ]) {
        expect(refresher.isConfigured, isFalse);
        final reply = await refresher.run((_) async => delivered = true);
        expect(reply, {'ok': false, 'reason': 'not_configured'});
      }
      expect(delivered, isFalse);
    });

    test('delivers the new access token and reports ok', () async {
      String? seen;
      final refresher = TokenRefresher(
        apiBaseUrl: 'https://api.example.com',
        refreshToken: 'slip',
        retryDelay: fast,
        refresh: ({required apiBaseUrl, required refreshToken}) async {
          expect(apiBaseUrl, 'https://api.example.com');
          expect(refreshToken, 'slip');
          return const RefreshedAccessToken('fresh.access');
        },
      );
      final reply = await refresher.run((token) async => seen = token);
      expect(reply, {'ok': true});
      expect(seen, 'fresh.access');
    });

    test('a rejected slip is final: no retry, reason rejected', () async {
      var calls = 0;
      final refresher = TokenRefresher(
        apiBaseUrl: 'https://api.example.com',
        refreshToken: 'dead',
        retryDelay: fast,
        refresh: ({required apiBaseUrl, required refreshToken}) async {
          calls++;
          throw const RefreshException(RefreshFailure.rejected);
        },
      );
      expect(await refresher.run((_) async {}), {'ok': false, 'reason': 'rejected'});
      expect(calls, 1);
    });

    test('a network failure is retried once, then succeeds', () async {
      var calls = 0;
      final refresher = TokenRefresher(
        apiBaseUrl: 'https://api.example.com',
        refreshToken: 'slip',
        retryDelay: fast,
        refresh: ({required apiBaseUrl, required refreshToken}) async {
          calls++;
          if (calls == 1) throw const RefreshException(RefreshFailure.unreachable);
          return const RefreshedAccessToken('fresh.access');
        },
      );
      expect(await refresher.run((_) async {}), {'ok': true});
      expect(calls, 2);
    });

    test('two network failures report unreachable', () async {
      var calls = 0;
      final refresher = TokenRefresher(
        apiBaseUrl: 'https://api.example.com',
        refreshToken: 'slip',
        retryDelay: fast,
        refresh: ({required apiBaseUrl, required refreshToken}) async {
          calls++;
          throw const RefreshException(RefreshFailure.unreachable);
        },
      );
      expect(await refresher.run((_) async {}), {'ok': false, 'reason': 'unreachable'});
      expect(calls, 2);
    });

    test('simultaneous requests share one refresh call', () async {
      var calls = 0;
      final gate = Completer<void>();
      final refresher = TokenRefresher(
        apiBaseUrl: 'https://api.example.com',
        refreshToken: 'slip',
        retryDelay: fast,
        refresh: ({required apiBaseUrl, required refreshToken}) async {
          calls++;
          await gate.future;
          return const RefreshedAccessToken('fresh.access');
        },
      );
      final first = refresher.run((_) async {});
      final second = refresher.run((_) async {});
      gate.complete();
      expect(await first, {'ok': true});
      expect(await second, {'ok': true});
      expect(calls, 1);
      expect(await refresher.run((_) async {}), {'ok': true});
      expect(calls, 2);
    });

    test('a delivery failure is reported as unreachable, not thrown', () async {
      final refresher = TokenRefresher(
        apiBaseUrl: 'https://api.example.com',
        refreshToken: 'slip',
        retryDelay: fast,
        refresh: ({required apiBaseUrl, required refreshToken}) async =>
            const RefreshedAccessToken('fresh.access'),
      );
      final reply = await refresher.run((_) async => throw StateError('page gone'));
      expect(reply, {'ok': false, 'reason': 'unreachable'});
    });

    test('refreshAccessToken tolerates a trailing slash on the base URL', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      String? path;
      server.listen((request) async {
        path = request.uri.path;
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"data":{"accessToken":"a.b.c"}}');
        await request.response.close();
      });
      final result = await refreshAccessToken(
        apiBaseUrl: 'http://127.0.0.1:${server.port}//',
        refreshToken: 'slip',
      );
      expect(result.accessToken, 'a.b.c');
      expect(path, '/api/Account/refresh');
      await server.close(force: true);
    });
  });

  group('refresh URL safety', () {
    test('https is allowed, http only for local development hosts in debug', () {
      expect(isAllowedRefreshBase('https://api.nizamy.app'), isTrue);
      expect(isAllowedRefreshBase('http://localhost:8001'), isTrue);
      expect(isAllowedRefreshBase('http://127.0.0.1:8001'), isTrue);
      expect(isAllowedRefreshBase('http://10.0.2.2:8001'), isTrue);
      expect(isAllowedRefreshBase('http://api.nizamy.app'), isFalse);
      expect(isAllowedRefreshBase('http://192.168.1.20'), isFalse);
    });

    test('a release build never allows plain http, not even localhost', () {
      expect(isAllowedRefreshBase('https://api.nizamy.app', release: true), isTrue);
      expect(isAllowedRefreshBase('http://localhost:8001', release: true), isFalse);
    });

    test('rejects other schemes and junk', () {
      for (final url in ['', 'api.nizamy.app', 'ftp://api.nizamy.app', 'https://', 'javascript:alert(1)']) {
        expect(isAllowedRefreshBase(url), isFalse, reason: url);
      }
    });

    test('refreshAccessToken refuses an insecure URL before any network call', () async {
      await expectLater(
        refreshAccessToken(apiBaseUrl: 'http://api.nizamy.app', refreshToken: 'slip'),
        throwsA(isA<RefreshException>()
            .having((e) => e.failure, 'failure', RefreshFailure.insecureUrl)),
      );
    });

    test('TokenRefresher is not configured for an insecure URL (host push fallback)', () async {
      final refresher = TokenRefresher(
        apiBaseUrl: 'http://api.nizamy.app',
        refreshToken: 'slip',
      );
      expect(refresher.hasInputs, isTrue);
      expect(refresher.isConfigured, isFalse);
      expect(await refresher.run((_) async {}), {'ok': false, 'reason': 'not_configured'});
    });
  });

  group('TokenRefresher deadline and host callback', () {
    test('a hung refresh gives up at the deadline and drops a late token', () async {
      final gate = Completer<RefreshedAccessToken>();
      var delivered = false;
      final refresher = TokenRefresher(
        apiBaseUrl: 'https://api.example.com',
        refreshToken: 'slip',
        deadline: const Duration(milliseconds: 50),
        refresh: ({required apiBaseUrl, required refreshToken}) => gate.future,
      );
      final reply = await refresher.run((_) async => delivered = true);
      expect(reply, {'ok': false, 'reason': 'unreachable'});

      gate.complete(const RefreshedAccessToken('too.late'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delivered, isFalse);
    });

    test('after a timeout the next request starts a fresh refresh', () async {
      var calls = 0;
      final refresher = TokenRefresher(
        apiBaseUrl: 'https://api.example.com',
        refreshToken: 'slip',
        deadline: const Duration(milliseconds: 50),
        retryDelay: const Duration(milliseconds: 1),
        refresh: ({required apiBaseUrl, required refreshToken}) async {
          calls++;
          if (calls == 1) await Completer<void>().future;
          return const RefreshedAccessToken('fresh.access');
        },
      );
      expect(await refresher.run((_) async {}), {'ok': false, 'reason': 'unreachable'});
      expect(await refresher.run((_) async {}), {'ok': true});
    });

    test('onRefreshed gets the new access token after delivery', () async {
      final order = <String>[];
      final refresher = TokenRefresher(
        apiBaseUrl: 'https://api.example.com',
        refreshToken: 'slip',
        refresh: ({required apiBaseUrl, required refreshToken}) async =>
            const RefreshedAccessToken('fresh.access'),
        onRefreshed: (token) => order.add('host:$token'),
      );
      await refresher.run((token) async => order.add('page:$token'));
      expect(order, ['page:fresh.access', 'host:fresh.access']);
    });

    test('a throwing onRefreshed does not fail the refresh', () async {
      final refresher = TokenRefresher(
        apiBaseUrl: 'https://api.example.com',
        refreshToken: 'slip',
        refresh: ({required apiBaseUrl, required refreshToken}) async =>
            const RefreshedAccessToken('fresh.access'),
        onRefreshed: (_) => throw StateError('host bug'),
      );
      expect(await refresher.run((_) async {}), {'ok': true});
    });

    test('a stalled server hits the exchange timeout and maps to unreachable', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {});
      await expectLater(
        refreshAccessToken(
          apiBaseUrl: 'http://127.0.0.1:${server.port}',
          refreshToken: 'slip',
          timeout: const Duration(milliseconds: 100),
        ),
        throwsA(isA<RefreshException>()
            .having((e) => e.failure, 'failure', RefreshFailure.unreachable)),
      );
      await server.close(force: true);
    });
  });
}
