import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/constants/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');
  await Supabase.initialize(
    url: Env.supabaseUrl,
    // supabase_flutter's `publishableKey` param accepts both the legacy
    // "anon" JWT-format key and the newer sb_publishable_... key — either
    // is what SUPABASE_ANON_KEY in .env should hold.
    publishableKey: Env.supabaseAnonKey,
  );

  // Google sign-in (Faz 11, madde 5 — see docs/roadmap.md):
  // `GoogleSignIn.instance.initialize()` must run exactly once, before
  // any other `GoogleSignIn` call, or `authenticate()` throws — only
  // when actually configured (`LoginScreen` hides the button otherwise,
  // matching `googleSignInAvailableProvider`'s own check), so a build
  // without Google credentials never touches this at all.
  if (Env.googleClientId != null || Env.googleServerClientId != null) {
    await GoogleSignIn.instance.initialize(
      clientId: Env.googleClientId,
      serverClientId: Env.googleServerClientId,
    );
  }

  runApp(const ProviderScope(child: LifeSearchApp()));
}
