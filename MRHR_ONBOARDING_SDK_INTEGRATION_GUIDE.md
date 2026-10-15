# AI-HR Client Onboarding SDK — Integration Guide (Flutter)

How to embed the **NizamyAI onboarding chat** inside a Flutter app. Written for
the host app's developers (Nizamy / MRHR). The SDK ships as a single widget:
give it the new owner's login tokens, get a working onboarding chat that sets
up their company.

> Package: `aihr_client_onboarding_sdk` · distributed publicly from
> `https://github.com/AA-Solutions-tech/aihr-client-onboarding-sdk-dist.git`

---

## 1. What you're integrating

`aihr_client_onboarding_sdk` is a thin Flutter package that renders the
onboarding chat inside a WebView and bridges the owner's session and a few phone
features into it. Your app owns login; the SDK keeps tokens in memory only.

In the chat the new owner sets up: company details, work location, the first
check-in (with fingerprint or face), team invites, shifts and leave types. When
they finish, the SDK tells your app so it can open the dashboard.

- **You provide:** the owner's access token and refresh token from your native
  login, the MRHR server they logged in to, and the phone's device id.
- **The SDK provides:** the whole onboarding experience as one widget,
  `AiHrClientOnboardingWidget`, including the location, check-in and
  fingerprint prompts.
- **The SDK talks to:** the AI-HR backend (`https://hr.aasolutions.tech`) for
  the chat, and your MRHR server only to renew the access token.

Nothing else — no WebView setup, no JS bridge — is exposed.

---

## 2. Prerequisites

- **Flutter** `>=3.16.0`, Dart `>=3.0.0`.
- **No repo access needed.** The dist repo is public, so `flutter pub get`
  works on any machine (developer laptops and CI).
- **Platform minimums.** The SDK depends on `flutter_inappwebview ^6.0.0`,
  `geolocator ^14.1.1`, `geocoding ^5.0.0` and `local_auth ^3.0.2`. It is
  tested on **iOS 13.0+** and Android with **Android Gradle Plugin 8.9.1 or
  newer** (needed by `androidx.core` 1.18). If your app targets lower, raise
  these (verify exact values against those packages' docs).

---

## 3. Add the dependency

In **your app's** `pubspec.yaml`, add a git dependency pinned to a version tag:

```yaml
dependencies:
  aihr_client_onboarding_sdk:
    git:
      url: https://github.com/AA-Solutions-tech/aihr-client-onboarding-sdk-dist.git
      ref: v0.1.0        # pin an exact version — do not use a branch
```

Then:

```bash
flutter pub get
```

> `flutter_inappwebview`, `geolocator`, `geocoding` and `local_auth` come in
> automatically as transitive dependencies — you don't add them yourself.

**Upgrading later:** bump `ref:` to the new tag (e.g. `v0.2.0`) and run
`flutter pub get` again. Versions are immutable — a given tag always resolves
to the same build.

---

## 4. Required platform configuration

The chat loads from our servers over `https://` — no network configuration is
needed. The SDK does use the phone's location and biometrics (for the work
location and the first check-in), and a Flutter package cannot add these
permissions to your app — they are one-time edits in your project.

### Android

**a.** Add the permissions to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.USE_BIOMETRIC" />
```

**b.** Make `MainActivity` extend `FlutterFragmentActivity` (required by
`local_auth` to show the fingerprint prompt):

```kotlin
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

**c.** Use Android Gradle Plugin **8.9.1 or newer** (in `android/settings.gradle`
or `android/build.gradle`).

### iOS

Add to `ios/Runner/Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Your location sets where your team checks in.</string>
<key>NSFaceIDUsageDescription</key>
<string>Face ID verifies it is you when you check in.</string>
```

> **Skip the location entries and the work-location and check-in steps fail.**
> **Skip `FlutterFragmentActivity` (Android) or `NSFaceIDUsageDescription`
> (iOS) and the fingerprint / face prompt never appears.**

---

## 5. Open the onboarding

There is no separate "launch" — you route to the widget, normally right after
the owner's native login and OTP. Import it:

```dart
import 'package:aihr_client_onboarding_sdk/aihr_client_onboarding_sdk.dart';
```

### As a full screen (most common)

```dart
Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => Scaffold(
      body: SafeArea(
        child: AiHrClientOnboardingWidget(
          authToken: session.accessToken,
          refreshToken: session.refreshToken,
          apiBaseUrl: session.mrhrBaseUrl,     // e.g. https://api.nizamy.app
          deviceId: device.id,                 // see Section 7
          onTokenRefreshed: (token) => session.saveAccessToken(token),
          onComplete: (result) {
            Navigator.of(context).pop();       // leave onboarding
            openDashboard();
          },
          onAuthError: (reason) {
            Navigator.of(context).pop();
            sendOwnerToLogin();                // your re-login flow
          },
        ),
      ),
    ),
  ),
);
```

The widget fills its parent, so give it a sized container (a `Scaffold` body,
an `Expanded` — anything with bounded height).

---

## 6. The session contract

