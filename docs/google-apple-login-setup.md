# Google/Apple login — external setup checklist

The code for this (Faz 11, madde 5 — see `docs/roadmap.md`) is done and
tested, but it can't actually sign anyone in until **you** complete this
setup — none of it can be done or verified from inside the repo. Neither
button shows up in the app at all until its own prerequisite below is met
(`LoginScreen` hides a broken button rather than showing one).

## Google

Google sign-in needs **two** OAuth client IDs from
[Google Cloud Console](https://console.cloud.google.com/apis/credentials)
(same project the rest of your Google APIs live in, or a new one) — a
**Web** client and, per platform, a **iOS**/**Android** client. The app
only ever needs the Web one directly; the platform ones exist so each
native SDK can complete its own sign-in flow, but Supabase always
validates the token against the **Web** client's id.

1. **Create the Web client** (APIs & Services → Credentials → Create
   Credentials → OAuth client ID → Application type: **Web application**).
   No redirect URI is needed for this flow. Copy its **Client ID**.
2. **Create an iOS client** (Application type: **iOS**), bundle ID
   matching `mobile/ios/Runner.xcodeproj`'s bundle identifier. Copy its
   **Client ID** and its **iOS URL scheme** (the reversed client ID,
   looks like `com.googleusercontent.apps.XXXX`).
3. **Create an Android client** (Application type: **Android**), package
   name `com.example.lifesearch` (or whatever `mobile/android/app/build.gradle`'s
   `applicationId` actually is) plus your **release keystore's SHA-1**
   fingerprint (`keytool -list -v -keystore <path> | grep SHA1`) — and,
   separately, your **debug keystore's** SHA-1 too if you want Google
   sign-in to work in debug builds (`~/.android/debug.keystore`,
   password `android`).
4. **Supabase Dashboard** → Authentication → Providers → **Google** →
   enable it, paste the **Web** client's Client ID and secret.
5. **`mobile/.env`**:
   ```
   GOOGLE_CLIENT_ID=<iOS client id>.apps.googleusercontent.com
   GOOGLE_SERVER_CLIENT_ID=<Web client id>.apps.googleusercontent.com
   ```
   `GOOGLE_SERVER_CLIENT_ID` is the one that actually matters everywhere —
   it's what makes the ID token's `aud` claim match what Supabase checks
   against. Leave both empty to keep the Google button hidden.
6. **iOS**: add the reversed iOS client ID as a URL scheme in
   `mobile/ios/Runner/Info.plist` (a `CFBundleURLTypes` entry) — see
   [`google_sign_in_ios`'s README](https://pub.dev/packages/google_sign_in_ios#ios-integration)
   for the exact snippet.
7. **Android**: no manifest changes needed beyond what's already there —
   Google Sign-In on Android authenticates against the SHA-1 fingerprints
   registered in step 3, not anything in `mobile/android/`.

## Apple

Only wired up for iOS/macOS here (`NativeOAuthService.isAppleAvailable`)
— Android would need a separate web-based flow this app doesn't set up.

1. **Apple Developer** → Certificates, IDs & Profiles → your App ID →
   enable the **Sign In with Apple** capability.
2. **Xcode**: open `mobile/ios/Runner.xcworkspace`, select the Runner
   target → Signing & Capabilities → **+ Capability** → **Sign In with
   Apple**. This is the only thing Apple's side needs on the client —
   no `.env` value, no Info.plist entry.
3. **Supabase Dashboard** → Authentication → Providers → **Apple** →
   enable it. Supabase needs:
   - your **Services ID** (Apple Developer → Identifiers → **+** →
     Services IDs — a *separate* identifier from the App ID itself,
     used as the "Client ID" Supabase asks for),
   - a **Sign in with Apple key** (Apple Developer → Keys → **+**,
     enable Sign In with Apple) — download the `.p8` file once, it
     can't be re-downloaded,
   - your **Team ID** and the **Key ID** of that key.

   Supabase's own
   [Apple provider guide](https://supabase.com/docs/guides/auth/social-login/auth-apple)
   walks through generating the client secret JWT these pieces combine
   into — follow it exactly, this part is fiddly and easy to get wrong.

## App Store review note

If you ship Google sign-in on iOS, Apple's App Store Review Guideline
4.8 requires also offering Sign in with Apple — which is exactly what
this feature does (both buttons, Apple's shown whenever the platform
supports it), so there's nothing extra to do here beyond actually
completing the Apple setup above before submitting.

## What was **not** verified

None of this — a real Google/Apple sign-in round trip end-to-end — could
be tested here: it needs real OAuth credentials, a Supabase project with
both providers actually configured, and (for Apple) a real device or
simulator signed with a provisioning profile that has the capability.
The code was verified as far as it can be without that: `flutter analyze`
clean, and widget tests exercise every branch of `AuthController.
signInWithGoogle()`/`signInWithApple()` (success, user-cancelled, native
SDK error) against a `FakeNativeOAuthService` standing in for the real
SDKs — see `docs/roadmap.md`, Faz 11, madde 5.
