import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/services/apple_auth_service.dart';
import 'package:dating_app/core/services/google_auth_service.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onEnter() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => const HomeScreen(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  Future<void> _onGuestEnter() async {
    final role = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _GuestModeDialog(),
    );
    if (!mounted || role == null) return;
    await context.read<DatingProvider>().enterGuestMode(role);
    if (mounted) _onEnter();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 1040;

    return Scaffold(
      backgroundColor: const Color(0xFF021120),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF021120), Color(0xFF062038), Color(0xFF0C4A62)],
          ),
        ),
        child: Stack(
          children: [
            const Positioned.fill(child: _BackdropOrbs()),
            if (isWide)
              _WideLayout(
                  tabController: _tabController,
                  onLogin: _onEnter,
                  onGuestLogin: _onGuestEnter,
                  onDone: _onEnter)
            else
              _MobileLayout(
                  tabController: _tabController,
                  onLogin: _onEnter,
                  onGuestLogin: _onGuestEnter,
                  onDone: _onEnter),
          ],
        ),
      ),
    );
  }
}

// ─── Mobile Layout ────────────────────────────────────────────────────────────

class _MobileLayout extends StatelessWidget {
  const _MobileLayout({
    required this.tabController,
    required this.onLogin,
    required this.onGuestLogin,
    required this.onDone,
  });

  final TabController tabController;
  final VoidCallback onLogin;
  final VoidCallback onGuestLogin;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 24, 26, 20),
            child: const _HeroContent(),
          ),
        ),
        Expanded(
          child: _AuthCard(
            tabController: tabController,
            onLogin: onLogin,
            onGuestLogin: onGuestLogin,
            onDone: onDone,
          ),
        ),
      ],
    );
  }
}

// ─── Wide Layout ──────────────────────────────────────────────────────────────

class _WideLayout extends StatelessWidget {
  const _WideLayout({
    required this.tabController,
    required this.onLogin,
    required this.onGuestLogin,
    required this.onDone,
  });

  final TabController tabController;
  final VoidCallback onLogin;
  final VoidCallback onGuestLogin;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Row(
              children: [
                const Expanded(
                  flex: 11,
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: _HeroContentWide(),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 9,
                  child: _AuthCard(
                    tabController: tabController,
                    onLogin: onLogin,
                    onGuestLogin: onGuestLogin,
                    onDone: onDone,
                    isWide: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Hero Content (mobile) ────────────────────────────────────────────────────

class _HeroContent extends StatelessWidget {
  const _HeroContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SvgPicture.asset(
          'assets/images/rentch_logo_full.svg',
          height: 40,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          placeholderBuilder: (_) => const Text('Rentch',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1)),
        ),
        const SizedBox(height: 18),
        const Text(
          'הדרך החכמה\nלמצוא את הבית הבא שלך',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            height: 1.2,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 14),
        const _HeroStats(),
      ],
    );
  }
}

// ─── Hero Stats ───────────────────────────────────────────────────────────────

class _HeroStats extends StatelessWidget {
  const _HeroStats();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _StatItem(value: '1,200+', label: 'דירות'),
        _StatSep(),
        const _StatItem(value: '94%', label: 'שביעות רצון'),
        _StatSep(),
        const _StatItem(value: '<48h', label: 'עד מאצ׳'),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3)),
        Text(label,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.52),
                fontSize: 11,
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _StatSep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      color: Colors.white.withValues(alpha: 0.18),
    );
  }
}

// ─── Hero Content (wide) ─────────────────────────────────────────────────────

class _HeroContentWide extends StatelessWidget {
  const _HeroContentWide();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SvgPicture.asset(
          'assets/images/rentch_logo_full.svg',
          height: 56,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          placeholderBuilder: (_) => const Text('Rentch',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 28),
        const Text(
          'הדרך המהירה\nלמצוא את הבית הבא שלך.',
          style: TextStyle(
              color: Colors.white,
              fontSize: 44,
              height: 1.1,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.3),
        ),
        const SizedBox(height: 16),
        Text(
          'Rentch מחבר שוכרים ומשכירים בחוויה חכמה, מהירה וברורה.',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 17,
              height: 1.6,
              fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 32),
        const _WideFeatureList(),
      ],
    );
  }
}

