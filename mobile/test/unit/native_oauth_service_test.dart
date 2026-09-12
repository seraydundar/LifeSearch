import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:lifesearch/features/auth/data/native_oauth_service.dart';

void main() {
  // Faz 12, madde 11 (denetim düzeltmesi — see docs/roadmap.md):
  // isGoogleAvailable delegates to google_sign_in's own advertised
  // capability (GoogleSignIn.instance.supportsAuthenticate()) instead
  // of a hardcoded !kIsWeb, so it stays correct on any platform the
  // package adds or drops support for.
  test(
      "isGoogleAvailable is false, not a crash, when no platform implementation is "
      'registered at all — a bare `flutter test` VM binary never registers one, the exact '
      "same shape of gap as a real Windows/Linux build (google_sign_in has no platform "
      'package for either) would hit in production', () {
    final service = NativeOAuthService();

    // The platform interface's own placeholder throws UnimplementedError
    // (an Error, not an Exception) until something registers a real
    // implementation — confirmed by first writing this test with a bare
    // `expect(..., isA<bool>())` and watching it actually throw, not by
    // assuming the failure mode.
    expect(() => GoogleSignIn.instance.supportsAuthenticate(), throwsA(isA<Error>()));

    expect(service.isGoogleAvailable, isFalse);
  });
}
