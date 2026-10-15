import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'handlers/handlers.dart';
import 'navigation_policy.dart';
import 'onboarding_result.dart';
import 'onboarding_scripts.dart';
import 'token_refresh.dart';

/// Where the always-current build of the onboarding chat page is hosted.
/// Changing the page's screens or the onboarding agent reaches every installed
/// app on the next backend deploy, with no app release. Override for local
/// development with `--dart-define=AIHR_ONBOARDING_BASE_URL=...`.
const String _kBaseUrl = String.fromEnvironment(
  'AIHR_ONBOARDING_BASE_URL',
  defaultValue: 'https://hr.aasolutions.tech/HR/aihr-client-onboarding-app',
);

/// 'ar' only for an explicit Arabic code; everything else is English.
String _normalizeLanguage(String? raw) => raw == 'ar' ? 'ar' : 'en';

/// The NizamyAI client onboarding chat.
///
/// Pass the owner's current access token in [authToken], plus the Nizamy
/// [refreshToken] and [apiBaseUrl] from native login. The widget then renews
/// the access token itself when the company is created (the new company claims
/// only arrive through the refresh) and whenever the backend answers 401, and
/// pushes the new token into the page without reloading it.
///
/// ```dart
/// AiHrClientOnboardingWidget(
///   authToken: accessToken,
///   refreshToken: refreshToken,
///   apiBaseUrl: 'https://api.nizamy.app',
///   onComplete: (result) => openDashboard(),
///   onAuthError: (reason) => reauthenticate(),
/// )
/// ```
class AiHrClientOnboardingWidget extends StatefulWidget {
  const AiHrClientOnboardingWidget({
    super.key,
    required this.authToken,
    this.refreshToken,
    this.apiBaseUrl,
    this.language,
    this.onComplete,
    this.onAuthError,
    this.onCompanyCreated,
    this.onTokenRefreshed,
    this.locationProvider,
    this.biometricProvider,
    this.pushRegistration,
    this.deviceId,
  });

  /// The owner's current access token. Held in memory by the page only; it is
  /// never written to disk or put in a URL.
  final String authToken;

  /// The Nizamy refresh token from native login. Used only inside this widget
  /// to call MRHR's refresh endpoint; it is never sent to the page, to our
  /// backend, to a log or to disk. It does not rotate and lasts about 90 days,
  /// so treat it like a password. Without it (and [apiBaseUrl]) the widget
  /// cannot refresh and falls back to the host pushing a new [authToken].
  final String? refreshToken;

  /// MRHR base URL for the environment the owner logged in to (live or test).
  /// Used for the refresh call, and also sent to the backend with every turn so
  /// it validates the token in that environment. It must be one of the
  /// environments the backend knows; an unknown one is refused.
  final String? apiBaseUrl;

  /// Explicit language override ('en' or 'ar'). Leave null to follow the
  /// ambient `Localizations.localeOf(context)`.
  final String? language;

  /// Called when the owner finishes onboarding. The host app can open its
  /// dashboard.
  final void Function(OnboardingResult result)? onComplete;

  /// Called when the backend rejects the token and it could not be recovered.
  /// The host app owns re-authentication.
  final void Function(String? reason)? onAuthError;

  /// Notification only: called right after the company is created. With
  /// [refreshToken] and [apiBaseUrl] set the widget refreshes the token on its
  /// own and the host app does nothing. Without them the host is expected to
  /// refresh and rebuild this widget with the new [authToken].
  final VoidCallback? onCompanyCreated;

  /// Called with the new access token every time the widget refreshes it, so
  /// the host app can store the current one (its own copy goes stale otherwise,
  /// for example when the app restarts in the middle of onboarding).
  final void Function(String accessToken)? onTokenRefreshed;

  /// Where the phone is. Defaults to the device GPS (geolocator).
  final LocationProvider? locationProvider;

  /// Face or fingerprint check. Defaults to the phone's own biometric prompt.
  final BiometricProvider? biometricProvider;

  /// The host app's push registration (token, platform, device id), used when
  /// the owner turns notifications on. Null means push is not offered.
  final PushRegistrationProvider? pushRegistration;

  /// This phone's id, the same one the host app sends to Nizamy's
  /// `register-fingerprint`. After a verified fingerprint or face check-in it
  /// is sent with the check-in so the owner's fingerprint is registered and
  /// the account is activated. Null means check-in without registration.
  final String? deviceId;

  @override
  State<AiHrClientOnboardingWidget> createState() =>
      _AiHrClientOnboardingWidgetState();
}

