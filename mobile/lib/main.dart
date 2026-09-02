import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  runApp(const ProviderScope(child: LifeSearchApp()));
}
