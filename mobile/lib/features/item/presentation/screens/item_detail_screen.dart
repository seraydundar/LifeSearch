import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../shared/extensions/build_context_x.dart';
import '../../domain/entities/item.dart';
import '../providers/item_providers.dart';
import '../widgets/item_type_icon.dart';

/// Read-only detail view for non-note items (image/pdf/document/...).
/// Notes use `NoteEditorScreen` instead — see `app_router.dart`.
class ItemDetailScreen extends ConsumerStatefulWidget {
  const ItemDetailScreen({super.key, required this.item});

  final Item item;

  @override
  ConsumerState<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends ConsumerState<ItemDetailScreen> {
  late Item _item = widget.item;
  String? _signedUrl;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _loadSignedUrl();
  }

  Future<void> _loadSignedUrl() async {
    final path = _item.storagePath;
    if (path == null) return;
    final url = await ref.read(itemRepositoryProvider).getSignedUrl(path);
    if (mounted) setState(() => _signedUrl = url);
  }

  Future<void> _toggleFavorite() async {
    final next = !_item.favorite;
    setState(() => _item = _item.copyWith(favorite: next)); // optimistic
    try {
      await ref.read(itemRepositoryProvider).setFavorite(_item.id, next);
    } catch (_) {
      if (!mounted) return;
      setState(() => _item = _item.copyWith(favorite: !next)); // revert
      context.showErrorSnackBar('Güncellenemedi.');
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bu içeriği sil'),
        content: const Text('Bu işlem geri alınamaz.'),
        actions: [
          TextButton(onPressed: () => context.pop(false), child: const Text('Vazgeç')),
          TextButton(onPressed: () => context.pop(true), child: const Text('Sil')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isDeleting = true);
    try {
      await ref.read(itemRepositoryProvider).deleteItem(_item);
      if (mounted && context.canPop()) context.pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      context.showErrorSnackBar('Silinemedi.');
    }
  }

  Future<void> _openFile() async {
    if (_signedUrl == null) return;
    await launchUrl(Uri.parse(_signedUrl!), mode: LaunchMode.externalApplication);
  }

  Future<void> _openSourceUrl() async {
    final url = _item.sourceUrl;
    if (url == null) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final isImage = _item.type == ItemType.image || _item.type == ItemType.screenshot;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: Icon(_item.favorite ? Icons.star : Icons.star_border),
            onPressed: _toggleFavorite,
          ),
          IconButton(
            icon: _isDeleting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline),
            onPressed: _isDeleting ? null : _delete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (isImage && _signedUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(_signedUrl!, fit: BoxFit.cover),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Icon(itemTypeIcon(_item.type), size: 48),
              ),
            ),
          const SizedBox(height: 20),
          Text(_item.title ?? _item.originalFilename ?? 'Untitled',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(itemTypeLabel(_item.type), style: Theme.of(context).textTheme.bodyMedium),
          if (_item.description != null && _item.description!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_item.description!, style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: 16),
          if (_item.processingStatus != 'completed')
            Chip(label: Text(_processingLabel(_item.processingStatus))),
          const SizedBox(height: 16),
          if (_item.type == ItemType.url)
            _MetaRow(label: 'Link', value: _item.sourceUrl ?? '—')
          else
            _MetaRow(label: 'Dosya adı', value: _item.originalFilename ?? '—'),
          _MetaRow(label: 'Tür', value: _item.mimeType ?? '—'),
          _MetaRow(label: 'Eklenme', value: DateFormat('d MMM y, HH:mm').format(_item.createdAt)),
          const SizedBox(height: 24),
          if (_item.type == ItemType.url)
            FilledButton.icon(
              onPressed: _openSourceUrl,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Bağlantıyı Aç'),
            )
          else if (!isImage && _item.storagePath != null)
            FilledButton.icon(
              onPressed: _signedUrl == null ? null : _openFile,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Dosyayı Aç'),
            ),
        ],
      ),
    );
  }

  String _processingLabel(String status) {
    return switch (status) {
      'pending' => 'İşlenmeyi bekliyor',
      'processing' => 'İşleniyor...',
      'failed' => 'İşlenemedi',
      _ => status,
    };
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
