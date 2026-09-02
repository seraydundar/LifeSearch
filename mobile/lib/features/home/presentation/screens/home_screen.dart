import 'package:flutter/material.dart';

/// Static shell for now — search box and library counts aren't wired to
/// real data until Phase 2+ (item CRUD) and Phase 5 (semantic search).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Good morning 👋', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 20),
            TextField(
              readOnly: true, // becomes real search input in Phase 5
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search your life...',
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text('Recently Added', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            const _EmptyStateCard(
              icon: Icons.inbox_outlined,
              message: 'Henüz içerik eklemedin.\n+ ile ilk içeriğini ekle.',
            ),
            const SizedBox(height: 32),
            Text('Your Library', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            const _LibraryRow(icon: Icons.image_outlined, label: 'Images', count: 0),
            const _LibraryRow(icon: Icons.description_outlined, label: 'Documents', count: 0),
            const _LibraryRow(icon: Icons.notes_outlined, label: 'Notes', count: 0),
            const _LibraryRow(icon: Icons.link, label: 'Links', count: 0),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Wired up in Phase 2 (capture feature: photo/document/note/audio/link).
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 32, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryRow extends StatelessWidget {
  const _LibraryRow({required this.icon, required this.label, required this.count});

  final IconData icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyLarge)),
          Text('$count', style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}