class _WideFeatureList extends StatelessWidget {
  const _WideFeatureList();

  @override
  Widget build(BuildContext context) {
    return const Column(children: [
      _WideFeatureItem(
          icon: IconsaxPlusBold.building,
          title: 'גלילת דירות חכמה',
          subtitle: 'מציג רק את מה שמתאים לפרופיל שלך'),
      SizedBox(height: 14),
      _WideFeatureItem(
          icon: IconsaxPlusBold.heart,
          title: 'התאמה דו-כיוונית',
          subtitle: 'שוכרים ומשכירים מאשרים זה את זה'),
      SizedBox(height: 14),
      _WideFeatureItem(
          icon: IconsaxPlusBold.message,
          title: 'צ׳אט ישיר',
          subtitle: 'תקשורת ממוקדת בין הצדדים'),
    ]);
  }
}

class _WideFeatureItem extends StatelessWidget {
  const _WideFeatureItem(
      {required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14)),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
          Text(subtitle,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ]),
      ),
    ]);
  }
}

// ─── Auth Card ────────────────────────────────────────────────────────────────

class _AuthCard extends StatelessWidget {
  const _AuthCard({
    required this.tabController,
    required this.onLogin,
    required this.onGuestLogin,
    required this.onDone,
    this.isWide = false,
  });

  final TabController tabController;
  final VoidCallback onLogin;
  final VoidCallback onGuestLogin;
  final VoidCallback onDone;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final radius = isWide
        ? BorderRadius.circular(36)
        : const BorderRadius.vertical(top: Radius.circular(36));

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFAFCFE),
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
              color: Color(0x44021120), blurRadius: 48, offset: Offset(0, -12)),
          BoxShadow(
              color: Color(0x18021120), blurRadius: 16, offset: Offset(0, -4)),
        ],
      ),
      child: Column(
        children: [
          if (!isWide) ...[
            const SizedBox(height: 14),
            Container(
              width: 34,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(999)),
            ),
            const SizedBox(height: 16),
          ] else
            const SizedBox(height: 28),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isWide ? 28 : 20),
            child: _ModeTabs(controller: tabController),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              child: TabBarView(
                controller: tabController,
                children: [
                  _LoginTab(onLogin: onLogin, onGuestLogin: onGuestLogin),
                  _RegisterFlow(onDone: onDone),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Backdrop ─────────────────────────────────────────────────────────────────

class _BackdropOrbs extends StatelessWidget {
  const _BackdropOrbs();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(children: [
        Positioned(
            top: -140,
            right: -60,
            child: _GlowOrb(
                size: 320,
                color: AppColors.primary.withValues(alpha: 0.22))),
        Positioned(
            left: -100,
            top: 130,
            child: _GlowOrb(
                size: 250, color: Colors.white.withValues(alpha: 0.06))),
        Positioned(
            bottom: -80,
            left: 20,
            child: _GlowOrb(
                size: 280,
                color: AppColors.coral.withValues(alpha: 0.11))),
        Positioned(
            top: 52,
            right: -24,
            child: Transform.rotate(
                angle: 0.18, child: const _FloatingCardMockup())),
        Positioned(
            top: 96,
            right: 88,
            child: Transform.rotate(
                angle: -0.09,
                child: const _FloatingCardMockup(accent: true))),
      ]),
    );
  }
}

