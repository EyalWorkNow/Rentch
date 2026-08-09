import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// First-run "how to use the app" intro.
///
/// A few swipeable cards (Hebrew, RTL, on-brand) that introduce the main tabs
/// and key gestures. Shown ONCE: gated behind the [_seenKey] SharedPreferences
/// flag. Includes a Skip and a final "let's go" CTA.
class AppIntro extends StatefulWidget {
  AppIntro({super.key, required this.onDone});

  /// Called once the user finishes or skips the intro (after the flag is set).
  final VoidCallback onDone;

  static const String _seenKey = 'seen_intro_v1';

  /// Whether the intro has already been shown on this device.
  static Future<bool> hasBeenSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_seenKey) ?? false;
    } catch (_) {
      // If prefs are unavailable, fail "seen" so we never block the app behind
      // a repeating intro.
      return true;
    }
  }

  static Future<void> markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_seenKey, true);
    } catch (_) {}
  }

  @override
  State<AppIntro> createState() => _AppIntroState();
}

class _IntroPage {
  const _IntroPage({
    required this.icon,
    required this.title,
    required this.body,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color accent;
}

class _AppIntroState extends State<AppIntro> {
  final _controller = PageController();
  int _index = 0;

  List<_IntroPage> get _pages {
    final l10n = AppLocalizations.of(context)!;
    return [
      _IntroPage(
        icon: IconsaxPlusBold.building,
        title: l10n.introSwipeTitle,
        body: l10n.introSwipeBody,
        accent: AppColors.primary,
      ),
      _IntroPage(
        icon: IconsaxPlusBold.search_normal_1,
        title: l10n.introAtiTitle,
        body: l10n.introAtiBody,
        accent: AppColors.coral,
      ),
      _IntroPage(
        icon: IconsaxPlusBold.video_octagon,
        title: l10n.introTourTitle,
        body: l10n.introTourBody,
        accent: AppColors.navy,
      ),
      _IntroPage(
        icon: IconsaxPlusBold.message,
        title: l10n.introMatchTitle,
        body: l10n.introMatchBody,
        accent: AppColors.primary,
      ),
      _IntroPage(
        icon: IconsaxPlusBold.profile_circle,
        title: l10n.introProfileTitle,
        body: l10n.introProfileBody,
        accent: AppColors.coral,
      ),
    ];
  }

  Future<void> _finish() async {
    HapticFeedback.lightImpact();
    await AppIntro.markSeen();
    if (mounted) widget.onDone();
  }

  void _next() {
    HapticFeedback.selectionClick();
    if (_index >= _pages.length - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    final isLast = _index >= pages.length - 1;

    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              // Skip
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: TextButton(
                    key: const Key('intro_skip_button'),
                    onPressed: _finish,
                    child: Text(
                      AppLocalizations.of(context)!.skip,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: pages.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) => _IntroCard(page: pages[i]),
                ),
              ),
              // Dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(pages.length, (i) {
                  final active = i == _index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 22 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.primary
                          : AppColors.primary.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    key: const Key('intro_next_button'),
                    onPressed: _next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: Text(
                      isLast
                          ? AppLocalizations.of(context)!.letsGetStarted
                          : AppLocalizations.of(context)!.next,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
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

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.page});
  final _IntroPage page;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: page.accent.withValues(alpha: 0.12),
            ),
            child: Center(
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: page.accent,
                  boxShadow: [
                    BoxShadow(
                      color: page.accent.withValues(alpha: 0.35),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(page.icon, color: Colors.white, size: 42),
              ),
            ),
          ),
          const SizedBox(height: 36),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            page.body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
