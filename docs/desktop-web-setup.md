# Desktop/web client — setup & platform notes

Faz 11, madde 6c (see `docs/roadmap.md`) added **web** and **macOS
desktop** as real, buildable targets for the same Flutter app —
not a separate client. **Windows and Linux were deliberately not
added**: this session's sandbox has no such machine to build or run
them on, so any code added for them couldn't be verified at all
(unlike web/macOS, both actually built *and ran* here — see below).
Adding them later is one command:

```
flutter create --platforms=windows,linux .
```

...but do that on (or at least verify the result on) an actual Windows/
Linux machine — don't assume it Just Works from this precedent alone.

## Building

```
flutter build web      # → build/web, serve as static files
flutter build macos    # → build/macos/Build/Products/Release/LifeSearch.app
```

Both need nothing beyond the existing `mobile/.env` — same config as
mobile.

## What's disabled, and why

Every capture path (`Choose Image`, `Upload Document`, `Take Photo`,
`Record Audio`) ends up persisting the picked/captured file with
`dart:io`'s `File` (`OfflineItemRepository.uploadFile`) — which has no
real filesystem to work with on web. Rather than let that crash, all
four are disabled on web (`capture_platform_support.dart`), with a
"Web'de henüz desteklenmiyor" subtitle instead of a silently-broken
button — the same "hide a broken control rather than show one"
approach used for Google/Apple sign-in (Faz 11, madde 5).

**Take Photo** is *also* disabled on macOS specifically: the `camera`
plugin has no macOS implementation at all (its own `pubspec.yaml` only
declares android/ios/web). `Choose Image`/`Upload Document`/`Record
Audio` all work normally on macOS — `file_picker` and `record` both
have real desktop backends, and `dart:io`/`path_provider` work exactly
like they do on mobile.

**Export** (Settings → Export data) needed no gating at all: it used to
write a `dart:io` temp file and share that path, which would have
needed the same web-specific handling — instead it was changed to
share the JSON directly from bytes (`XFile.fromData`, see
`export_providers.dart`), which works identically on every platform.
Not a limitation, just a simpler design that happens to be portable.

**Google sign-in (Faz 11, madde 5) is hidden on web, not just
unconfigured** (Faz 12, madde 11 — see docs/roadmap.md): `google_sign_in`
on web can't do the imperative `authenticate()` flow this app uses at
all — its web implementation renders its own Google-controlled button
into the DOM instead, a fundamentally different flow this app doesn't
implement. `NativeOAuthService.isGoogleAvailable` now checks the
package's own advertised capability rather than assuming every platform
supports it, so the button simply doesn't show on web (same "hide a
broken control rather than show one" pattern as everywhere else) —
implementing the DOM-button flow itself is future work, not done here.
Apple sign-in on web needs a Services ID with a *web* redirect URI,
separate from the iOS/macOS native flow, and stays pre-existing "kod
var, kurulum kullanıcıda" territory (see
`docs/google-apple-login-setup.md`), just with one more platform's
worth of setup were it ever added.

## Local persistence on web: sqlite compiled to WASM

There's no real filesystem in a browser, so Drift can't use its normal
native sqlite backend there. `AppDatabase._openConnection()` now passes
`DriftWebOptions` pointing at two static files:

```
web/sqlite3.wasm
web/drift_worker.dart.js
```

**These are binary/generated files downloaded from
[drift's GitHub releases](https://github.com/simolus3/drift/releases),
not written by hand** — and they must match `pubspec.lock`'s *resolved*
`drift` version exactly (not just the `^` range in `pubspec.yaml`) or
the worker protocol between the wasm sqlite build and the drift package
can silently mismatch. Whenever `drift`/`drift_flutter` gets bumped:

```
grep -A3 '^  drift:$' pubspec.lock   # confirm the resolved version
# then download that exact release's two assets and overwrite these files
```

## A real bug this caught: macOS App Sandbox blocks all networking by default

Flutter's own macOS template enables `com.apple.security.app-sandbox`
but does **not** include `com.apple.security.network.client` — without
it, every outgoing request (Supabase, the AI backend) is silently
blocked by the OS sandbox, entitlement or no entitlement bug in this
app's own code. This is a
[documented Flutter gotcha](https://docs.flutter.dev/platform-integration/macos/building),
not specific to this app, but it's exactly the kind of thing that's
easy to miss since `flutter build macos` succeeds either way — the
failure only shows up at runtime, on the first network call.

**Caught and verified, not just added defensively**: running the built
`.app` before this fix, a background network call (`google_fonts`
fetching a font over HTTPS) failed every time within a few seconds;
after adding `com.apple.security.network.client` to *both*
`macos/Runner/DebugProfile.entitlements` and `Release.entitlements`
(Flutter's own docs: change both identically) and rebuilding, the same
run produced no network errors at all, repeated twice. `codesign -d
--entitlements :- LifeSearch.app` confirms the entitlement is actually
embedded in the signed build.

## What was verified, and what wasn't

**Verified in this session**:
- `flutter build web` — real compilation, succeeds; `sqlite3.wasm`/
  `drift_worker.dart.js` confirmed present in `build/web/` output.
- `flutter build macos` — real compilation + codesigning, succeeds.
- The built macOS app actually **launched and ran** (real `open` +
  process check, not just "the build succeeded") against this
  project's real, configured Supabase project (`mobile/.env`) — no
  startup crash, no Dart exception, across three separate runs
  totaling ~30 seconds of uptime, before and after the entitlement fix.
- `flutter analyze` clean, full `flutter test` suite green (189 tests)
  on the same codebase now covering three platforms' worth of
  conditional logic.

**Not verified — genuinely couldn't be, from here**:
- Any actual browser run of the web build (`flutter run -d chrome`,
  or opening `build/web/index.html` in a real browser) — no Chrome/
  Chromium binary is installed in this sandbox at all
  (`flutter doctor` reports it missing). The wasm sqlite setup is
  therefore verified by code review and matching drift's documented
  contract exactly, not by watching it actually open a database in a
  browser tab.
- Any actual interactive use of the macOS app (clicking through login,
  search, capturing an item) — this session can launch a process and
  read its logs, not drive its UI. The app was observed running
  without error, not observed successfully completing a real user
  flow end to end.
- CORS: if the backend and the web build end up on different origins
  in production, `ALLOWED_ORIGINS` (`backend/.env`) needs the web
  app's real origin — the default `["*"]` works for local development
  but isn't something this session set up for a real deployment.
- Windows and Linux, entirely — not added, not attempted, per the
  scope decision above.
