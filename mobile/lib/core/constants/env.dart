import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Typed access to values loaded from `.env` (git-ignored; copy from `.env.example`).
/// Never put a secret key (e.g. Supabase `service_role`) here — backend-only.
class Env {
  Env._();

  static String get supabaseUrl => _require('SUPABASE_URL');
  static String get supabaseAnonKey => _require('SUPABASE_ANON_KEY');

  /// Optional: AI processing is an enhancement, not a hard dependency. Unset means disabled, not an error.
  static String? get backendUrl => _optional('BACKEND_URL');

  /// iOS/macOS Google Sign-In client id. Unset (with [googleServerClientId]) hides Google sign-in entirely.
  static String? get googleClientId => _optional('GOOGLE_CLIENT_ID');

  /// The web OAuth client id, needed on every platform so the ID token's `aud` claim matches
  /// Supabase's configured Google provider — otherwise Supabase rejects an otherwise-valid token.
  static String? get googleServerClientId => _optional('GOOGLE_SERVER_CLIENT_ID');

  static String? _optional(String key) {
    try {
      final value = dotenv.env[key];
      return (value == null || value.isEmpty) ? null : value;
    } on NotInitializedError {
      // Widget tests that never call dotenv.load(): treat as unset, not an error.
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
