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

/// Owns loading/error state for Export; also triggers the one-shot OS share sheet directly.
class ExportController extends AsyncNotifier<void> {
  @override
  void build() {}

  Future<void> exportAndShare() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final json = await ref.read(exportServiceProvider).exportUserDataAsJson();
      // XFile.fromData works on every platform, including web, where path_provider has no real filesystem.
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
