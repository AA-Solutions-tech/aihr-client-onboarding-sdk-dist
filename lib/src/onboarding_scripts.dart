import 'dart:convert';

/// Builds the JavaScript that hands the access token to the onboarding page.
///
/// A pure function (no widget or platform dependency) so it can be unit
/// tested. `jsonEncode` produces a correctly escaped JavaScript string
/// literal, so the token can never break out of the call.
String buildSetAuthTokenScript(String token) =>
    'window.AIHR_ONBOARDING && window.AIHR_ONBOARDING.setAuthToken(${jsonEncode(token)});';

/// Builds the JavaScript that hands the host app's language ('en' or 'ar')
/// to the onboarding page.
String buildSetLanguageScript(String language) =>
    'window.AIHR_ONBOARDING && window.AIHR_ONBOARDING.setLanguage(${jsonEncode(language)});';

/// Builds the JavaScript that tells the page which MRHR environment the owner
/// logged in to (the `apiBaseUrl` the host passed). The page sends it with each
/// turn so the backend validates the token in that environment; it is only a
/// key into the backend's own list, never an address the backend calls.
String buildSetApiEnvironmentScript(String apiBaseUrl) =>
    'window.AIHR_ONBOARDING && window.AIHR_ONBOARDING.setApiEnvironment(${jsonEncode(apiBaseUrl)});';
