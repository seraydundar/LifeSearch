import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings/presentation/providers/theme_mode_provider.dart';
import 'app_lock_gate.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class LifeSearchApp extends ConsumerWidget {
  const LifeSearchApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'LifeSearch',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) => AppLockGate(child: child!),
    );
  }
}
