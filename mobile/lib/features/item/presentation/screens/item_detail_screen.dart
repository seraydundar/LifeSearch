import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../shared/extensions/build_context_x.dart';
import '../../../collections/presentation/widgets/add_to_collection_sheet.dart';
import '../../../search/domain/entities/search_result.dart';
import '../../../search/presentation/providers/search_providers.dart';
import '../../domain/entities/item.dart';
import '../providers/item_providers.dart';
import '../widgets/entities_row.dart';
import '../widgets/item_type_icon.dart';
import '../widgets/tags_row.dart';

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
  Item? _duplicateTarget;

  @override
  void initState() {
    super.initState();
    _loadSignedUrl();
    _loadDuplicateTarget();
  }

  Future<void> _loadDuplicateTarget() async {
    final duplicateOfItemId = _item.duplicateOfItemId;
    if (duplicateOfItemId == null || _item.duplicateDismissed) return;
    final target = await ref.read(itemRepositoryProvider).findById(duplicateOfItemId);
    if (mounted) setState(() => _duplicateTarget = target);
  }

  Future<void> _dismissDuplicate() async {
    setState(() => _item = _item.copyWith(duplicateDismissed: true)); // optimistic
    try {
      await ref.read(itemRepositoryProvider).dismissDuplicate(_item.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _item = _item.copyWith(duplicateDismissed: false)); // revert
      context.showErrorSnackBar('Güncellenemedi.');
    }
  }

  void _openDuplicateTarget() {
    final target = _duplicateTarget;
    if (target == null) return;
    final route = target.type == ItemType.note ? '/item/${target.id}/note' : '/item/${target.id}';
    context.push(route, extra: target);
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

  void _openRelated(SearchResult related) {
    final route = related.itemType == ItemType.note
        ? '/item/${related.itemId}/note'
        : '/item/${related.itemId}';
    context.push(
      route,
      extra: Item(
        id: related.itemId,
        type: related.itemType,
        title: related.itemTitle,
        processingStatus: 'completed',
        favorite: false,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isImage = _item.type == ItemType.image || _item.type == ItemType.screenshot;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_outlined),
            tooltip: 'Koleksiyona ekle',
            onPressed: () => showAddToCollectionSheet(context, _item.id),
          ),
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
          if (!_item.duplicateDismissed && _item.duplicateOfItemId != null && _duplicateTarget != null) ...[
            _DuplicateBanner(
              target: _duplicateTarget!,
              onView: _openDuplicateTarget,
              onDismiss: _dismissDuplicate,
            ),
            const SizedBox(height: 16),
          ],
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
          if (_item.capturedAt != null)
            _MetaRow(label: 'Çekim', value: DateFormat('d MMM y, HH:mm').format(_item.capturedAt!)),
          if (_item.latitude != null && _item.longitude != null)
            _LocationRow(latitude: _item.latitude!, longitude: _item.longitude!),
          const SizedBox(height: 12),
          TagsRow(itemId: _item.id),
          const SizedBox(height: 8),
          EntitiesRow(itemId: _item.id),
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
          const SizedBox(height: 24),
          _RelatedSection(itemId: _item.id, onTap: _openRelated),
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

/// Flags a possible duplicate found by the backend pipeline (requirements
/// doc, section 46) — never blocks anything, just lets the user jump to
/// the other item or dismiss the flag for good.
class _DuplicateBanner extends StatelessWidget {
  const _DuplicateBanner({required this.target, required this.onView, required this.onDismiss});

  final Item target;
  final VoidCallback onView;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.copy_all_outlined, size: 20, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Bu içerik zaten eklenmiş gibi görünüyor',
                      style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              target.title ?? target.originalFilename ?? 'Untitled',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: onDismiss, child: const Text('Yoksay')),
                const SizedBox(width: 4),
                FilledButton.tonal(onPressed: onView, child: const Text('Görüntüle')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal strip of semantically related items (requirements doc,
/// section 47) — hidden entirely while loading/empty/errored so it never
/// distracts from the item's own content.
class _RelatedSection extends ConsumerWidget {
  const _RelatedSection({required this.itemId, required this.onTap});

  final String itemId;
  final ValueChanged<SearchResult> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final related = ref.watch(relatedItemsProvider(itemId));
    return related.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('İlgili İçerikler', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _RelatedCard(result: item, onTap: () => onTap(item));
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RelatedCard extends StatelessWidget {
  const _RelatedCard({required this.result, required this.onTap});

  final SearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(itemTypeIcon(result.itemType), size: 20),
                const SizedBox(height: 8),
                Text(
                  result.itemTitle ?? 'Untitled',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// EXIF capture location (requirements doc, section 8-12) — tapping opens
/// it in Maps. Coordinates are shown as-is (no reverse geocoding — that
/// needs its own API/key) rounded to ~11m precision, which is plenty for
/// "where was I when I took this".
class _LocationRow extends StatelessWidget {
  const _LocationRow({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => launchUrl(
        Uri.parse('https://maps.apple.com/?ll=$latitude,$longitude'),
        mode: LaunchMode.externalApplication,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(width: 100, child: Text('Konum', style: theme.textTheme.bodySmall)),
            Expanded(
              child: Text(
                '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary),
              ),
            ),
            Icon(Icons.open_in_new, size: 14, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
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
