import 'dart:ui';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:dating_app/core/ui/platform_fx.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/auth_screen.dart';
import 'package:dating_app/presentation/screens/home_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:dating_app/presentation/widgets/animations/micro_animations.dart';
import 'package:dating_app/presentation/widgets/scale_bounce.dart';

/// The entry flow (onboarding/auth) is ALWAYS the source teal brand, never the
/// broker-black accent — so it uses this fixed compile-time token rather than
/// the runtime-swappable `AppColors.primary`, making it structurally immune to
/// any global accent flip that may occur while a session is being established.
Color get _kBrandTeal => AppColors.primary; // entry CTA, follows the accent

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final PageController _pageController;
  int _page = 0;

  // One focused screen — the whole product in a single coherent message instead
  // of three separate intro slides.
  List<_OnboardingSlide> _slides(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return [
      _OnboardingSlide(
        imageUrl:
            'https://images.unsplash.com/photo-1600607687939-ce8a6c25118c?auto=format&fit=crop&w=1200&q=85',
        title: l10n.onboardingHeadline,
        body: l10n.onboardingSubtitle,
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _openAuth() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, animation, __) => const AuthScreen(),
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  void _next() {
    if (_page == _slides(context).length - 1) {
      _openAuth();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final maxWidth = size.width >= 600 ? 430.0 : double.infinity;
    final slides = _slides(context);
    final slide = slides[_page];

    return Scaffold(
      backgroundColor: AppColors.border,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: _pageController,
                itemCount: slides.length,
                onPageChanged: (value) => setState(() => _page = value),
                itemBuilder: (context, index) {
                  return Image.network(
                    _slides(context)[index].imageUrl,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    errorBuilder: (_, __, ___) => const _OnboardingFallback(),
                  );
                },
              ),
              const Positioned.fill(child: _OnboardingScrim()),
              // Debug-only shortcut: skip onboarding/login straight to home so
              // the AI assistant "נועה" can be tried immediately. Never shipped
              // (kDebugMode is false in release builds).
              if (kDebugMode)
                Positioned(
                  top: 4,
                  left: 4,
                  child: SafeArea(
                    child: Material(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () async {
                          // DEBUG: sign in anonymously so the server voice + GPT
                          // endpoints (which require a Firebase JWT) actually work.
                          // Needs Anonymous auth enabled in the Firebase console.
                          try {
                            if (FirebaseAuth.instance.currentUser == null) {
                              await FirebaseAuth.instance.signInAnonymously();
                            }
                          } catch (_) {}
                          if (!context.mounted) return;
                          context.read<DatingProvider>().markEnteredApp();
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                                builder: (_) => const HomeScreen()),
                          );
                        },
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          child: Text('DEBUG → אתי',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_page > 0)
                Positioned(
                  top: 12,
                  right: 16,
                  child: SafeArea(
                    child: ScaleBounce(
                      onTap: () {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 360),
                          curve: Curves.easeOutCubic,
                        );
                      },
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.2),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.keyboard_arrow_right_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                  child: Column(
                    children: [
                      const Spacer(),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 320),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.08),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: _SlideCopy(
                          key: ValueKey(slide.title),
                          slide: slide,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (slides.length > 1) ...[
                        _PageDots(
                          count: slides.length,
                          activeIndex: _page,
                        ),
                        const SizedBox(height: 32),
                      ] else
                        const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: PlatformFx.blurSigma(18), sigmaY: PlatformFx.blurSigma(18)),
                          child: GestureDetector(
                            onTap: _next,
                            child: Container(
                              width: double.infinity,
                              height: 62,
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                              decoration: BoxDecoration(
                                color: _kBrandTeal.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: _kBrandTeal.withValues(alpha: 0.3),
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                children: [
                                  if (_page == slides.length - 1)
                                    const SizedBox(width: 56) // spacer to offset the circle on opposite side
                                  else
                                    const SizedBox(width: 24),
                                  Expanded(
                                    child: Center(
                                      child: Text(
                                        _page == slides.length - 1
                                            ? AppLocalizations.of(context)!.getStarted
                                            : AppLocalizations.of(context)!.next,
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (_page == slides.length - 1)
                                    Container(
                                      width: 50,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        color: _kBrandTeal,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.arrow_outward_rounded,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                    )
                                  else
                                    const SizedBox(width: 24),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      BreatheAnimation(
                        child: SvgPicture.asset(
                          'assets/images/rently_logo_with_text.svg',
                          height: 42,
                          colorFilter: const ColorFilter.mode(
                            Colors.white,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ],
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

class _OnboardingSlide {
  const _OnboardingSlide({
    required this.imageUrl,
    required this.title,
    required this.body,
  });

  final String imageUrl;
  final String title;
  final String body;
}

class _SlideCopy extends StatelessWidget {
  const _SlideCopy({
    super.key,
    required this.slide,
  });

  final _OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          slide.title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'SF Hebrew Rounded',
            color: Colors.white,
            fontSize: 34,
            height: 1.18,
            fontWeight: FontWeight.w900,
            shadows: [
              Shadow(
                color: Color(0x4D000000),
                blurRadius: 14,
                offset: Offset(0, 3),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          slide.body,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.84),
            fontSize: 15.5,
            height: 1.45,
            fontWeight: FontWeight.w600,
            shadows: const [
              Shadow(
                color: Color(0x22000000),
                blurRadius: 8,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OnboardingScrim extends StatelessWidget {
  const _OnboardingScrim();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.05),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.16),
              ],
              stops: const [0.0, 0.48, 1.0],
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.62,
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.0),
                    Colors.black.withValues(alpha: 0.18),
                    Colors.black.withValues(alpha: 0.52),
                    Colors.black.withValues(alpha: 0.82),
                    Colors.black.withValues(alpha: 0.94),
                  ],
                  stops: const [0.0, 0.28, 0.56, 0.82, 1.0],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.count,
    required this.activeIndex,
  });

  final int count;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final isActive = index == activeIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          width: isActive ? 34 : 7,
          height: 7,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: isActive ? 1 : 0.48),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}

class _OnboardingFallback extends StatelessWidget {
  const _OnboardingFallback();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.slate200,
            Color(0xFF7F94A8),
            AppColors.inkSoft,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.apartment_rounded,
          color: Colors.white.withValues(alpha: 0.24),
          size: 132,
        ),
      ),
    );
  }
}
