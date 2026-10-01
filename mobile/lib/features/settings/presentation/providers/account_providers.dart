import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client_provider.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/account_service.dart';

final accountServiceProvider = Provider<AccountService>((ref) {
  return AccountService(ref.watch(apiClientProvider));
});

final accountControllerProvider =
    AsyncNotifierProvider<AccountController, void>(AccountController.new);

/// On success, signs the now-nonexistent session out locally; the router redirect handles the rest.
class AccountController extends AsyncNotifier<void> {
  @override
  void build() {}

  Future<void> deleteAccount() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(accountServiceProvider).deleteAccount();
      await ref.read(authControllerProvider.notifier).signOut();
    });
  }
}
