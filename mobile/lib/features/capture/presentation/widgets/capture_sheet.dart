import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/extensions/build_context_x.dart';
import '../../../item/domain/entities/item.dart';
import '../../../item/presentation/providers/item_providers.dart';

/// The "+" flow from the requirements doc (section 13). Photo capture,
/// audio recording and link saving are Phase 6/8 work — shown but disabled
/// for now so the full product shape is visible without pretending they
/// already work.
Future<void> showCaptureSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (context) => const _CaptureSheet(),
  );
}

class _CaptureSheet extends ConsumerWidget {
  const _CaptureSheet();

  Future<void> _pickAndUpload(
    BuildContext context,
    WidgetRef ref, {
    required FileType fileType,
    required ItemType itemType,
    List<String>? allowedExtensions,
  }) async {
    final files = await FilePicker.pickFiles(
      type: fileType,
      allowedExtensions: allowedExtensions,
    );
    final file = files.isEmpty ? null : files.single;
    if (file?.path == null) return; // user cancelled

    if (!context.mounted) return;
    Navigator.of(context).pop(); // close the sheet, show progress on the screen behind it

    final ok = await ref.read(captureControllerProvider.notifier).uploadFile(
          localFilePath: file!.path!,
          originalFilename: file.name,
          mimeType: _guessMimeType(file.extension),
          type: itemType,
        );

    if (!context.mounted) return;
    if (!ok) {
      final error = ref.read(captureControllerProvider).error;
      context.showErrorSnackBar(error?.toString() ?? 'Yükleme başarısız oldu.');
    }
  }

  String _guessMimeType(String? extension) {
    return switch (extension?.toLowerCase()) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'heic' => 'image/heic',
      _ => 'application/octet-stream',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUploading = ref.watch(captureControllerProvider).isLoading;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text('Add to LifeSearch', style: Theme.of(context).textTheme.titleMedium),
            ),
            const SizedBox(height: 8),
            _CaptureTile(
              icon: Icons.note_add_outlined,
              label: 'Create Note',
              onTap: () {
                Navigator.of(context).pop();
                context.push('/item/new');
              },
            ),
            _CaptureTile(
              icon: Icons.image_outlined,
              label: 'Choose Image',
              enabled: !isUploading,
              onTap: () => _pickAndUpload(
                context,
                ref,
                fileType: FileType.image,
                itemType: ItemType.image,
              ),
            ),
            _CaptureTile(
              icon: Icons.picture_as_pdf_outlined,
              label: 'Upload Document',
              enabled: !isUploading,
              onTap: () => _pickAndUpload(
                context,
                ref,
                fileType: FileType.custom,
                allowedExtensions: const ['pdf'],
                itemType: ItemType.pdf,
              ),
            ),
            const _CaptureTile(icon: Icons.camera_alt_outlined, label: 'Take Photo', comingSoon: 'Faz 6'),
            const _CaptureTile(icon: Icons.mic_none_outlined, label: 'Record Audio', comingSoon: 'Faz 8'),
            const _CaptureTile(icon: Icons.link, label: 'Add Link', comingSoon: 'Faz 8'),
          ],
        ),
      ),
    );
  }
}

class _CaptureTile extends StatelessWidget {
  const _CaptureTile({
    required this.icon,
    required this.label,
    this.onTap,
    this.enabled = true,
    this.comingSoon,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;
  final String? comingSoon;

  @override
  Widget build(BuildContext context) {
    final isDisabled = comingSoon != null || !enabled;
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: comingSoon != null
          ? Chip(label: Text(comingSoon!), visualDensity: VisualDensity.compact)
          : null,
      enabled: !isDisabled,
      onTap: isDisabled ? null : onTap,
    );
  }
}
