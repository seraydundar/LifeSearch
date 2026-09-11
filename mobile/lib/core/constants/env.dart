import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Typed access to the values loaded from `.env` (see `.env.example`).
///
/// `.env` is git-ignored — copy `.env.example` to `.env` and fill in the
/// Supabase project's URL/anon key before running the app. Never put a
/// secret key (e.g. Supabase `service_role`) here; that stays backend-only.
class Env {
  Env._();

  static String get supabaseUrl => _require('SUPABASE_URL');
  static String get supabaseAnonKey => _require('SUPABASE_ANON_KEY');

  /// The FastAPI AI service's base URL. Optional on purpose — AI
  /// processing is an enhancement, not something the app depends on to
  /// function (requirements doc, rule 15: assume AI operations can fail).
  /// Empty/unset means "AI processing disabled", not an error.
  static String? get backendUrl => _optional('BACKEND_URL');

  /// Google Sign-In (Faz 11, madde 5 — see docs/roadmap.md): the OAuth
  /// client id `GoogleSignIn.instance.initialize()` uses on iOS/macOS.
  /// Optional — Google sign-in is hidden entirely (see `LoginScreen`)
  /// when this and [googleServerClientId] are both unset, the same
  /// "missing means disabled, not broken" contract as [backendUrl].
  static String? get googleClientId => _optional('GOOGLE_CLIENT_ID');

  /// The **web** OAuth client id — needed on every platform (not just
  /// Android) so the ID token's `aud` claim matches the "Client ID"
  /// configured in Supabase's Google provider settings; without this,
  /// Supabase would reject an otherwise-valid Google ID token. See
  /// docs/google-apple-login-setup.md.
  static String? get googleServerClientId => _optional('GOOGLE_SERVER_CLIENT_ID');

  static String? _optional(String key) {
    try {
      final value = dotenv.env[key];
      return (value == null || value.isEmpty) ? null : value;
    } on NotInitializedError {
      // A widget test that never calls `dotenv.load()` (most don't,
      // and shouldn't need to just to read an optional value) — treated
      // the same as the key simply not being set: nothing configured,
      // not an error. Found as a real regression: `LoginScreen` reading
      // this (for Google sign-in's availability) is what first exercised
      // an *unmocked* `Env` getter in a test with no `.env` loaded.
      return null;
    }
  }

  static String _require(String key) {
    final value = dotenv.env[key];
    if (value == null || value.isEmpty) {
      throw StateError(
        'Missing "$key" in mobile/.env. Copy .env.example to .env and fill '
        'it in with your Supabase project\'s URL/anon key.',
      );
    }
    return value;
  }
}
