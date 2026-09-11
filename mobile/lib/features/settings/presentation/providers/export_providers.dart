import 'dart:convert';

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
      final json = await ref.read(exportServiceProvider).exportUserDataAsJson();
      // `XFile.fromData` (bytes in memory), not a `dart:io` File path —
      // works identically on every platform including web, which has
      // no real filesystem for `path_provider` to hand back a path for
      // (Faz 11, madde 6c, see docs/roadmap.md).
      final fileName = 'lifesearch-export-${DateTime.now().millisecondsSinceEpoch}.json';
      final file = XFile.fromData(
        utf8.encode(json),
        name: fileName,
        mimeType: 'application/json',
      );
      await SharePlus.instance.share(ShareParams(files: [file]));
    });
  }
}
