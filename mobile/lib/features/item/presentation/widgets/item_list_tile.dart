import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/item.dart';
import 'item_type_icon.dart';

/// Standard row for an item in any list. Optional `trailing` slot lets a
/// screen add its own action (e.g. "remove from this collection").
class ItemListTile extends StatelessWidget {
  const ItemListTile({super.key, required this.item, this.trailing});

  final Item item;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: itemTypeColor(item.type).withValues(alpha: 0.15),
        foregroundColor: itemTypeColor(item.type),
        child: Icon(itemTypeIcon(item.type)),
      ),
      title: Text(item.displayTitle, maxLines: 1),
      subtitle: Text(
        '${itemTypeLabel(item.type)} · ${DateFormat('d MMM').format(item.createdAt)}',
      ),
      trailing: trailing ?? (item.favorite ? const Icon(Icons.star, size: 20) : null),
      onTap: () {
        final route = item.type == ItemType.note ? '/item/${item.id}/note' : '/item/${item.id}';
        context.push(route, extra: item);
      },
    );
  }
}