class _FloatingCardMockup extends StatelessWidget {
  const _FloatingCardMockup({this.accent = false});
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 126,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: accent
            ? AppColors.primary.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.07),
        border: Border.all(
            color: Colors.white.withValues(alpha: accent ? 0.18 : 0.09),
            width: 1),
      ),
      child: Column(children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                color: Colors.white.withValues(alpha: 0.04)),
            child: Center(
              child: Icon(
                accent ? IconsaxPlusBold.house_2 : IconsaxPlusBold.building,
                color: Colors.white.withValues(alpha: 0.20),
                size: 26,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                height: 6,
                width: double.infinity,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: Colors.white.withValues(alpha: 0.16))),
            const SizedBox(height: 4),
            Container(
                height: 5,
                width: 44,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: Colors.white.withValues(alpha: 0.09))),
            const SizedBox(height: 6),
            Row(children: [
              Container(
                  height: 16,
                  width: 40,
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      color: AppColors.primary.withValues(alpha: 0.32))),
              const Spacer(),
              Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.10))),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [
          color,
          color.withValues(alpha: color.a * 0.3),
          Colors.transparent,
        ]),
      ),
    );
  }
}

// ─── Guest Mode Dialog ────────────────────────────────────────────────────────

class _GuestModeDialog extends StatelessWidget {
  const _GuestModeDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 520),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFCFE),
          borderRadius: BorderRadius.circular(30),
          boxShadow: const [
            BoxShadow(
                color: Color(0x35072946),
                blurRadius: 36,
                offset: Offset(0, 16))
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('המשך כאורח',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: AppColors.navy)),
              const SizedBox(height: 8),
              const Text(
                'בחרו האם להיכנס כבעל דירה או כדייר שמחפש דירה.',
                style: TextStyle(
                    fontSize: 14, height: 1.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 18),
              _GuestRoleOption(
                title: 'אורח כדייר מחפש דירה',
                subtitle: 'דירות פעילות ומאצ׳ים פתוחים.',
                icon: IconsaxPlusBold.profile_circle,
                color: AppColors.primary,
                onTap: () => Navigator.of(context).pop('tenant'),
              ),
              const SizedBox(height: 12),
              _GuestRoleOption(
                title: 'אורח כבעל דירה',
                subtitle: 'נכסים פעילים ומועמדים בתהליך.',
                icon: IconsaxPlusBold.home,
                color: AppColors.navy,
                onTap: () => Navigator.of(context).pop('landlord'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuestRoleOption extends StatelessWidget {
  const _GuestRoleOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.borderLight),
          color: color.withValues(alpha: 0.06),
        ),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: AppColors.textSecondary)),
              ],
            ),
          ),
          Icon(IconsaxPlusBold.arrow_left_2, color: color, size: 16),
        ]),
      ),
    );
  }
}

// ─── Mode Tabs ────────────────────────────────────────────────────────────────

