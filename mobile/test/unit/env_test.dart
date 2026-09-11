import 'package:flutter_test/flutter_test.dart';
import 'package:lifesearch/core/constants/env.dart';

void main() {
  // Regression guard: `dotenv.load()` is never called in this file (most
  // widget tests don't call it either) — reading an *optional* Env value
  // used to crash with `NotInitializedError` the first time something
  // actually exercised it unmocked (found via `LoginScreen`'s Google
  // sign-in availability check, see `login_screen_test.dart`), instead
  // of behaving like "nothing configured".
  test('an optional Env value is null, not a crash, when dotenv was never loaded', () {
    expect(Env.backendUrl, isNull);
    expect(Env.googleClientId, isNull);
    expect(Env.googleServerClientId, isNull);
  });
}
