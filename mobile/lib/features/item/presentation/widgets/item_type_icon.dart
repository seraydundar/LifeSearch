import 'package:flutter/material.dart';

import '../../domain/entities/item.dart';

/// A fixed accent per content type, so a note/PDF/screenshot/etc. reads at
/// a glance from its color alone — Library grid/list, Home's "Recently
/// Added", search results and item detail all share it, so the same type
/// always looks the same everywhere. Deliberately a soft, mid-tone
/// palette (not the app's indigo — that's reserved for search/brand) to
/// stay in the "minimal, not AI-glow" register (requirements doc, section
/// 67) rather than reading as a full color-coded system.
Color itemTypeColor(ItemType type) {
  return switch (type) {
    ItemType.note => Colors.amber.shade700,
    ItemType.image => Colors.purple.shade400,
    ItemType.screenshot => Colors.teal.shade400,
    ItemType.pdf => Colors.red.shade400,
    ItemType.audio => Colors.green.shade600,
    ItemType.url => Colors.blue.shade400,
    ItemType.document => Colors.blueGrey.shade400,
  };
}

IconData itemTypeIcon(ItemType type) {
  return switch (type) {
    ItemType.note => Icons.notes_outlined,
    ItemType.image => Icons.image_outlined,
    ItemType.screenshot => Icons.screenshot_outlined,
    ItemType.pdf => Icons.picture_as_pdf_outlined,
    ItemType.audio => Icons.mic_outlined,
    ItemType.url => Icons.link,
    ItemType.document => Icons.description_outlined,
  };
}

String itemTypeLabel(ItemType type) {
  return switch (type) {
    ItemType.note => 'Not',
    ItemType.image => 'Görsel',
    ItemType.screenshot => 'Screenshot',
    ItemType.pdf => 'PDF',
    ItemType.audio => 'Ses',
    ItemType.url => 'Link',
    ItemType.document => 'Belge',
  };
}
