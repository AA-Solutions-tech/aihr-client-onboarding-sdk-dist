/// What the widget reports to the host app when onboarding finishes.
class OnboardingResult {
  const OnboardingResult({this.accessToken});

  /// The latest access token, so the host app can reuse it instead of
  /// refreshing again. Null when the page did not supply one.
  final String? accessToken;

  /// Builds a result from the arguments of the page's `onComplete` call.
  /// Anything that is not the expected shape yields an empty result.
  factory OnboardingResult.fromHandlerArgs(List<dynamic> args) {
    if (args.isEmpty) return const OnboardingResult();
    final first = args.first;
    if (first is! Map) return const OnboardingResult();
    final token = first['accessToken'];
    return OnboardingResult(
      accessToken: token is String && token.isNotEmpty ? token : null,
    );
  }
}
