import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/extensions/build_context_x.dart';
import '../../../collections/presentation/widgets/add_to_collection_sheet.dart';
import '../../domain/entities/item.dart';
import '../providers/item_providers.dart';

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

  bool get _isEditing => widget.item != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) _loadContent();
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
    final isSaving = ref.watch(noteEditorControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Notu Düzenle' : 'Yeni Not'),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.folder_outlined),
              tooltip: 'Koleksiyona ekle',
              onPressed: () => showAddToCollectionSheet(context, widget.item!.id),
            ),
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
                  const Divider(height: 24),
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