| Parameter | Type | Meaning |
|---|---|---|
| `authToken` *(required)* | `String` | The owner's **live** access token. Sent as `Authorization: Bearer <token>`. Held in memory only; never persisted by the SDK. |
| `refreshToken` *(required in production)* | `String?` | The refresh token from the same login. Used only inside the SDK to renew the access token (see below). Never sent to the chat page, our backend or a log. |
| `apiBaseUrl` *(required in production)* | `String?` | The MRHR server the owner logged in to (live or test). Must be `https`. The renew call goes here, and our backend validates the token against this same server. |
| `deviceId` *(required in production)* | `String?` | This phone's id — see Section 7. |
| `onTokenRefreshed` | `void Function(String accessToken)?` | Called with the new access token every time the SDK renews it. Save it in your session. |
| `onComplete` | `void Function(OnboardingResult result)?` | The owner finished onboarding. Open the dashboard. `result.accessToken` is the latest token. |
| `onAuthError` | `void Function(String? reason)?` | The session could not be recovered (e.g. the refresh token is no longer valid). Send the owner back to login. |
| `onCompanyCreated` | `VoidCallback?` | The company now exists. Informational only — the SDK already renews the token itself. |
| `language` | `String?` | `'en'` or `'ar'`. Leave it out to follow your app's locale. |
| `pushRegistration` | `PushRegistrationProvider?` | Your push registration, used when the owner turns notifications on (Section 7). |
| `locationProvider`, `biometricProvider` | — | Optional replacements for the built-in GPS and biometric prompt. The defaults work out of the box. |

### Giving the tokens

Pass the tokens from your native login when you build the widget. That's the
whole handshake — the SDK hands the access token to the chat once it loads.

### Renewing the token (the SDK does it)

When the owner creates their company, MRHR only adds the company to the access
token through its refresh endpoint. The SDK handles this itself: it calls
`POST {apiBaseUrl}/api/Account/refresh` with `refreshToken`, continues the chat
on the new token, and calls `onTokenRefreshed` so your app stores it. It does
the same if the token expires later. You do nothing — just save the token
passed to `onTokenRefreshed`.

### Handling rejection

If the refresh token itself is rejected, the SDK calls `onAuthError`. Send the
owner back to login, then open onboarding again with the new tokens.

> **Auth model:** your app owns login. The SDK keeps the tokens in memory only,
> never writes them to disk, and treats the refresh token like a password (it
> does not rotate and lasts about 90 days).

---

## 7. Device id and push notifications

### `deviceId` — required

Pass **the same device id your app sends to MRHR's
`POST /api/account/register-fingerprint`**. During the first check-in, after the
owner passes the phone's fingerprint or face prompt, the SDK registers the
fingerprint with this id. That is what activates the owner's account on MRHR —
and MRHR only lets an **active** owner invite their team. Without `deviceId`,
check-in still works but the team invite step is refused.

### `pushRegistration` — optional

Push belongs to your app (Firebase and the notification permission). Pass a
function that registers the device and returns the result, or `null` if the
owner declined:

```dart
Future<PushRegistration?> registerPush() async {
  final token = await yourPushService.register();
  if (token == null) return null;
  return PushRegistration(token: token, platform: 'android', deviceId: device.id);
}
```

Without it, the notifications option in the chat shows as unavailable.

---

## 8. Full minimal example

```dart
import 'package:flutter/material.dart';
import 'package:aihr_client_onboarding_sdk/aihr_client_onboarding_sdk.dart';

class OwnerOnboardingPage extends StatelessWidget {
  const OwnerOnboardingPage({
    super.key,
    required this.accessToken,
    required this.refreshToken,
    required this.mrhrBaseUrl,
    required this.deviceId,
  });

  final String accessToken;
  final String refreshToken;
  final String mrhrBaseUrl;
  final String deviceId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AiHrClientOnboardingWidget(
          authToken: accessToken,
          refreshToken: refreshToken,
          apiBaseUrl: mrhrBaseUrl,
          deviceId: deviceId,
          onTokenRefreshed: (token) {
            // store the new access token in your session
          },
          onComplete: (result) {
            Navigator.of(context).pushReplacementNamed('/dashboard');
          },
          onAuthError: (reason) {
            Navigator.of(context).pushReplacementNamed('/login');
          },
        ),
      ),
    );
  }
}
```

Open it after login:

```dart
Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => OwnerOnboardingPage(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      mrhrBaseUrl: session.mrhrBaseUrl,
      deviceId: device.id,
    ),
  ),
);
```

---

## 9. Troubleshooting

| Symptom | Likely cause |
|---|---|
| **Blank chat screen / "couldn't load"** | No internet connection, or our server is unreachable. The chat loads from our servers; there is no offline copy. |
| **Team invite says the owner must activate the company** | `deviceId` was not passed (Section 7), so the fingerprint was never registered and MRHR has not activated the owner. |
| **Fingerprint / face prompt never appears (Android)** | `MainActivity` does not extend `FlutterFragmentActivity` (Section 4b), or the phone has no fingerprint/face enrolled. |
| **Location step fails / no permission prompt** | Missing location permissions (Section 4a) or `NSLocationWhenInUseUsageDescription` (iOS), or the owner denied location. |
| **"Session expired" right after company creation** | `refreshToken` or `apiBaseUrl` missing or not `https`, so the SDK could not renew the token. |
| **Chat refuses the session immediately** | `apiBaseUrl` is not an MRHR server our backend knows, or the access token is invalid/expired. |
| **Build fails on Android** | Android Gradle Plugin older than 8.9.1, or min SDK too low (Section 2). |

---

## 10. Versioning

- Each release is an immutable tag (`v0.1.0`, `v0.2.0`, …) on the dist repo.
- Pin an exact tag in `pubspec.yaml`; never track a branch.
- To adopt a new version, bump `ref:` and run `flutter pub get`.
- **Chat changes need no rebuild.** The onboarding chat loads live from our
  servers, so changes to its questions, cards and wording reach your users
  automatically on our next deploy — no action needed on your side.
- **A rebuild is still required when a release changes something native** — a
  new permission, a new phone feature, or a change to the widget's own
  parameters. In that case: bump `ref:`, run `flutter pub get`, and
  rebuild/re-release your app as usual.

---

*Questions or a new build? Contact the AI-HR team.*
