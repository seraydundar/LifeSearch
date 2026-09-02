import 'package:flutter/material.dart';

import '../../domain/entities/item.dart';

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
