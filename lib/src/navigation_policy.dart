/// Decides whether the WebView may navigate to [target].
///
/// The onboarding page is the only content this widget should ever show, so
/// navigation is limited to the same scheme, host and port as the page's own
/// base URL (plus `about:blank`). Anything else is cancelled, which keeps the
/// JavaScript bridge from being reachable by a foreign page.
bool isAllowedNavigation(Uri? target, Uri base) {
  if (target == null) return false;
  if (target.scheme == 'about') return target.toString() == 'about:blank';
  return target.scheme == base.scheme &&
      target.host == base.host &&
      target.port == base.port;
}
