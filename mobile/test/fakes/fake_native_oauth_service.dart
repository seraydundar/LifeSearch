import 'package:lifesearch/features/auth/data/native_oauth_service.dart';

/// A full fake (not a subclass — `NativeOAuthService`'s real methods all
/// touch native platform channels, which even a subclassed-but-unused
/// constructor path in a test binary would risk hitting) so tests never
/// need a real Google/Apple account or device capability.
class FakeNativeOAuthService implements NativeOAuthService {
  FakeNativeOAuthService({
    this.googleIdToken = 'fake-google-id-token',
    this.appleIdToken = 'fake-apple-id-token',
    this.appleAvailable = true,
  });

  /// `null` simulates the user cancelling the native picker — see
  /// `AuthController.signInWithGoogle`'s docstring for why that's not
  /// an error.
  String? googleIdToken;
  String? appleIdToken;
  bool appleAvailable;

  /// Set to make the next `signInWithGoogle`/`signInWithApple` call
  /// throw this instead of returning a token.
  Object? errorToThrow;

  int signInWithGoogleCallCount = 0;
  int signInWithAppleCallCount = 0;

  @override
  bool get isAppleAvailable => appleAvailable;

  @override
  Future<String?> signInWithGoogle() async {
    signInWithGoogleCallCount++;
    if (errorToThrow case final error?) throw error;
    return googleIdToken;
  }

  @override
  Future<String?> signInWithApple() async {
    signInWithAppleCallCount++;
    if (errorToThrow case final error?) throw error;
    return appleIdToken;
  }
}
