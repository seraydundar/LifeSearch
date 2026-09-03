import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../item/presentation/providers/item_providers.dart';
import '../providers/theme_mode_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    final themeMode = ref.watch(themeModeProvider);
    final isSigningOut = ref.watch(authControllerProvider).isLoading;
    final pendingSync = ref.watch(pendingSyncCountProvider).valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(user?.email ?? '—'),
            subtitle: const Text('Account'),
          ),
          const Divider(),
          ListTile(
            leading: Icon(
              pendingSync == 0 ? Icons.cloud_done_outlined : Icons.cloud_sync_outlined,
            ),
            title: const Text('Sync'),
            subtitle: Text(
              pendingSync == 0
                  ? 'Her şey senkronize edildi'
                  : '$pendingSync değişiklik senkronize edilmeyi bekliyor',
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Theme'),
            trailing: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined)),
                ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined)),
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined)),
              ],
              selected: {themeMode},
              onSelectionChanged: (selection) =>
                  ref.read(themeModeProvider.notifier).state = selection.first,
              showSelectedIcon: false,
            ),
          ),
          const Divider(),
          ListTile(
            leading: isSigningOut
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
            title: Text('Log out', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: isSigningOut ? null : () => ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
    );
  }
}
