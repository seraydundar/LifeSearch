import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_lock_providers.dart';

/// Full-screen overlay shown instead of the app whenever app-lock is on
/// and the current session hasn't been unlocked yet — see [AppLockGate].
class AppLockScreen extends ConsumerStatefulWidget {
  const AppLockScreen({super.key});

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen> {
  bool _authenticating = false;
  bool _lastAttemptFailed = false;

  @override
  void initState() {
    super.initState();
    // Prompt immediately rather than making the user tap first.
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  Future<void> _authenticate() async {
    if (_authenticating) return;
    setState(() {
      _authenticating = true;
      _lastAttemptFailed = false;
    });
    final success = await ref.read(appLockServiceProvider).authenticate();
    if (!mounted) return;
    if (success) {
      ref.read(appLockUnlockedProvider.notifier).state = true;
    } else {
      setState(() {
        _authenticating = false;
        _lastAttemptFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 64, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 24),
                const Text(
                  'LifeSearch kilitli',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  _lastAttemptFailed
                      ? 'Doğrulanamadı — tekrar dene.'
                      : 'Devam etmek için kimliğini doğrula.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (_authenticating)
                  const CircularProgressIndicator()
                else
                  FilledButton.icon(
                    onPressed: _authenticate,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Kilidi Aç'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
