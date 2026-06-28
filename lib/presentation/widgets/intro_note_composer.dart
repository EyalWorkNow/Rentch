import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/repositories/property_likes_repository.dart';
import 'package:flutter/material.dart';

/// A tiny RTL composer that lets a tenant attach a short intro note (≤140 chars)
/// to their "like", so they can stand out to the landlord (Feature #6).
///
/// It is intentionally self-contained: it returns the typed text via [onChanged]
/// (live) and exposes the current value through a [IntroNoteController]. Drop it
/// into a sheet/dialog and read `controller.text` when the user confirms.
///
/// Two starter chips pre-fill common, reassuring phrasings.
class IntroNoteComposer extends StatefulWidget {
  const IntroNoteComposer({
    super.key,
    this.controller,
    this.onChanged,
    this.initialText = '',
    this.autofocus = false,
  });

  /// Optional external controller so a host sheet can read the final value.
  final IntroNoteController? controller;

  /// Called whenever the note text changes (already trimmed to the max length).
  final ValueChanged<String>? onChanged;

  final String initialText;
  final bool autofocus;

  /// The starter chips offered to the tenant.
  static const List<String> starterChips = <String>[
    'משפחה שקטה, חוזה ארוך',
    'אישור הכנסה מוכן',
  ];

  /// The hard character limit on the note (mirrors the repository field).
  static int get maxLength => PropertyLikesRepository.introMessageMaxLength;

  @override
  State<IntroNoteComposer> createState() => _IntroNoteComposerState();
}

class _IntroNoteComposerState extends State<IntroNoteComposer> {
  late final TextEditingController _text;
  late final IntroNoteController _note;

  @override
  void initState() {
    super.initState();
    _note = widget.controller ?? IntroNoteController();
    final seed = widget.initialText.isNotEmpty
        ? widget.initialText
        : _note.text;
    _text = TextEditingController(text: seed);
    _note.attach(_text);
    _text.addListener(_handleChange);
  }

  void _handleChange() {
    widget.onChanged?.call(_text.text.trim());
    if (mounted) setState(() {});
  }

  void _applyChip(String value) {
    _text.text = value;
    _text.selection = TextSelection.collapsed(offset: value.length);
  }

  @override
  void dispose() {
    _text.removeListener(_handleChange);
    // Only dispose controllers we created.
    if (widget.controller == null) _note.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = IntroNoteComposer.maxLength - _text.text.characters.length;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'הוסיפו מילה קצרה על עצמכם',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'משפט אחד שגורם לבעל הדירה לשים לב אליכם (לא חובה).',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final chip in IntroNoteComposer.starterChips)
                ActionChip(
                  label: Text(chip),
                  labelStyle: TextStyle(
                    fontSize: 13,
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w600,
                  ),
                  backgroundColor: AppColors.primaryLight2,
                  side: BorderSide(color: AppColors.primaryLight),
                  onPressed: () => _applyChip(chip),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            autofocus: widget.autofocus,
            maxLength: IntroNoteComposer.maxLength,
            maxLines: 3,
            minLines: 2,
            textInputAction: TextInputAction.done,
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'למשל: זוג צעיר, ללא חיות, חוזה לשנתיים',
              counterText: '$remaining תווים נותרו',
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.borderLight),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.borderLight),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lightweight controller that exposes the composer's current note text without
/// forcing the host to hold the underlying [TextEditingController].
class IntroNoteController extends ChangeNotifier {
  TextEditingController? _inner;

  void attach(TextEditingController inner) {
    _inner = inner;
  }

  /// The current note, trimmed and clamped to the max length.
  String get text {
    final raw = _inner?.text.trim() ?? '';
    return raw.length > IntroNoteComposer.maxLength
        ? raw.substring(0, IntroNoteComposer.maxLength)
        : raw;
  }
}