class _ModeTabs extends StatelessWidget {
  const _ModeTabs({required this.controller});
  final TabController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF2F7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: TabBar(
        controller: controller,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelPadding: EdgeInsets.zero,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryDark]),
          boxShadow: const [
            BoxShadow(
                color: Color(0x3813BEC9), blurRadius: 14, offset: Offset(0, 5))
          ],
        ),
        labelColor: Colors.white,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle:
            const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        tabs: const [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.login_rounded, size: 16),
                SizedBox(width: 6),
                Text('כניסה'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_add_alt_1_rounded, size: 16),
                SizedBox(width: 6),
                Text('הרשמה'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Login Tab ────────────────────────────────────────────────────────────────

class _LoginTab extends StatefulWidget {
  const _LoginTab({required this.onLogin, required this.onGuestLogin});
  final VoidCallback onLogin;
  final VoidCallback onGuestLogin;

  @override
  State<_LoginTab> createState() => _LoginTabState();
}

class _LoginTabState extends State<_LoginTab> {
  final _googleAuthService = GoogleAuthService();
  final _appleAuthService = AppleAuthService();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _googleLoading = false;
  bool _appleLoading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final provider = context.read<DatingProvider>();
    FocusScope.of(context).unfocus();
    if (_phoneCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('יש למלא מספר טלפון')));
      return;
    }
    setState(() => _loading = true);
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    await provider.setUserRole(provider.userRole);
    if (mounted) widget.onLogin();
  }

  Future<void> _loginWithGoogle() async {
    if (_googleLoading) return;
    if (!AppConfig.enableGoogleSignIn) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('כניסה עם Google לא מופעלת בסביבת ההרצה הזו')));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _googleLoading = true);
    try {
      final result = await _googleAuthService.signIn();
      if (!mounted) return;
      final provider = context.read<DatingProvider>();
      await provider.applyGoogleIdentity(
          displayName: result.displayName, photoUrl: result.photoUrl);
      await provider.setUserRole(provider.userRole);
      if (!mounted) return;
      widget.onLogin();
    } on GoogleAuthCanceledException {
      // no-op
    } on GoogleAuthConfigException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('הכניסה עם Google לא זמינה כרגע. נסו שוב מאוחר יותר.')));
    } catch (error) {
      if (!mounted) return;
      final msg = error.toString().toLowerCase();
      if (msg.contains('canceled') ||
          msg.contains('cancelled') ||
          msg.contains('sign_in_canceled')) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('הכניסה עם Google נכשלה. נסו שוב.')));
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _loginWithApple() async {
    if (_appleLoading) return;
    FocusScope.of(context).unfocus();
    setState(() => _appleLoading = true);
    try {
      final result = await _appleAuthService.signIn();
      if (!mounted) return;
      final provider = context.read<DatingProvider>();
      await provider.applyGoogleIdentity(
          displayName: result.displayName, photoUrl: null);
      await provider.setUserRole(provider.userRole);
      if (!mounted) return;
      widget.onLogin();
    } on AppleAuthCanceledException {
      // no-op
    } on AppleAuthUnsupportedException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('כניסה עם Apple זמינה במכשירי Apple נתמכים בלבד.')));
    } on SignInWithAppleAuthorizationException catch (e) {
      if (!mounted) return;
      if (e.code == AuthorizationErrorCode.canceled) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('הכניסה עם Apple נכשלה. נסו שוב.')));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('הכניסה עם Apple נכשלה. נסו שוב.')));
    } finally {
      if (mounted) setState(() => _appleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Compact heading
          const Text('ברוכים הבאים',
              style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3)),
          const SizedBox(height: 2),
          const Text('הכנסו עם מספר הטלפון שלכם',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 18),

          // Phone
          _AuthTextField(
            controller: _phoneCtrl,
            label: 'מספר טלפון',
            hint: '05X-XXXXXXX',
            icon: IconsaxPlusBold.call,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
          ),
          const SizedBox(height: 10),

          // Password
          _AuthTextField(
            controller: _passwordCtrl,
            label: 'סיסמה',
            icon: IconsaxPlusBold.lock,
            obscureText: _obscure,
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                color: AppColors.textSecondary,
                size: 18,
              ),
            ),
          ),

          // Forgot
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () {},
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('שכחתי סיסמה',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 14),

          // Login CTA
          SizedBox(
            height: 54,
            child: FilledButton(
              onPressed: _loading ? null : _login,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white))
                  : const Text('כניסה לחשבון',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 10),

          // Guest — text link, not a button
          Center(
            child: TextButton(
              onPressed: widget.onGuestLogin,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(IconsaxPlusBold.eye, size: 14),
                  const SizedBox(width: 5),
                  Text('המשך כאורח',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary
                              .withValues(alpha: 0.85))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Divider
          Row(children: [
            const Expanded(child: Divider(color: AppColors.borderLight)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('או',
                  style: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.65),
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
            const Expanded(child: Divider(color: AppColors.borderLight)),
          ]),
          const SizedBox(height: 10),

          // Social — side by side in one row
          FutureBuilder<bool>(
            future: AppleAuthService.isAvailable,
            builder: (context, snapshot) {
              final showApple = snapshot.data == true;
              final showGoogle = AppConfig.enableGoogleSignIn;
              if (!showGoogle && !showApple) return const SizedBox.shrink();

              return Row(children: [
                if (showGoogle)
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: OutlinedButton(
                        onPressed: _googleLoading ? null : _loginWithGoogle,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.navy,
                          backgroundColor: Colors.white,
                          side:
                              const BorderSide(color: AppColors.borderLight),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          padding: EdgeInsets.zero,
                        ),
                        child: _googleLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppColors.navy))
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                        borderRadius:
                                            BorderRadius.circular(4),
                                        color: const Color(0xFFF1F1F1)),
                                    child: const Center(
                                      child: Text('G',
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w900,
                                              color: Color(0xFF4285F4))),
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  const Text('Google',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800)),
                                ],
                              ),
                      ),
                    ),
                  ),
                if (showGoogle && showApple) const SizedBox(width: 10),
                if (showApple)
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed:
                            _appleLoading ? null : _loginWithApple,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          padding: EdgeInsets.zero,
                        ),
                        child: _appleLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.apple_rounded, size: 18),
                                  SizedBox(width: 6),
                                  Text('Apple',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800)),
                                ],
                              ),
                      ),
                    ),
                  ),
              ]);
            },
          ),
        ],
      ),
    );
  }
}

