import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The single `SupabaseClient` instance for the whole app.
///
/// `Supabase.initialize()` runs once in `main()` before `runApp`; this
/// provider just exposes the already-initialized client so that no widget
/// or repository ever calls `Supabase.instance` directly (see requirements
/// doc, rule: "Supabase çağrılarını doğrudan widget içerisinden yapma").
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});
