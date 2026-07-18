import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/constants/glossary.dart';
import 'package:dating_app/presentation/widgets/rently_icon.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

/// Wraps a label / chip with a tap-to-explain glossary popup.
///
/// Tapping [child] shows the plain-Hebrew definition of [term] (from
/// [Glossary]) in a small bottom sheet. If the term has no definition the
/// child is returned untouched (no tap handler, no extra layout), so it is
/// safe to wrap every chip indiscriminately.
///
/// Wire it around an amenity chip:
///   TermTooltip(term: 'ממ"ד', child: AmenityChip(label: 'ממ"ד'));
class TermTooltip extends StatelessWidget {
  const TermTooltip({
    super.key,
    required this.term,
    required this.child,
    this.showHintIcon = true,
  });

  /// The rental term to look up. Falls back to no-op if unknown to [Glossary].
  final String term;

  /// The widget being wrapped (a chip, label, etc.).
  final Widget child;

  /// Whether to overlay a small "?" hint badge so users know it is tappable.
  final bool showHintIcon;

  @override
  Widget build(BuildContext context) {
    final definition = Glossary.define(term);
    if (definition == null) return child;

    return Semantics(
      button: true,
      label: 'הסבר על המונח $term',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _showDefinition(context, term, definition),
        child: showHintIcon
            ? Stack(
                clipBehavior: Clip.none,
                children: [
                  child,
                  Positioned(
                    top: -5,
                    left: -5,
                    child: _HintBadge(),
                  ),
                ],
              )
            : child,
      ),
    );
  }

  static Future<void> _showDefinition(
    BuildContext context,
    String term,
    String definition,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: _TermDefinitionSheet(term: term, definition: definition),
      ),
    );
  }
}

class _HintBadge extends StatelessWidget {
  const _HintBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: const Text(
        '?',
        style: TextStyle(
          fontSize: 10,
          height: 1.0,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _TermDefinitionSheet extends StatelessWidget {
  const _TermDefinitionSheet({required this.term, required this.definition});

  final String term;
  final String definition;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.slate50,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 54,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.navy.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: RentlyIcon(
                      IconsaxPlusBold.book_1,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      term,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                definition,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textOnPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'הבנתי',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
