import 'package:flutter/material.dart';

import '../../domain/entities/item.dart';

/// Flags a possible duplicate; lets the user jump to it or dismiss.
/// Shared by `ItemDetailScreen` and `NoteEditorScreen`.
class DuplicateBanner extends StatelessWidget {
  const DuplicateBanner({super.key, required this.target, required this.onView, required this.onDismiss});

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
