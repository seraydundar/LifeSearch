import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../item/domain/entities/item.dart';
import '../../../item/presentation/providers/item_providers.dart';
import '../../../item/presentation/widgets/item_type_icon.dart';

/// Grid counterpart to `ItemListTile`; shows a thumbnail for images/
/// screenshots, falling back to the type icon otherwise or on load failure.
class ItemGridTile extends ConsumerStatefulWidget {
  const ItemGridTile({super.key, required this.item});

  final Item item;

  @override
  ConsumerState<ItemGridTile> createState() => _ItemGridTileState();
}

class _ItemGridTileState extends ConsumerState<ItemGridTile> {
  Future<String>? _signedUrlFuture;

  bool get _isImage =>
      widget.item.type == ItemType.image || widget.item.type == ItemType.screenshot;

  @override
  void initState() {
    super.initState();
    final path = widget.item.storagePath;
    if (_isImage && path != null) {
      _signedUrlFuture = ref.read(itemRepositoryProvider).getSignedUrl(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        final route = item.type == ItemType.note ? '/item/${item.id}/note' : '/item/${item.id}';
        context.push(route, extra: item);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_signedUrlFuture != null)
              FutureBuilder<String>(
                future: _signedUrlFuture,
                builder: (context, snapshot) {
                  final url = snapshot.data;
                  if (url == null) return _FallbackIcon(item: item);
                  return Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => _FallbackIcon(item: item),
                  );
                },
              )
            else
              _FallbackIcon(item: item),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.65)],
                  ),
                ),
                child: Text(
                  item.displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (item.favorite)
              const Positioned(
                top: 6,
                right: 6,
                child: Icon(Icons.star, size: 18, color: Colors.amber, shadows: [
                  Shadow(color: Colors.black45, blurRadius: 4),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

class _FallbackIcon extends StatelessWidget {
  const _FallbackIcon({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    final color = itemTypeColor(item.type);
    return ColoredBox(
      color: color.withValues(alpha: 0.12),
      child: Center(
        child: Icon(itemTypeIcon(item.type), size: 32, color: color),
      ),
    );
  }
}
