# aihr_client_onboarding_sdk

A Flutter widget that shows the NizamyAI onboarding chat to a new company owner.
In the chat the owner sets up their company: company details, work location,
first check-in (fingerprint or face), team invites, shifts and leave types.
When they finish, the widget tells your app so it can open the dashboard.

**Integration steps:** see [`MRHR_ONBOARDING_SDK_INTEGRATION_GUIDE.md`](MRHR_ONBOARDING_SDK_INTEGRATION_GUIDE.md).

## At a glance

```yaml
dependencies:
  aihr_client_onboarding_sdk:
    git:
      url: https://github.com/AA-Solutions-tech/aihr-client-onboarding-sdk-dist.git
      ref: v0.1.0
```

```dart
AiHrClientOnboardingWidget(
  authToken: accessToken,
  refreshToken: refreshToken,
  apiBaseUrl: mrhrBaseUrl,
  deviceId: deviceId,
  onTokenRefreshed: (token) => saveAccessToken(token),
  onComplete: (result) => openDashboard(),
  onAuthError: (reason) => goToLogin(),
)
```

- The chat page is hosted by the AI-HR backend, so chat changes reach every
  installed app without a new package version.
- Tokens are kept in memory only. The refresh token is used only to renew the
  access token with your MRHR server.
- The app needs location and biometric permissions; see the guide, Section 4.