// ─── Register Flow ────────────────────────────────────────────────────────────

class _RegisterFlow extends StatefulWidget {
  const _RegisterFlow({required this.onDone});
  final VoidCallback onDone;

  @override
  State<_RegisterFlow> createState() => _RegisterFlowState();
}

class _RegisterFlowState extends State<_RegisterFlow> {
  final _pageCtrl = PageController();
  int _step = 0;
  String _role = '';
  final _nameCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  int _budget = 7000;
  double _propRooms = 3;
  final List<String> _propFeatures = [];
  bool _loading = false;

  int get _totalSteps => _role == 'landlord' ? 3 : 2;

  @override
  void dispose() {
    _pageCtrl.dispose();
    _nameCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_step == 0 && _role.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('יש לבחור תפקיד')));
      return;
    }
    if (_step == 1 && _nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('יש להזין שם')));
      return;
    }
    if (_step >= _totalSteps - 1) {
      _submit();
    } else {
      setState(() => _step++);
      _pageCtrl.nextPage(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic);
    }
  }

  void _prev() {
    if (_step == 0) return;
    setState(() => _step--);
    _pageCtrl.previousPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    final provider = context.read<DatingProvider>();
    final name = _nameCtrl.text.trim();
    final current = provider.tenantProfile;
    await provider.updateTenantProfile(
      (current ??
              const TenantProfile(
                  id: 'user-1',
                  name: '',
                  bio: '',
                  photoUrls: [],
                  budgetMax: 9000,
                  desiredRooms: 2,
                  moveInWindow: 'גמיש',
                  importantDetails: []))
          .copyWith(
        name: name,
        budgetMax: _budget,
        desiredRooms: 2,
        moveInWindow: 'גמיש',
      ),
    );
    await provider.setUserRole(_role);
    final city = _cityCtrl.text.trim();
    if (_role == 'landlord' && city.isNotEmpty) {
      await provider.addLandlordProperty(RentalProperty(
        id: 'prop-${DateTime.now().millisecondsSinceEpoch}',
        url: '',
        price: 0,
        rooms: _propRooms,
        sizeM2: 0,
        floor: '0',
        totalFloors: '0',
        city: city,
        neighborhood: '',
        street: '',
        streetNumber: 0,
        lat: 32.0853,
        lon: 34.7818,
        propertyType: 'דירה',
        entryDate: 'גמיש',
        condition: 'טוב',
        ownerName: name,
        agencyListing: false,
        features: List.unmodifiable(_propFeatures),
        media: const [],
      ));
    }
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) widget.onDone();
  }

  String get _nextLabel {
    if (_step >= _totalSteps - 1) return 'בואו נתחיל';
    return 'הבא';
  }

  @override
  Widget build(BuildContext context) {
    final isOptionalStep = _role == 'landlord' && _step == 2;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          child: _StepProgress(step: _step, total: _totalSteps),
        ),
        Expanded(
          child: PageView(
            controller: _pageCtrl,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _StepRole(
                selected: _role,
                onSelect: (role) => setState(() => _role = role),
              ),
              _StepPersonal(
                nameCtrl: _nameCtrl,
                role: _role,
                budget: _budget,
                onBudget: (v) =>
                    setState(() => _budget = (v / 100).round() * 100),
              ),
              if (_role == 'landlord')
                _StepPropertyDetails(
                  cityCtrl: _cityCtrl,
                  rooms: _propRooms,
                  features: _propFeatures,
                  onRooms: (v) => setState(() => _propRooms = v),
                  onToggleFeature: (f) => setState(() =>
                      _propFeatures.contains(f)
                          ? _propFeatures.remove(f)
                          : _propFeatures.add(f)),
                ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
              20, 4, 20, 14 + MediaQuery.of(context).padding.bottom),
          child: _NavButtons(
            nextLabel: _nextLabel,
            loading: _loading,
            onPrev: _step > 0 ? _prev : null,
            onNext: _next,
            onSkip: isOptionalStep ? _submit : null,
          ),
        ),
      ],
    );
  }
}

