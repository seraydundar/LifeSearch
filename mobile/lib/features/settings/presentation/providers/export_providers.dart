import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/network/supabase_client_provider.dart';
import '../../data/export_service.dart';

final exportServiceProvider = Provider<ExportService>((ref) {
  return ExportService(ref.watch(supabaseClientProvider));
});

final exportControllerProvider =
    AsyncNotifierProvider<ExportController, void>(ExportController.new);

/// Owns loading/error state for "Export" — the actual OS share sheet
/// invocation lives here too since it's a one-shot side effect of the
/// same button press, not something any other screen needs to watch.
class ExportController extends AsyncNotifier<void> {
  @override
  void build() {}

  Future<void> exportAndShare() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final file = await ref.read(exportServiceProvider).exportUserDataAsJson();
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    });
  }
}
