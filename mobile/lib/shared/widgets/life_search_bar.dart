import 'dart:async';

import 'package:flutter/material.dart';

/// Example queries from the requirements doc (section 1) that the search
/// box cycles through in its hint text, so an idle field sells the
/// natural-language pitch instead of reading like a plain filename search.
const _examplePrompts = <String>[
  'Search your life...',
  'Geçen ay baktığım siyah monitörü bul',
  'Docker hakkında kaydettiğim not neydi?',
  'Prag\'da gitmek istediğim kahveciyi bul',
  'Garanti süresi yakında bitecek ürünlerim hangileri?',
  'İçinde PostgreSQL\'den bahsettiğim notları bul',
];

/// The search box used on both Home (a `readOnly` teaser that opens the
/// Search tab) and the Search tab itself (a live field) — one component so
/// the two stay visually identical and only diverge in behavior.
///
/// It's LifeSearch's most central piece of UI (requirements doc, section
/// 67: "Google Search, but for your personal digital life"), so it gets a
/// bit more visual weight than a plain `TextField`: a soft shadow to lift
/// it off the surface, and a rotating hint that previews the kind of
/// natural-language query the app actually understands.
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

  /// True for the Home screen teaser — taps navigate to `/search` instead
  /// of opening the keyboard in place.
  final bool readOnly;
  final bool autofocus;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Overrides the default trailing sparkle hint (e.g. the Search tab's
  /// clear button once there's a query).
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
      // Only cycle while there's nothing to distract from: an idle teaser,
      // or an empty field that isn't currently being typed into.
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