// ─── Step Progress ────────────────────────────────────────────────────────────

class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.step, required this.total});
  final int step;
  final int total;

  static const _labels = ['תפקיד', 'פרטים', 'נכס'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < total; i++) ...[
          _StepBubble(index: i, current: step, label: _labels[i]),
          if (i < total - 1)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  height: 2,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(1),
                    color: i < step ? AppColors.primary : AppColors.borderLight,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _StepBubble extends StatelessWidget {
  const _StepBubble(
      {required this.index, required this.current, required this.label});
  final int index;
  final int current;
  final String label;

  @override
  Widget build(BuildContext context) {
    final isDone = index < current;
    final isActive = index == current;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDone || isActive ? AppColors.primary : Colors.transparent,
            border: Border.all(
              color: isDone || isActive
                  ? AppColors.primary
                  : AppColors.borderLight,
              width: 1.5,
            ),
            boxShadow: isDone || isActive
                ? [
                    BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.26),
                        blurRadius: 8,
                        offset: const Offset(0, 3))
                  ]
                : [],
          ),
          child: Center(
            child: isDone
                ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                : Text('${index + 1}',
                    style: TextStyle(
                        color:
                            isActive ? Colors.white : AppColors.textDisabled,
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(height: 3),
        Text(label,
            style: TextStyle(
                color: isActive ? AppColors.primary : AppColors.textDisabled,
                fontSize: 10,
                fontWeight: FontWeight.w700)),
      ],
    );
  }
}

// ─── Step: Role ───────────────────────────────────────────────────────────────

class _StepRole extends StatelessWidget {
  const _StepRole({required this.selected, required this.onSelect});
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('מה מביא אותך לכאן?',
              style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3)),
          const SizedBox(height: 3),
          const Text('בחרו מסלול כדי שנוכל להתאים את החוויה',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 20),
          _RoleCard(
            icon: IconsaxPlusBold.house_2,
            title: 'אני מחפש/ת דירה',
            subtitle: 'שוכר / שוכרת',
            accent: AppColors.primary,
            selected: selected == 'tenant',
            onTap: () => onSelect('tenant'),
          ),
          const SizedBox(height: 12),
          _RoleCard(
            icon: IconsaxPlusBold.building,
            title: 'יש לי דירה להשכרה',
            subtitle: 'משכיר / משכירה',
            accent: AppColors.navy,
            selected: selected == 'landlord',
            onTap: () => onSelect('landlord'),
          ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: selected ? accent : Colors.white,
          border: Border.all(
            color: selected ? accent : AppColors.borderLight,
            width: selected ? 0 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? accent.withValues(alpha: 0.24)
                  : AppColors.shadow,
              blurRadius: selected ? 20 : 8,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.18)
                    : accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon,
                  color: selected ? Colors.white : accent, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: selected ? Colors.white : AppColors.navy,
                          fontSize: 16,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: TextStyle(
                          color: selected
                              ? Colors.white.withValues(alpha: 0.72)
                              : AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white
                    : AppColors.borderLight.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(
                  selected ? Icons.check_rounded : Icons.circle_outlined,
                  size: 14,
                  color: selected ? accent : AppColors.textDisabled),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Step: Personal ───────────────────────────────────────────────────────────

class _StepPersonal extends StatelessWidget {
  const _StepPersonal({
    required this.nameCtrl,
    required this.role,
    required this.budget,
    required this.onBudget,
  });

  final TextEditingController nameCtrl;
  final String role;
  final int budget;
  final ValueChanged<double> onBudget;

  @override
  Widget build(BuildContext context) {
    final isTenant = role == 'tenant';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('ספרו לנו קצת עליכם',
              style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3)),
          const SizedBox(height: 3),
          Text(
              isTenant
                  ? 'בעלי הדירות יוכלו להכיר אתכם'
                  : 'הפרטים יופיעו על הנכסים שלכם',
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 22),
          _AuthTextField(
            controller: nameCtrl,
            label: 'שם מלא',
            icon: IconsaxPlusBold.user,
            textCapitalization: TextCapitalization.words,
          ),
          if (isTenant) ...[
            const SizedBox(height: 16),
            _CompactBudgetPicker(budget: budget, onBudget: onBudget),
          ],
        ],
      ),
    );
  }
}