class _AiHrClientOnboardingWidgetState
    extends State<AiHrClientOnboardingWidget> {
  final Uri _base = Uri.parse(_kBaseUrl);
  InAppWebViewController? _controller;
  String _language = 'en';
  bool _loadFailed = false;
  late TokenRefresher _refresher = _buildRefresher();
  String? _latestToken;
  late final NativeRequestHandler _native = NativeRequestHandler(
    location: widget.locationProvider,
    biometric: widget.biometricProvider,
    pushRegistration: widget.pushRegistration,
    deviceId: widget.deviceId,
  );

  TokenRefresher _buildRefresher() {
    final refresher = TokenRefresher(
      apiBaseUrl: widget.apiBaseUrl,
      refreshToken: widget.refreshToken,
      onRefreshed: widget.onTokenRefreshed,
    );
    if (refresher.hasInputs && !refresher.isConfigured) {
      debugPrint(
        '[aihr_client_onboarding_sdk] token refresh is off: apiBaseUrl must be https.',
      );
    }
    return refresher;
  }

  /// The token the page should hold: the newest one this widget refreshed,
  /// unless the host has since pushed a different one.
  String get _currentToken => _latestToken ?? widget.authToken;

  Future<Map<String, Object?>> _refreshToken() => _refresher.run((token) async {
        _latestToken = token;
        await _inject(buildSetAuthTokenScript(token));
      });

  String _resolveLanguage() =>
      _normalizeLanguage(widget.language ?? Localizations.localeOf(context).languageCode);

  Uri get _initialUrl => _base.replace(queryParameters: {'lang': _language});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final resolved = _resolveLanguage();
    if (resolved != _language) {
      _language = resolved;
      _inject(buildSetLanguageScript(resolved));
    }
  }

  @override
  void didUpdateWidget(covariant AiHrClientOnboardingWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshToken != oldWidget.refreshToken ||
        widget.apiBaseUrl != oldWidget.apiBaseUrl) {
      _refresher = _buildRefresher();
    }
    if (widget.apiBaseUrl != oldWidget.apiBaseUrl) _injectEnvironment();
    if (widget.authToken != oldWidget.authToken) {
      _latestToken = null;
      _inject(buildSetAuthTokenScript(widget.authToken));
    }
    final resolved = _resolveLanguage();
    if (resolved != _language) {
      _language = resolved;
      _inject(buildSetLanguageScript(resolved));
    }
  }

  Future<void> _injectEnvironment() async {
    final environment = (widget.apiBaseUrl ?? '').trim();
    if (environment.isNotEmpty) {
      await _inject(buildSetApiEnvironmentScript(environment));
    }
  }

  Future<void> _inject(String script) async {
    final controller = _controller;
    if (controller == null) return;
    await controller.evaluateJavascript(source: script);
  }

  void _retry() {
    setState(() => _loadFailed = false);
    _controller?.loadUrl(urlRequest: URLRequest(url: WebUri.uri(_initialUrl)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loadFailed) {
      return _LoadErrorView(language: _language, onRetry: _retry);
    }
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri.uri(_initialUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        useShouldOverrideUrlLoading: true,
        javaScriptCanOpenWindowsAutomatically: false,
        supportMultipleWindows: false,
        allowFileAccess: false,
        allowContentAccess: false,
      ),
      shouldOverrideUrlLoading: (controller, action) async {
        final allowed = isAllowedNavigation(action.request.url?.uriValue, _base);
        return allowed
            ? NavigationActionPolicy.ALLOW
            : NavigationActionPolicy.CANCEL;
      },
      onWebViewCreated: (controller) {
        _controller = controller;
        controller.addJavaScriptHandler(
          handlerName: 'onAuthError',
          callback: (args) {
            final reason = args.isNotEmpty && args.first is String
                ? args.first as String
                : null;
            widget.onAuthError?.call(reason);
          },
        );
        controller.addJavaScriptHandler(
          handlerName: 'onNativeRequest',
          callback: (args) => _native.handle(args.isNotEmpty ? args.first : null),
        );
        controller.addJavaScriptHandler(
          handlerName: 'onCompanyCreated',
          callback: (args) {
            widget.onCompanyCreated?.call();
            return _refreshToken();
          },
        );
        controller.addJavaScriptHandler(
          handlerName: 'onTokenExpired',
          callback: (args) => _refreshToken(),
        );
        controller.addJavaScriptHandler(
          handlerName: 'onComplete',
          callback: (args) {
            widget.onComplete?.call(OnboardingResult.fromHandlerArgs(args));
          },
        );
      },
      onConsoleMessage: (controller, message) {
        debugPrint('[aihr_client_onboarding_sdk console] $message');
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame ?? true) setState(() => _loadFailed = true);
      },
      onReceivedHttpError: (controller, request, response) {
        if (request.isForMainFrame ?? true) setState(() => _loadFailed = true);
      },
      onLoadStop: (controller, url) async {
        await _injectEnvironment();
        await _inject(buildSetAuthTokenScript(_currentToken));
        await _inject(buildSetLanguageScript(_language));
      },
    );
  }
}

class _LoadErrorView extends StatelessWidget {
  const _LoadErrorView({required this.language, required this.onRetry});

  final String language;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isArabic = language == 'ar';
    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isArabic
                    ? 'تعذّر تحميل المساعد. تحقق من الاتصال.'
                    : 'Could not load the assistant. Check your connection.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Color(0xFF4E4E4E)),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: onRetry,
                child: Text(
                  isArabic ? 'إعادة المحاولة' : 'Retry',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0192E1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
