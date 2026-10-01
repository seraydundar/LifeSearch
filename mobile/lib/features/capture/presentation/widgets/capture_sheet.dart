import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../../shared/extensions/build_context_x.dart';
import '../../../item/domain/entities/item.dart';
import '../../../item/presentation/providers/item_providers.dart';
import '../screens/audio_recorder_screen.dart';
import '../screens/camera_screen.dart';
import 'capture_platform_support.dart';

Future<void> showCaptureSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    // Without this the sheet is capped at ~half screen height and overflows on shorter screens / larger text.
    isScrollControlled: true,
    builder: (context) => const _CaptureSheet(),
  );
}

class _CaptureSheet extends ConsumerWidget {
  const _CaptureSheet();

  // Per-platform logic lives in capture_platform_support.dart as plain functions of isWeb, for deterministic tests.
  bool get _fileCaptureSupported => fileCaptureSupportedFor(isWeb: kIsWeb);

  bool get _cameraSupported => cameraSupportedFor(isWeb: kIsWeb);

  bool get _audioRecordingSupported => audioRecordingSupportedFor(isWeb: kIsWeb);

  String? get _fileCaptureUnavailableReason => fileCaptureUnavailableReasonFor(isWeb: kIsWeb);

  String? get _cameraUnavailableReason => cameraUnavailableReasonFor(isWeb: kIsWeb);

  String? get _audioRecordingUnavailableReason =>
      audioRecordingUnavailableReasonFor(isWeb: kIsWeb);

  Future<void> _pickAndUpload(
    BuildContext context,
    WidgetRef ref, {
    required FileType fileType,
    required ItemType Function(String? extension) itemTypeFor,
    List<String>? allowedExtensions,
  }) async {
    final files = await FilePicker.pickFiles(
      type: fileType,
      allowedExtensions: allowedExtensions,
    );
    final file = files.isEmpty ? null : files.single;
    if (file == null) return;

    if (!context.mounted) return;
    Navigator.of(
      context,
    ).pop(); // close sheet; progress shows on the screen behind it

    // web never gives a `file:` path, so read bytes directly instead.
    final ok = kIsWeb
        ? await ref
            .read(captureControllerProvider.notifier)
            .uploadFileBytes(
              bytes: await file.readAsBytes(),
              originalFilename: file.name,
              mimeType: _guessMimeType(file.extension),
              type: itemTypeFor(file.extension),
            )
        : await ref
            .read(captureControllerProvider.notifier)
            .uploadFile(
              localFilePath: file.path!,
              originalFilename: file.name,
              mimeType: _guessMimeType(file.extension),
              type: itemTypeFor(file.extension),
            );

    if (!context.mounted) return;
    if (!ok) {
      final error = ref.read(captureControllerProvider).error;
      context.showErrorSnackBar(error?.toString() ?? 'Yükleme başarısız oldu.');
    }
  }

  Future<void> _takePhoto(BuildContext context, WidgetRef ref) async {
    final path = await Navigator.of(
      context,
      rootNavigator: true,
    ).push<String>(MaterialPageRoute(builder: (_) => const CameraScreen()));
    if (!context.mounted) return;
    Navigator.of(
      context,
    ).pop(); // close the sheet now that we're back from the camera
    if (path == null) return;

    final ok = await ref
        .read(captureControllerProvider.notifier)
        .uploadFile(
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
    Navigator.of(
      context,
    ).pop(); // close the sheet now that we're back from recording
    if (path == null) return;

    final ok = await ref
        .read(captureControllerProvider.notifier)
        .uploadFile(
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
    if (url == null) return;

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
      'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'txt' => 'text/plain',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'heic' => 'image/heic',
      _ => 'application/octet-stream',
    };
  }

  /// pdf/docx/txt per backend SUPPORTED_TYPES; pdf keeps its own ItemType, the rest become ItemType.document.
  ItemType _documentItemTypeFor(String? extension) {
    return switch (extension?.toLowerCase()) {
      'pdf' => ItemType.pdf,
      _ => ItemType.document,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUploading = ref.watch(captureControllerProvider).isLoading;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        // Scrollable fallback for small screens / larger system text.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 4,
                ),
                child: Text(
                  'Add to LifeSearch',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
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
                enabled: !isUploading && _fileCaptureSupported,
                unavailableReason: _fileCaptureUnavailableReason,
                onTap: () => _pickAndUpload(
                  context,
                  ref,
                  fileType: FileType.image,
                  itemTypeFor: (_) => ItemType.image,
                ),
              ),
              // Explicit tile rather than guessing from filename/EXIF — unreliable since Share/sync often strips it.
              _CaptureTile(
                icon: Icons.screenshot_outlined,
                label: 'Choose Screenshot',
                enabled: !isUploading && _fileCaptureSupported,
                unavailableReason: _fileCaptureUnavailableReason,
                onTap: () => _pickAndUpload(
                  context,
                  ref,
                  fileType: FileType.image,
                  itemTypeFor: (_) => ItemType.screenshot,
                ),
              ),
              _CaptureTile(
                icon: Icons.description_outlined,
                label: 'Upload Document',
                enabled: !isUploading && _fileCaptureSupported,
                unavailableReason: _fileCaptureUnavailableReason,
                onTap: () => _pickAndUpload(
                  context,
                  ref,
                  fileType: FileType.custom,
                  allowedExtensions: const ['pdf', 'docx', 'txt'],
                  itemTypeFor: _documentItemTypeFor,
                ),
              ),
              _CaptureTile(
                icon: Icons.camera_alt_outlined,
                label: 'Take Photo',
                enabled: !isUploading && _fileCaptureSupported && _cameraSupported,
                unavailableReason: _cameraUnavailableReason,
                onTap: () => _takePhoto(context, ref),
              ),
              _CaptureTile(
                icon: Icons.mic_none_outlined,
                label: 'Record Audio',
                enabled: !isUploading && _audioRecordingSupported,
                unavailableReason: _audioRecordingUnavailableReason,
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
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
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
    this.unavailableReason,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;

  /// Why this tile is disabled for this platform; `null` shows no subtitle.
  final String? unavailableReason;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: unavailableReason == null ? null : Text(unavailableReason!),
      enabled: enabled,
      onTap: enabled ? onTap : null,
    );
  }
}
