import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../shared/extensions/build_context_x.dart';
import '../../../../shared/widgets/private_item_locked_view.dart';
import '../../../collections/presentation/widgets/add_to_collection_sheet.dart';
import '../../../search/domain/entities/search_result.dart';
import '../../../search/presentation/providers/search_providers.dart';
import '../../domain/entities/item.dart';
import '../providers/item_providers.dart';
import '../widgets/duplicate_banner.dart';
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
  // Distinct from "still loading" so the UI can show a retry affordance.
  bool _signedUrlError = false;
  bool _isDeleting = false;
  Item? _duplicateTarget;

  /// Captured once from the item this screen was *opened* with, not
  /// from `_item.private` afterwards: marking the open item private via
  /// [_togglePrivate] must not immediately lock the user out of it.
  late final bool _requiresRevealToView;

  @override
  void initState() {
    super.initState();
    // Search/Ask AI/Related Items push a trimmed stand-in `Item`; correct
    // it immediately from the local cache if available, rather than
    // waiting for the first `ref.listen` change below.
    final fresh = ref.read(watchItemByIdProvider(widget.item.id));
    if (fresh != null) _item = fresh;
    _requiresRevealToView = _item.private;
    _loadSignedUrl();
    _loadDuplicateTarget();
  }

  /// Called on every local change to [watchItemByIdProvider] (see
  /// `build()`'s `ref.listen`), so a background sync completing this
  /// item shows up live. A `null` emission is ignored rather than
  /// replacing a real item with "not found" — it just means not synced
  /// to this device yet.
  void _applyFreshItem(Item fresh, Item? previous) {
    final hadStoragePath = _item.storagePath;
    final hadDuplicateOfItemId = _item.duplicateOfItemId;
    setState(() => _item = fresh);
    if (fresh.storagePath != null && fresh.storagePath != hadStoragePath) {
      _loadSignedUrl(); // wasn't known yet when we last checked
    }
    if (fresh.duplicateOfItemId != null && fresh.duplicateOfItemId != hadDuplicateOfItemId) {
      _loadDuplicateTarget(); // ditto
    }
    // Re-fetch tags/entities on pending/processing -> completed: the
    // one-shot FutureProviders cached an empty result from before the
    // pipeline finished. `previous == null` (first emission) is excluded
    // since initState()'s correction already covers that case.
    if (previous != null &&
        previous.processingStatus != 'completed' &&
        fresh.processingStatus == 'completed') {
      ref.invalidate(itemTagsProvider(fresh.id));
      ref.invalidate(itemEntitiesProvider(fresh.id));
    }
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
    setState(() => _signedUrlError = false); // clears a previous failure on retry
    try {
      final url = await ref.read(itemRepositoryProvider).getSignedUrl(path);
      if (mounted) setState(() => _signedUrl = url);
    } catch (_) {
      if (mounted) setState(() => _signedUrlError = true);
    }
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

  /// Marking/unmarking needs no biometric check — only *revealing*
  /// already-private items does (see `LibraryScreen`'s reveal button).
  Future<void> _togglePrivate() async {
    final next = !_item.private;
    setState(() => _item = _item.copyWith(private: next)); // optimistic
    try {
      await ref.read(itemRepositoryProvider).setPrivate(_item.id, next);
    } catch (_) {
      if (!mounted) return;
      setState(() => _item = _item.copyWith(private: !next)); // revert
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

  Future<void> _retryProcessing() async {
    setState(() => _item = _item.copyWith(processingStatus: 'pending')); // optimistic
    try {
      await ref.read(itemRepositoryProvider).retryProcessing(_item.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _item = _item.copyWith(processingStatus: 'failed')); // revert
      context.showErrorSnackBar('Tekrar denenemedi.');
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
    ref.listen(watchItemByIdProvider(widget.item.id), (previous, next) {
      if (next != null) _applyFreshItem(next, previous);
    });
    // ref.watch, not read: reacts live if AppLockGate resets reveal
    // while this screen is open.
    if (_requiresRevealToView && !ref.watch(privateItemsRevealedProvider)) {
      return const PrivateItemLockedView();
    }
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
            icon: Icon(_item.private ? Icons.lock_outline : Icons.lock_open_outlined),
            tooltip: _item.private ? 'Private\'dan çıkar' : 'Private yap',
            onPressed: _togglePrivate,
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
            DuplicateBanner(
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
          else if (isImage && _signedUrlError)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(Icons.broken_image_outlined, size: 48),
                    const SizedBox(height: 8),
                    const Text('Görsel yüklenemedi.'),
                    TextButton.icon(
                      onPressed: _loadSignedUrl,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Tekrar Dene'),
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Icon(itemTypeIcon(_item.type), size: 48, color: itemTypeColor(_item.type)),
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
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Chip(label: Text(_processingLabel(_item.processingStatus))),
                if (_item.processingStatus == 'failed')
                  TextButton.icon(
                    onPressed: _retryProcessing,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Tekrar Dene'),
                  ),
              ],
            ),
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
          else if (!isImage && _item.storagePath != null && _signedUrlError)
            OutlinedButton.icon(
              onPressed: _loadSignedUrl,
              icon: const Icon(Icons.refresh),
              label: const Text('Dosya bağlantısı alınamadı — Tekrar Dene'),
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

/// Horizontal strip of related items; hidden while loading/empty/errored.
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
                Icon(itemTypeIcon(result.itemType), size: 20, color: itemTypeColor(result.itemType)),
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

/// EXIF capture location; tapping opens it in Maps. No reverse geocoding.
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
