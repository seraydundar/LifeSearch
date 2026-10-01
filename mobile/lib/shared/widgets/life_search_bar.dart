import 'dart:async';

import 'package:flutter/material.dart';

/// Hint-text prompts the search box rotates through to preview natural-language queries.
const _examplePrompts = <String>[
  'Search your life...',
  'Geçen ay baktığım siyah monitörü bul',
  'Docker hakkında kaydettiğim not neydi?',
  'Prag\'da gitmek istediğim kahveciyi bul',
  'Garanti süresi yakında bitecek ürünlerim hangileri?',
  'İçinde PostgreSQL\'den bahsettiğim notları bul',
];

/// Shared by Home's `readOnly` teaser and the Search tab's live field, so both stay visually identical.
class LifeSearchBar extends StatefulWidget {
  const LifeSearchBar({
    super.key,
    this.controller,
    this.readOnly = false,
    this.autofocus = false,
    this.onTap,
    this.onChanged,
    this.onSubmitted,
    this.suffixIcon,
  });

  final TextEditingController? controller;

  /// True for the Home screen teaser — taps navigate to `/search` instead of opening the keyboard in place.
  final bool readOnly;
  final bool autofocus;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Overrides the default trailing sparkle hint (e.g. the Search tab's clear button once there's a query).
  final Widget? suffixIcon;

  @override
  State<LifeSearchBar> createState() => _LifeSearchBarState();
}

class _LifeSearchBarState extends State<LifeSearchBar> {
  late final _focusNode = FocusNode()..addListener(() => setState(() {}));
  int _promptIndex = 0;
  Timer? _rotation;

  @override
  void initState() {
    super.initState();
    _rotation = Timer.periodic(const Duration(milliseconds: 3200), (_) {
      if (!mounted) return;
      // Only cycle an idle teaser or an empty, unfocused field.
      if (widget.readOnly || (_isEmpty && !_focusNode.hasFocus)) {
        setState(() => _promptIndex = (_promptIndex + 1) % _examplePrompts.length);
      }
    });
  }

  bool get _isEmpty => widget.controller?.text.trim().isEmpty ?? true;

  @override
  void dispose() {
    _rotation?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trailing = widget.suffixIcon ??
        (_isEmpty
            ? Icon(
                Icons.auto_awesome_outlined,
                size: 20,
                color: theme.colorScheme.primary.withValues(alpha: 0.55),
              )
            : null);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        readOnly: widget.readOnly,
        autofocus: widget.autofocus,
        textInputAction: TextInputAction.search,
        onTap: widget.onTap,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        style: theme.textTheme.bodyLarge,
        decoration: InputDecoration(
          hintText: _examplePrompts[_promptIndex],
          prefixIcon: Icon(Icons.search, color: theme.colorScheme.primary),
          suffixIcon: trailing,
          filled: true,
          fillColor: theme.colorScheme.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
          ),
        ),
      ),
    );
  }
}
