import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

const List<_LanguageOption> _languageOptions = [
  _LanguageOption('he', 'עברית', '🇮🇱'),
  _LanguageOption('en', 'English', '🇺🇸'),
  _LanguageOption('ar', 'العربية', '🇸🇦'),
  _LanguageOption('fr', 'Français', '🇫🇷'),
  _LanguageOption('es', 'Español', '🇪🇸'),
];

// Shared with the landlord/broker Settings sub-page (profile_screen.dart) and
// the tenant profile screen — a Wrap of pill buttons. For the tighter,
// branding-forward onboarding screen use [LanguageDropdown] instead.
class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key, this.compact = false});

  /// Smaller pills/no shadow — for tight spaces.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Consumer<DatingProvider>(
      builder: (context, provider, _) {
        return Wrap(
          spacing: compact ? 6 : 8,
          runSpacing: compact ? 6 : 8,
          children: _languageOptions.map((opt) {
            final isSelected = provider.languageCode == opt.code;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                provider.setLanguageCode(opt.code);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.symmetric(
                    horizontal: compact ? 12 : 16, vertical: compact ? 7 : 10),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(opt.flag, style: TextStyle(fontSize: compact ? 13 : 15)),
                    const SizedBox(width: 6),
                    Text(
                      opt.label,
                      style: TextStyle(
                        color: isSelected ? Colors.white : AppColors.textPrimary,
                        fontSize: compact ? 12.5 : 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

// A clear, self-labelled CTA row — globe icon + "Language" + current
// selection + chevron — that expands into a flag-labelled menu. Used on the
// onboarding screen, where a bare row of pills (or an unlabelled icon-only
// pill) read as unclear decoration rather than an obvious tappable control.
class LanguageDropdown extends StatelessWidget {
  const LanguageDropdown({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DatingProvider>(
      builder: (context, provider, _) {
        final current = _languageOptions
            .firstWhere((o) => o.code == provider.languageCode, orElse: () => _languageOptions[1]);
        return PopupMenuButton<String>(
          initialValue: current.code,
          onSelected: (code) {
            HapticFeedback.selectionClick();
            provider.setLanguageCode(code);
          },
          offset: const Offset(0, 54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          color: Colors.white,
          elevation: 10,
          itemBuilder: (context) => _languageOptions.map((opt) {
            final isSelected = opt.code == current.code;
            return PopupMenuItem<String>(
              value: opt.code,
              height: 48,
              child: Row(
                children: [
                  Text(opt.flag, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      opt.label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                        color: isSelected ? AppColors.primary : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check_circle_rounded, size: 20, color: AppColors.primary),
                ],
              ),
            );
          }).toList(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.language_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(current.flag, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Text(
                  current.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down_rounded,
                    color: Colors.white, size: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LanguageOption {
  const _LanguageOption(this.code, this.label, this.flag);
  final String code;
  final String label;
  final String flag;
}
