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
