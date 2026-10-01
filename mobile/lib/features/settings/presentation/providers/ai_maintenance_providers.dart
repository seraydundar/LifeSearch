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

/// `int?` state: `null` means not yet pressed this session, not "zero found".
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
