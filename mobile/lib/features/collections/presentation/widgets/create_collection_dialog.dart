import 'package:flutter/material.dart';

/// Returns the entered name, or `null` if the user cancelled.
Future<String?> showCreateCollectionDialog(BuildContext context, {String? initialName}) {
  final controller = TextEditingController(text: initialName);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(initialName == null ? 'Yeni Koleksiyon' : 'Koleksiyonu Yeniden Adlandır'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(hintText: 'Örn: Docker Notları'),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('Kaydet'),
        ),
      ],
    ),
  );
}
