import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../../shared/extensions/build_context_x.dart';
import '../../../item/domain/entities/item.dart';
import '../../../item/presentation/providers/item_providers.dart';
import '../screens/audio_recorder_screen.dart';
import '../screens/camera_screen.dart';

/// The "+" flow from the requirements doc (section 13) — every option is
/// live as of Phase 8.
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

  Future<void> _takePhoto(BuildContext context, WidgetRef ref) async {
    final path = await Navigator.of(context, rootNavigator: true).push<String>(
      MaterialPageRoute(builder: (_) => const CameraScreen()),
    );
    if (!context.mounted) return;
    Navigator.of(context).pop(); // close the sheet now that we're back from the camera
    if (path == null) return; // backed out without taking a photo

    final ok = await ref.read(captureControllerProvider.notifier).uploadFile(
          localFilePath: path,
          originalFilename: p.basename(path),
          mimeType: 'image/jpeg',
          type: ItemType.image,
        );

    if (!context.mounted) return;
    if (!ok) {
      final error = ref.read(captureControllerProvider).error;
      context.showErrorSnackBar(error?.toString() ?? 'Yükleme başarısız oldu.');
    }
  }

  Future<void> _recordAudio(BuildContext context, WidgetRef ref) async {
    final path = await Navigator.of(context, rootNavigator: true).push<String>(
      MaterialPageRoute(builder: (_) => const AudioRecorderScreen()),
    );
    if (!context.mounted) return;
    Navigator.of(context).pop(); // close the sheet now that we're back from recording
    if (path == null) return; // backed out without saving a recording

    final ok = await ref.read(captureControllerProvider.notifier).uploadFile(
          localFilePath: path,
          originalFilename: p.basename(path),
          mimeType: 'audio/m4a',
          type: ItemType.audio,
        );

    if (!context.mounted) return;
    if (!ok) {
      final error = ref.read(captureControllerProvider).error;
      context.showErrorSnackBar(error?.toString() ?? 'Yükleme başarısız oldu.');
    }
  }

  Future<void> _addLink(BuildContext context, WidgetRef ref) async {
    final url = await showDialog<String>(
      context: context,
      builder: (context) => const _AddLinkDialog(),
    );
    if (url == null) return; // cancelled

    if (!context.mounted) return;
    Navigator.of(context).pop(); // close the sheet

    final ok = await ref.read(captureControllerProvider.notifier).addLink(url);

    if (!context.mounted) return;
    if (!ok) {
      final error = ref.read(captureControllerProvider).error;
      context.showErrorSnackBar(error?.toString() ?? 'Link eklenemedi.');
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
            _CaptureTile(
              icon: Icons.camera_alt_outlined,
              label: 'Take Photo',
              enabled: !isUploading,
              onTap: () => _takePhoto(context, ref),
            ),
            _CaptureTile(
              icon: Icons.mic_none_outlined,
              label: 'Record Audio',
              enabled: !isUploading,
              onTap: () => _recordAudio(context, ref),
            ),
            _CaptureTile(
              icon: Icons.link,
              label: 'Add Link',
              enabled: !isUploading,
              onTap: () => _addLink(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddLinkDialog extends StatefulWidget {
  const _AddLinkDialog();

  @override
  State<_AddLinkDialog> createState() => _AddLinkDialogState();
}

class _AddLinkDialogState extends State<_AddLinkDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    var url = _controller.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Bir link gir.');
      return;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    if (Uri.tryParse(url)?.host.contains('.') != true) {
      setState(() => _error = 'Geçerli bir link gir.');
      return;
    }
    Navigator.of(context).pop(url);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Link'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(hintText: 'https://...', errorText: _error),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Vazgeç')),
        FilledButton(onPressed: _submit, child: const Text('Ekle')),
      ],
    );
  }
}

class _CaptureTile extends StatelessWidget {
  const _CaptureTile({
    required this.icon,
    required this.label,
    this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      enabled: enabled,
      onTap: enabled ? onTap : null,
    );
  }
}