// ─── Compact Budget Picker ────────────────────────────────────────────────────

class _CompactBudgetPicker extends StatelessWidget {
  const _CompactBudgetPicker(
      {required this.budget, required this.onBudget});
  final int budget;
  final ValueChanged<double> onBudget;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 8, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          Row(children: [
            const Text('תקציב חודשי',
                style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('₪${_fmt(budget)}',
                style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3)),
          ]),
          const SizedBox(height: 6),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 9),
              overlayShape:
                  const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: const Color(0xFFD0EDF0),
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withValues(alpha: 0.16),
            ),
            child: Slider(
              value: budget.toDouble().clamp(2000, 20000),
              min: 2000,
              max: 20000,
              divisions: 180,
              onChanged: onBudget,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Nav Buttons ─────────────────────────────────────────────────────────────

class _NavButtons extends StatelessWidget {
  const _NavButtons({
    required this.nextLabel,
    required this.loading,
    required this.onPrev,
    required this.onNext,
    this.onSkip,
  });

  final String nextLabel;
  final bool loading;
  final VoidCallback? onPrev;
  final VoidCallback onNext;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (onPrev != null) ...[
              SizedBox(
                height: 52,
                width: 52,
                child: OutlinedButton(
                  onPressed: onPrev,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.navy,
                    side: const BorderSide(color: AppColors.borderLight),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15)),
                  ),
                  child: const Icon(Icons.arrow_forward_ios_rounded, size: 17),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: loading ? null : onNext,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15)),
                  ),
                  icon: loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.3, color: Colors.white))
                      : const Icon(Icons.arrow_back_ios_rounded, size: 15),
                  label: Text(nextLabel,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ],
        ),
        if (onSkip != null) ...[
          const SizedBox(height: 6),
          TextButton(
            onPressed: onSkip,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text('דלג על שלב זה',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary.withValues(alpha: 0.75))),
          ),
        ],
      ],
    );
  }
}

// ─── Auth TextField ───────────────────────────────────────────────────────────

class _AuthTextField extends StatelessWidget {
  const _AuthTextField({
    required this.label,
    required this.icon,
    this.controller,
    this.hint,
    this.keyboardType,
    this.textDirection,
    this.obscureText = false,
    this.suffixIcon,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController? controller;
  final String label;
  final String? hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextDirection? textDirection;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.borderLight),
    );

    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textDirection: textDirection,
      obscureText: obscureText,
      textCapitalization: textCapitalization,
      style: const TextStyle(
          color: AppColors.navy, fontSize: 15, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white,
        labelStyle: const TextStyle(
            color: AppColors.textSecondary, fontWeight: FontWeight.w600),
        hintStyle: TextStyle(
            color: AppColors.textSecondary.withValues(alpha: 0.7),
            fontWeight: FontWeight.w500),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 54, minHeight: 52),
        prefixIcon: Padding(
          padding: const EdgeInsets.all(9),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, color: AppColors.primary, size: 16),
          ),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
        ),
      ),
    );
  }
}

