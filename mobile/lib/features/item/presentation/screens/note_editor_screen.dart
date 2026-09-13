import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/extensions/build_context_x.dart';
import '../../../collections/presentation/widgets/add_to_collection_sheet.dart';
import '../../domain/entities/item.dart';
import '../providers/item_providers.dart';
import '../widgets/entities_row.dart';
import '../widgets/tags_row.dart';

/// Create mode when [item] is null, edit mode otherwise. Content is loaded
/// lazily in edit mode since the list view never fetches note bodies.
class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({super.key, this.item});

  final Item? item;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  late final _titleController = TextEditingController(text: widget.item?.title);
  late final _contentController = TextEditingController();
  bool _loadingContent = false;
  bool _isDeleting = false;

  /// `null` in create mode. Mutable (unlike `widget.item`) so favorite/
  /// private/retry below can update it optimistically and so
  /// `watchItemByIdProvider` (see `build()`) can keep it fresh — notes
  /// go through the same AI pipeline (tagging/entities/embedding) as
  /// every other item type, so this screen needs the same "sil/favori/
  /// private/retry" actions `ItemDetailScreen` already has (Faz 12,
  /// madde 12, denetim düzeltmesi — see docs/roadmap.md: this screen
  /// had none of them before).
  late Item? _item = widget.item;

  bool get _isEditing => widget.item != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      // Same immediate-correction reasoning as `ItemDetailScreen`'s
      // `initState()` — see that widget's docstring.
      final fresh = ref.read(watchItemByIdProvider(widget.item!.id));
      if (fresh != null) _item = fresh;
      _loadContent();
    }
  }

  Future<void> _loadContent() async {
    setState(() => _loadingContent = true);
    final content = await ref.read(itemRepositoryProvider).fetchNoteContent(widget.item!.id);
    if (!mounted) return;
    _contentController.text = content;
    setState(() => _loadingContent = false);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _toggleFavorite() async {
    final current = _item!;
    final next = !current.favorite;
    setState(() => _item = current.copyWith(favorite: next)); // optimistic
    try {
      await ref.read(itemRepositoryProvider).setFavorite(current.id, next);
    } catch (_) {
      if (!mounted) return;
      setState(() => _item = current); // revert
      context.showErrorSnackBar('Güncellenemedi.');
    }
  }

  /// Item-level Privacy Mode (Faz 11, madde 2 — see docs/roadmap.md) —
  /// same contract as `ItemDetailScreen._togglePrivate()`.
  Future<void> _togglePrivate() async {
    final current = _item!;
    final next = !current.private;
    setState(() => _item = current.copyWith(private: next)); // optimistic
    try {
      await ref.read(itemRepositoryProvider).setPrivate(current.id, next);
    } catch (_) {
      if (!mounted) return;
      setState(() => _item = current); // revert
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
      await ref.read(itemRepositoryProvider).deleteItem(_item!);
      if (mounted && context.canPop()) context.pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      context.showErrorSnackBar('Silinemedi.');
    }
  }

  /// Same contract as `ItemDetailScreen._retryProcessing()`.
  Future<void> _retryProcessing() async {
    final current = _item!;
    setState(() => _item = current.copyWith(processingStatus: 'pending')); // optimistic
    try {
      await ref.read(itemRepositoryProvider).retryProcessing(current.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _item = current.copyWith(processingStatus: 'failed')); // revert
      context.showErrorSnackBar('Tekrar denenemedi.');
    }
  }

  String _processingLabel(String status) {
    return switch (status) {
      'pending' => 'İşlenmeyi bekliyor',
      'processing' => 'İşleniyor...',
      'failed' => 'İşlenemedi',
      _ => status,
    };
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      context.showErrorSnackBar('Bir başlık gir.');
      return;
    }

    final saved = await ref.read(noteEditorControllerProvider.notifier).save(
          itemId: widget.item?.id,
          title: title,
          content: _contentController.text,
        );

    if (!mounted) return;
    if (saved == null && !_isEditing) {
      final error = ref.read(noteEditorControllerProvider).error;
      context.showErrorSnackBar(error?.toString() ?? 'Not kaydedilemedi.');
      return;
    }
    if (context.canPop()) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditing) {
      // Live, not one-shot — same reasoning as `ItemDetailScreen`'s
      // `ref.listen(watchItemByIdProvider(...))` (Faz 12, madde 8 — see
      // docs/roadmap.md): a background sync completing this note's AI
      // processing (or another device changing it) while this screen
      // is open should show up here too, not just after leaving and
      // coming back.
      ref.listen(watchItemByIdProvider(widget.item!.id), (previous, next) {
        if (next == null) return;
        setState(() => _item = next);
        // Same gap `ItemDetailScreen._applyFreshItem` had (denetim
        // düzeltmesi — see docs/roadmap.md): tags/entities are produced
        // by the same AI pipeline run that just finished, but
        // `itemTagsProvider`/`itemEntitiesProvider` are one-shot
        // `FutureProvider`s that fetched (and cached) nothing back when
        // the note was still pending/processing — without this,
        // `TagsRow`/`EntitiesRow` would keep showing no tags/entities
        // until the user left this screen and came back.
        if (previous != null &&
            previous.processingStatus != 'completed' &&
            next.processingStatus == 'completed') {
          ref.invalidate(itemTagsProvider(next.id));
          ref.invalidate(itemEntitiesProvider(next.id));
        }
      });
    }
    final isSaving = ref.watch(noteEditorControllerProvider).isLoading;
    final item = _item;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Notu Düzenle' : 'Yeni Not'),
        actions: [
          if (_isEditing && item != null) ...[
            IconButton(
              icon: const Icon(Icons.folder_outlined),
              tooltip: 'Koleksiyona ekle',
              onPressed: () => showAddToCollectionSheet(context, item.id),
            ),
            IconButton(
              icon: Icon(item.favorite ? Icons.star : Icons.star_border),
              onPressed: _toggleFavorite,
            ),
            IconButton(
              icon: Icon(item.private ? Icons.lock_outline : Icons.lock_open_outlined),
              tooltip: item.private ? 'Private\'dan çıkar' : 'Private yap',
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
          IconButton(
            icon: isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            onPressed: isSaving ? null : _save,
            tooltip: 'Kaydet',
          ),
        ],
      ),
      body: _loadingContent
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _titleController,
                    style: Theme.of(context).textTheme.titleLarge,
                    decoration: const InputDecoration(
                      hintText: 'Başlık',
                      border: InputBorder.none,
                    ),
                  ),
                  if (item != null && item.processingStatus != 'completed') ...[
                    const SizedBox(height: 8),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        Chip(label: Text(_processingLabel(item.processingStatus))),
                        if (item.processingStatus == 'failed')
                          TextButton.icon(
                            onPressed: _retryProcessing,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Tekrar Dene'),
                          ),
                      ],
                    ),
                  ],
                  const Divider(height: 24),
                  if (_isEditing) ...[
                    TagsRow(itemId: widget.item!.id),
                    const SizedBox(height: 8),
                    EntitiesRow(itemId: widget.item!.id),
                    const SizedBox(height: 12),
                  ],
                  Expanded(
                    child: TextField(
                      controller: _contentController,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        hintText: 'Yazmaya başla...',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
