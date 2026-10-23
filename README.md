# aihr_client_onboarding_sdk

A Flutter widget that shows the NizamyAI onboarding chat to a new company owner.
In the chat the owner sets up their company: name and company, work location,
fingerprint, team invites, shifts, leave types, a first check-in and check-out,
and notifications, with Nizamy's reward points shown as each step is done.
When they finish, the widget tells your app so it can open the dashboard.

**Integration steps:** see [`MRHR_ONBOARDING_SDK_INTEGRATION_GUIDE.md`](MRHR_ONBOARDING_SDK_INTEGRATION_GUIDE.md).

## At a glance

```yaml
dependencies:
  aihr_client_onboarding_sdk:
    git:
      url: https://github.com/AA-Solutions-tech/aihr-client-onboarding-sdk-dist.git
      ref: v0.2.0
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
