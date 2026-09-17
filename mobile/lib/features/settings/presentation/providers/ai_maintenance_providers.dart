import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client_provider.dart';
import '../../data/ai_maintenance_service.dart';

final aiMaintenanceServiceProvider = Provider<AiMaintenanceService>((ref) {
  return AiMaintenanceService(ref.watch(apiClientProvider));
});

final reprocessStaleEmbeddingsControllerProvider =
    AsyncNotifierProvider<ReprocessStaleEmbeddingsController, int?>(
  ReprocessStaleEmbeddingsController.new,
);

/// Owns loading/error/result state for the "AI Status" row's "Reprocess
/// stale embeddings" action (P3, docs/requirements-audit-2026-09-13.md).
/// The state's `int?` is the last known `stale_item_count` — `null`
/// before the button has ever been pressed this session, not "zero
/// found".
class ReprocessStaleEmbeddingsController extends AsyncNotifier<int?> {
  @override
  int? build() => null;

  Future<void> reprocess() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      return ref.read(aiMaintenanceServiceProvider).reprocessStaleEmbeddings();
    });
  }
}