// ─── Step: Property Details (optional, landlord only) ────────────────────────

class _StepPropertyDetails extends StatelessWidget {
  const _StepPropertyDetails({
    required this.cityCtrl,
    required this.rooms,
    required this.features,
    required this.onRooms,
    required this.onToggleFeature,
  });

  final TextEditingController cityCtrl;
  final double rooms;
  final List<String> features;
  final ValueChanged<double> onRooms;
  final ValueChanged<String> onToggleFeature;

  static const _featureTags = [
    'מרפסת', 'חניה', 'מעלית', 'מיזוג',
    'ממ"ד',  'מחסן', 'גינה',  'ריהוט',
    'מחמדים', 'אינטרנט',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header + optional badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text('פרטי הנכס',
                  style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3)),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text('אופציונלי',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 3),
          const Text('ניתן לעדכן פרטים נוספים מתוך לוח הבקרה',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 16),

          // City field
          _AuthTextField(
            controller: cityCtrl,
            label: 'עיר / שכונה',
            icon: IconsaxPlusBold.location,
          ),
          const SizedBox(height: 12),

          // Rooms stepper
          _RoomsStepper(rooms: rooms, onRooms: onRooms),
          const SizedBox(height: 14),

          // Features label
          const Text('מה יש בנכס?',
              style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 14,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 9),

          // Feature chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _featureTags
                .map((f) => _FeatureChip(
                      label: f,
                      selected: features.contains(f),
                      onTap: () => onToggleFeature(f),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ─── Rooms Stepper ────────────────────────────────────────────────────────────

class _RoomsStepper extends StatelessWidget {
  const _RoomsStepper({required this.rooms, required this.onRooms});
  final double rooms;
  final ValueChanged<double> onRooms;

  @override
  Widget build(BuildContext context) {
    final label = rooms % 1 == 0 ? rooms.toInt().toString() : '$rooms';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 8, offset: Offset(0, 2))
        ],
      ),
      child: Row(children: [
        const Text('מספר חדרים',
            style: TextStyle(
                color: AppColors.navy,
                fontSize: 14,
                fontWeight: FontWeight.w700)),
        const Spacer(),
        _StepperBtn(
          icon: Icons.remove_rounded,
          onTap: () => onRooms((rooms - 0.5).clamp(1.0, 8.0)),
          filled: false,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(label,
              style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5)),
        ),
        _StepperBtn(
          icon: Icons.add_rounded,
          onTap: () => onRooms((rooms + 0.5).clamp(1.0, 8.0)),
          filled: true,
        ),
      ]),
    );
  }
}

class _StepperBtn extends StatelessWidget {
  const _StepperBtn(
      {required this.icon, required this.onTap, required this.filled});
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled
              ? AppColors.primary
              : AppColors.borderLight.withValues(alpha: 0.6),
        ),
        child: Icon(icon,
            size: 16,
            color: filled ? Colors.white : AppColors.textSecondary),
      ),
    );
  }
}

// ─── Feature Chip ─────────────────────────────────────────────────────────────

class _FeatureChip extends StatelessWidget {
  const _FeatureChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding:
            const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected ? AppColors.primary : Colors.white,
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.borderLight),
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.22),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check_rounded, size: 12, color: Colors.white),
              const SizedBox(width: 5),
            ],
            Text(label,
                style: TextStyle(
                    color: selected ? Colors.white : AppColors.navy,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

// ─── Utility ──────────────────────────────────────────────────────────────────

String _fmt(int value) {
  final raw = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final remaining = raw.length - i;
    buffer.write(raw[i]);
    if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
  }
  return buffer.toString();
}
