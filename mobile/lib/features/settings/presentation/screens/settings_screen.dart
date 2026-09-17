import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/network/api_client_provider.dart';
import '../../../../shared/extensions/build_context_x.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../item/presentation/providers/item_providers.dart';
import '../../domain/storage_usage.dart';
import '../providers/account_providers.dart';
import '../providers/ai_maintenance_providers.dart';
import '../providers/app_lock_providers.dart';
import '../providers/export_providers.dart';
import '../providers/theme_mode_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    final themeMode = ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.system;
    final isSigningOut = ref.watch(authControllerProvider).isLoading;
    final pendingSync = ref.watch(pendingSyncCountProvider).valueOrNull ?? 0;
    final items = ref.watch(itemsProvider).valueOrNull ?? const [];
    final isExporting = ref.watch(exportControllerProvider).isLoading;
    final isDeletingAccount = ref.watch(accountControllerProvider).isLoading;
    final aiAvailable = ref.watch(apiClientProvider) != null;
    final appLockEnabled = ref.watch(appLockEnabledProvider).valueOrNull ?? false;
    final appLockSupported = ref.watch(appLockDeviceSupportedProvider).valueOrNull ?? false;
    final isReprocessing = ref.watch(reprocessStaleEmbeddingsControllerProvider).isLoading;

    ref.listen(exportControllerProvider, (previous, next) {
      if (next.hasError) context.showErrorSnackBar('Dışa aktarılamadı.');
    });
    // P3 (docs/requirements-audit-2026-09-13.md): reports the result
    // either way — a silent "accepted" for a button press the user is
    // actively watching would look like nothing happened.
    ref.listen(reprocessStaleEmbeddingsControllerProvider, (previous, next) {
      if (next.hasError) {
        context.showErrorSnackBar('Yeniden işleme başlatılamadı.');
        return;
      }
      final count = next.valueOrNull;
      if (count == null || (previous?.isLoading ?? false) == false) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 0
                ? 'Yeniden işlenecek eski embedding bulunamadı.'
                : '$count öğe arka planda yeniden işleniyor.',
          ),
        ),
      );
    });
    ref.listen(accountControllerProvider, (previous, next) {
      if (next.hasError) {
        context.showErrorSnackBar(
          next.error is Failure ? (next.error! as Failure).message : 'Hesap silinemedi.',
        );
      }
    });

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
            leading: const Icon(Icons.storage_outlined),
            title: const Text('Storage'),
            subtitle: Text(
              storageTotalIsIncomplete(items)
                  ? '${formatBytes(totalStorageBytes(items))} kullanılıyor (bazı eski öğelerin boyutu bilinmiyor)'
                  : '${formatBytes(totalStorageBytes(items))} kullanılıyor',
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.bar_chart_outlined),
            title: const Text('Analytics'),
            subtitle: const Text('Arşivinin türe/aya göre dağılımı, en yaygın etiketler'),
            onTap: () => context.push('/analytics'),
          ),
          const Divider(),
          // "AI Status", not "AI Settings" (P2-08, docs/requirements-audit
          // -2026-09-13.md): there's nothing here to configure — the AI
          // provider is chosen server-side (backend/.env's AI_PROVIDER),
          // not per-user — so a "Settings" label overclaimed what this
          // row actually does. It's a read-only status line, same as
          // Storage/Sync above it, not a control.
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('AI Status'),
            subtitle: Text(
              aiAvailable
                  ? 'AI destekli işleme aktif — embedding, arama ve Ask AI bu sunucu üzerinden çalışıyor'
                  : 'Backend yapılandırılmamış — AI destekli işleme (arama, Ask AI) devre dışı',
            ),
            // P3 (docs/requirements-audit-2026-09-13.md): the one actual
            // action this row can trigger — everything else about "AI
            // Status" is read-only, see that rename's own note above.
            trailing: aiAvailable
                ? TextButton(
                    onPressed: isReprocessing
                        ? null
                        : () => ref
                            .read(reprocessStaleEmbeddingsControllerProvider.notifier)
                            .reprocess(),
                    child: isReprocessing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Reprocess'),
                  )
                : null,
          ),
          const Divider(),
          ListTile(
            leading: isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share_outlined),
            title: const Text('Export'),
            subtitle: const Text('Verilerini JSON olarak dışa aktar'),
            onTap: isExporting
                ? null
                : () => ref.read(exportControllerProvider.notifier).exportAndShare(),
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
                  ref.read(themeModeProvider.notifier).setThemeMode(selection.first),
              showSelectedIcon: false,
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy'),
            subtitle: Text(
              appLockSupported
                  ? 'Uygulamayı açarken biyometrik/PIN doğrulaması iste'
                  : 'Bu cihazda biyometrik veya PIN kilidi ayarlı değil',
            ),
            trailing: Switch(
              value: appLockEnabled,
              onChanged:
                  appLockSupported ? (value) => _onAppLockToggle(context, ref, value) : null,
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
          const Divider(),
          ListTile(
            leading: isDeletingAccount
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
            title: Text(
              'Delete Account',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            subtitle: const Text('Tüm verilerini kalıcı olarak sil'),
            onTap: isDeletingAccount ? null : () => _confirmDeleteAccount(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteAccount(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hesabını sil'),
        content: const Text(
          'Bu işlem GERİ ALINAMAZ. Tüm içeriklerin, koleksiyonların ve hesabın '
          'kalıcı olarak silinecek.',
        ),
        actions: [
          TextButton(onPressed: () => context.pop(false), child: const Text('Vazgeç')),
          TextButton(
            onPressed: () => context.pop(true),
            child: Text(
              'Hesabı Sil',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(accountControllerProvider.notifier).deleteAccount();
  }

  /// Turning app-lock ON requires a successful authentication first — so a
  /// user with, say, unreliable Face ID doesn't lock themselves out on the
  /// very next launch. Turning it OFF doesn't need re-auth: reaching this
  /// switch at all means the current session is already unlocked.
  Future<void> _onAppLockToggle(BuildContext context, WidgetRef ref, bool value) async {
    if (value) {
      final success = await ref.read(appLockServiceProvider).authenticate();
      if (!success) {
        if (context.mounted) context.showErrorSnackBar('Doğrulanamadı, kilit açılmadı.');
        return;
      }
    }
    await ref.read(appLockEnabledProvider.notifier).setEnabled(value);
  }
}
