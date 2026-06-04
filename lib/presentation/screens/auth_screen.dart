import 'dart:ui';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/services/apple_auth_service.dart';
import 'package:dating_app/core/services/google_auth_service.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/data/repositories/property_repository.dart';
import 'package:dating_app/presentation/screens/home_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────

const _kScreenBg = Color(0xFFF0F4F7);
const _kCardBg = Colors.white;
const _kInputBorder = Color(0xFFDDE3EE);
const _kInputFill = Color(0xFFF7F9FC);
const _kPillBtn = AppColors.navy;

// ─── Auth Screen ──────────────────────────────────────────────────────────────

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
      backgroundColor: _kScreenBg,
      body: isWide
          ? _WideLayout(
              tabController: _tabController,
              onLogin: _onEnter,
              onGuestLogin: _onGuestEnter,
              onDone: _onEnter)
          : _MobileLayout(
              tabController: _tabController,
              onLogin: _onEnter,
              onGuestLogin: _onGuestEnter,
              onDone: _onEnter),
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
    return Container(
      color: Colors.white,
      child: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: TabBarView(
            controller: tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _LoginTab(
                onLogin: onLogin,
                onGuestLogin: onGuestLogin,
                onSwitchToRegister: () => tabController.animateTo(1),
              ),
              _RegisterFlow(
                onDone: onDone,
                onSwitchToLogin: () => tabController.animateTo(0),
              ),
            ],
          ),
        ),
      ),
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
                Expanded(
                  flex: 11,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _WideHero(),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 9,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _kCardBg,
                      borderRadius: BorderRadius.circular(36),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x22072946),
                            blurRadius: 40,
                            offset: Offset(0, 12)),
                      ],
                    ),
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      children: [
                        _SimpleTabBar(controller: tabController),
                        const SizedBox(height: 8),
                        Expanded(
                          child: TabBarView(
                            controller: tabController,
                            children: [
                              _LoginTab(
                                  onLogin: onLogin,
                                  onGuestLogin: onGuestLogin,
                                  onSwitchToRegister: () =>
                                      tabController.animateTo(1)),
                              _RegisterFlow(
                                  onDone: onDone,
                                  onSwitchToLogin: () =>
                                      tabController.animateTo(0)),
                            ],
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
      ),
    );
  }
}

// ─── Logo Header for Mobile ──────────────────────────────────────────────────

class _LogoHeader extends StatelessWidget {
  const _LogoHeader({this.showBackButton = false, this.onBack});
  final bool showBackButton;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 36, bottom: 20),
      child: SizedBox(
        width: double.infinity,
        height: 60,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (showBackButton)
              Positioned(
                right: 0,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: _kInputBorder),
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 20, color: AppColors.navy),
                    onPressed: onBack,
                  ),
                ),
              ),
            SvgPicture.asset(
              'assets/images/rentch_logo_with_text.svg',
              height: 44,
              colorFilter:
                  const ColorFilter.mode(AppColors.navy, BlendMode.srcIn),
              placeholderBuilder: (_) => const Text('Rentch',
                  style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Wide Hero ────────────────────────────────────────────────────────────────

class _WideHero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SvgPicture.asset(
          'assets/images/rentch_logo_with_text.svg',
          height: 48,
          colorFilter:
              const ColorFilter.mode(AppColors.navy, BlendMode.srcIn),
          placeholderBuilder: (_) => const Text('Rentch',
              style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 38,
                  fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 24),
        const Text(
          'הדרך המהירה\nלמצוא את הבית הבא שלך.',
          style: TextStyle(
              color: AppColors.navy,
              fontSize: 40,
              height: 1.15,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.2),
        ),
        const SizedBox(height: 14),
        Text(
          'Rentch מחבר שוכרים ומשכירים בחוויה חכמה, מהירה וברורה.',
          style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
              height: 1.6,
              fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 28),
        _WideFeatureList(),
      ],
    );
  }
}

class _WideFeatureList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(children: const [
      _WideFeatureItem(
          icon: IconsaxPlusBold.building,
          title: 'גלילת דירות חכמה',
          subtitle: 'מציג רק את מה שמתאים לפרופיל שלך'),
      SizedBox(height: 12),
      _WideFeatureItem(
          icon: IconsaxPlusBold.heart,
          title: 'התאמה דו-כיוונית',
          subtitle: 'שוכרים ומשכירים מאשרים זה את זה'),
      SizedBox(height: 12),
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
        width: 44,
        height: 44,
        decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14)),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 14,
                  fontWeight: FontWeight.w800)),
          Text(subtitle,
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ]),
      ),
    ]);
  }
}

// ─── Simple Tab Bar ───────────────────────────────────────────────────────────

class _SimpleTabBar extends StatelessWidget {
  const _SimpleTabBar({required this.controller});
  final TabController controller;

  @override
  Widget build(BuildContext context) {
    return TabBar(
      controller: controller,
      indicatorColor: AppColors.primary,
      indicatorWeight: 2.5,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: _kInputBorder,
      labelColor: AppColors.navy,
      unselectedLabelColor: AppColors.textSecondary,
      labelStyle:
          const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      unselectedLabelStyle:
          const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      tabs: const [
        Tab(text: 'כניסה'),
        Tab(text: 'הרשמה'),
      ],
    );
  }
}

// ─── Social Sign-in Row ───────────────────────────────────────────────────────

class _SocialRow extends StatelessWidget {
  const _SocialRow({
    required this.googleLoading,
    required this.appleLoading,
    required this.onGoogle,
    required this.onApple,
  });

  final bool googleLoading;
  final bool appleLoading;
  final VoidCallback onGoogle;
  final VoidCallback onApple;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AppleAuthService.isAvailable,
      builder: (context, snapshot) {
        final showApple = snapshot.data == true;
        final showGoogle = AppConfig.enableGoogleSignIn;
        if (!showGoogle && !showApple) return const SizedBox.shrink();

        return Row(children: [
          if (showGoogle)
            Expanded(
              child: _SocialBtn(
                loading: googleLoading,
                onTap: onGoogle,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                          color: const Color(0xFFF1F3F4),
                          borderRadius: BorderRadius.circular(4)),
                      child: const Center(
                        child: Text('G',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF4285F4))),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('Google',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy)),
                  ],
                ),
              ),
            ),
          if (showGoogle && showApple) const SizedBox(width: 10),
          if (showApple)
            Expanded(
              child: _SocialBtn(
                loading: appleLoading,
                onTap: onApple,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.apple_rounded, size: 20, color: AppColors.navy),
                    SizedBox(width: 6),
                    Text('Apple',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy)),
                  ],
                ),
              ),
            ),
        ]);
      },
    );
  }
}

class _SocialBtn extends StatelessWidget {
  const _SocialBtn(
      {required this.loading, required this.onTap, required this.child});
  final bool loading;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kInputBorder, width: 1.5),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0A072946),
                blurRadius: 8,
                offset: Offset(0, 2))
          ],
        ),
        child: loading
            ? const Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.navy)))
            : child,
      ),
    );
  }
}

// ─── OR Divider ───────────────────────────────────────────────────────────────

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      const Expanded(child: Divider(color: _kInputBorder)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Text('או',
            style: TextStyle(
                color: AppColors.textSecondary.withValues(alpha: 0.7),
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ),
      const Expanded(child: Divider(color: _kInputBorder)),
    ]);
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
          color: _kCardBg,
          borderRadius: BorderRadius.circular(30),
          boxShadow: const [
            BoxShadow(
                color: Color(0x35072946), blurRadius: 36, offset: Offset(0, 16))
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
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: '$title. $subtitle',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _kInputBorder),
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
      ),
    );
  }
}

// ─── Login Tab ────────────────────────────────────────────────────────────────

class _LoginTab extends StatefulWidget {
  const _LoginTab({
    required this.onLogin,
    required this.onGuestLogin,
    required this.onSwitchToRegister,
  });
  final VoidCallback onLogin;
  final VoidCallback onGuestLogin;
  final VoidCallback onSwitchToRegister;

  @override
  State<_LoginTab> createState() => _LoginTabState();
}

class _LoginTabState extends State<_LoginTab> {
  final _googleAuthService = GoogleAuthService();
  final _appleAuthService = AppleAuthService();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _googleLoading = false;
  bool _appleLoading = false;
  bool _obscure = true;
  bool _rememberMe = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('יש למלא אימייל וסיסמה')));
      return;
    }
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);
      if (!mounted) return;
      final provider = context.read<DatingProvider>();
      await provider.setUserRole(provider.userRole);
      if (mounted) widget.onLogin();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final msg = switch (e.code) {
        'user-not-found' ||
        'wrong-password' ||
        'invalid-credential' =>
          'אימייל או סיסמה שגויים',
        'user-disabled' => 'החשבון מושבת',
        'too-many-requests' => 'יותר מדי ניסיונות, נסה שוב מאוחר יותר',
        _ => 'שגיאה בכניסה, נסה שוב',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
          msg.contains('sign_in_canceled')) {
        return;
      }
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
      // user dismissed — no-op
    } on AppleAuthUnsupportedException {
      if (!mounted) return;
      _showAppleError('כניסה עם Apple זמינה במכשירי Apple בלבד.');
    } on SignInWithAppleAuthorizationException catch (e) {
      if (!mounted) return;
      if (e.code == AuthorizationErrorCode.canceled) return;
      _showAppleError('הכניסה עם Apple נכשלה (${e.code.name}). נסו שוב.');
    } catch (e) {
      if (!mounted) return;
      _showAppleError('הכניסה עם Apple נכשלה. נסו שוב.');
    } finally {
      if (mounted) setState(() => _appleLoading = false);
    }
  }

  void _showAppleError(String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'כניסה עם Apple',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
        ),
        content: Text(message,
            style: const TextStyle(color: Color(0xFF475569), height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('סגור', style: TextStyle(color: Color(0xFF64748B))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              widget.onGuestLogin();
            },
            child: const Text('כניסה כאורח'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo header at top of scroll view
          const _LogoHeader(),
          const SizedBox(height: 16),

          // Title
          const Text(
            'ברוכים השבים',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.navy,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5),
          ),
          const SizedBox(height: 8),
          const Text(
            'התחברו עם כתובת האימייל והסיסמה שלכם כדי לגשת לחשבון.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 24),

          // Social buttons
          _SocialRow(
            googleLoading: _googleLoading,
            appleLoading: _appleLoading,
            onGoogle: _loginWithGoogle,
            onApple: _loginWithApple,
          ),
          const SizedBox(height: 20),

          // OR divider
          const _OrDivider(),
          const SizedBox(height: 20),

          // Email
          const _FieldLabel(label: 'כתובת אימייל'),
          const SizedBox(height: 6),
          _CleanTextField(
            controller: _emailCtrl,
            hint: 'name@example.com',
            keyboardType: TextInputType.emailAddress,
            textDirection: TextDirection.ltr,
          ),
          const SizedBox(height: 16),

          // Password
          const _FieldLabel(label: 'סיסמה'),
          const SizedBox(height: 6),
          _CleanTextField(
            controller: _passwordCtrl,
            obscureText: _obscure,
            hint: '••••••••',
            suffixIcon: GestureDetector(
              onTap: () => setState(() => _obscure = !_obscure),
              child: Icon(
                _obscure
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                color: AppColors.textSecondary,
                size: 20,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Remember me & Forgot Password
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _rememberMe = !_rememberMe),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        color: _rememberMe ? AppColors.primary : Colors.white,
                        border: Border.all(
                          color: _rememberMe
                              ? AppColors.primary
                              : _kInputBorder,
                          width: 1.5,
                        ),
                      ),
                      child: _rememberMe
                          ? const Icon(Icons.check_rounded,
                              size: 12, color: Colors.white)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'זכור אותי',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              TextButton(
                onPressed: () {},
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'שכחת סיסמה?',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Login CTA — black pill
          _PillButton(
            label: 'התחברות',
            loading: _loading,
            onTap: _login,
          ),
          const SizedBox(height: 16),

          // Guest / Anonymous entry
          Center(
            child: TextButton(
              onPressed: widget.onGuestLogin,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(IconsaxPlusBold.eye, size: 14),
                  const SizedBox(width: 6),
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
          const SizedBox(height: 12),

          // Switch to register
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('אין לך חשבון? ',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
                GestureDetector(
                  onTap: widget.onSwitchToRegister,
                  child: const Text('הרשמה',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Register Flow ────────────────────────────────────────────────────────────

class _RegisterFlow extends StatefulWidget {
  const _RegisterFlow({required this.onDone, required this.onSwitchToLogin});
  final VoidCallback onDone;
  final VoidCallback onSwitchToLogin;

  @override
  State<_RegisterFlow> createState() => _RegisterFlowState();
}

class _RegisterFlowState extends State<_RegisterFlow> {
  final _pageCtrl = PageController();
  int _step = 0;
  String _role = '';
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _passwordObscure = true;
  bool _agreedToTerms = false;
  final _nameCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  int _budget = 7000;
  double _propRooms = 3;
  final List<String> _propFeatures = [];
  bool _loading = false;
  bool _googleLoading = false;
  bool _appleLoading = false;

  final _googleAuthService = GoogleAuthService();
  final _appleAuthService = AppleAuthService();

  int get _totalSteps => 3;

  @override
  void dispose() {
    _pageCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_step == 0) {
      final name = _nameCtrl.text.trim();
      final email = _emailCtrl.text.trim();
      final password = _passwordCtrl.text;
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('יש להזין שם מלא')));
        return;
      }
      if (email.isEmpty || !email.contains('@')) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('יש להזין כתובת אימייל תקינה')));
        return;
      }
      if (password.length < 6) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('הסיסמה חייבת להכיל לפחות 6 תווים')));
        return;
      }
      if (!_agreedToTerms) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('יש לאשר את תנאי השימוש ומדיניות הפרטיות')));
        return;
      }
    }
    if (_step == 1 && _role.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('יש לבחור תפקיד')));
      return;
    }
    if (_step >= _totalSteps - 1) {
      final agreed = await _showEulaDialog();
      if (agreed) _submit();
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

  Future<void> _loginWithGoogle() async {
    if (_googleLoading) return;
    if (!AppConfig.enableGoogleSignIn) return;
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
      widget.onDone();
    } on GoogleAuthCanceledException {
      // no-op
    } catch (_) {
      if (!mounted) return;
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
      widget.onDone();
    } on AppleAuthCanceledException {
      // no-op
    } catch (_) {
      if (!mounted) return;
    } finally {
      if (mounted) setState(() => _appleLoading = false);
    }
  }

  Future<bool> _showEulaDialog() async {
    final agreed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (ctx, anim1, anim2) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic)),
              child: Material(
                color: Colors.transparent,
                child: _EulaSheet(
                  onAccept: () => Navigator.pop(ctx, true),
                  onDecline: () => Navigator.pop(ctx, false),
                ),
              ),
            ),
          ),
        );
      },
    );
    return agreed ?? false;
  }
}

// ─── Eula Sheet ───────────────────────────────────────────────────────────────

class _EulaSheet extends StatelessWidget {
  const _EulaSheet({required this.onAccept, required this.onDecline});
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _DomeClipper(),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(24, 60, 24, 28 + MediaQuery.of(context).padding.bottom),
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 30,
              offset: Offset(0, -10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title
            const Text(
              'תנאי השימוש ב-Rentch',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            // Scrollable terms content
            SizedBox(
              height: 200,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'ברוך הבא ל-Rentch!\nבשימוש באפליקציה אתה מסכים לתנאים הבאים:',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                    SizedBox(height: 12),
                    _EulaSection(
                      title: '1. תוכן הולם',
                      body: 'אין לפרסם תוכן פוגעני, גזעני, מיני, מאיים או כל תוכן שפוגע בזכויות אחרים.',
                    ),
                    _EulaSection(
                      title: '2. ללא אלימות ואיום',
                      body: 'כל צורה של הטרדה, איום, בריונות או התנהגות פוגענית אסורה לחלוטין.',
                    ),
                    _EulaSection(
                      title: '3. דיווח תוכן',
                      body: 'משתמשים יכולים לדווח על תוכן שפוגע בהנחיות. נטפל בכל דיווח תוך 24 שעות.',
                    ),
                    _EulaSection(
                      title: '4. חסימת משתמשים',
                      body: 'ניתן לחסום כל משתמש שמתנהג בצורה לא הולמת.',
                    ),
                    _EulaSection(
                      title: '5. פרטיות',
                      body: 'אנו מכבדים את פרטיותך. המידע ישמש לצורך התאמת נכסים בלבד.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDecline,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: const Text(
                      'ביטול',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: onAccept,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: const Text(
                      'אני מסכים/ה',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      final credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      final uid = credential.user?.uid ??
          'user-${DateTime.now().millisecondsSinceEpoch}';

      if (!mounted) return;
      final provider = context.read<DatingProvider>();
      final name = _nameCtrl.text.trim();
      final current = provider.tenantProfile;
      await provider.updateTenantProfile(
        (current ??
                TenantProfile(
                    id: uid,
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
        // Registration creates a draft skeleton — no consent required for drafts.
        // The landlord completes the listing (and accepts terms) in AddPropertyScreen.
        await provider.addLandlordProperty(
          RentalProperty(
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
          ),
          status: PropertyRecordStatus.draft,
        );
      }
      if (mounted) {
        _showSuccessSheet();
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final msg = switch (e.code) {
        'email-already-in-use' => 'כתובת האימייל כבר קיימת במערכת',
        'weak-password' => 'הסיסמה חלשה מדי',
        'invalid-email' => 'כתובת אימייל לא תקינה',
        _ => 'שגיאה ביצירת החשבון, נסה שוב',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSuccessSheet() {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 450),
      pageBuilder: (ctx, anim1, anim2) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic)),
              child: Material(
                color: Colors.transparent,
                child: _AnimatedSuccessSheet(onContinue: widget.onDone),
              ),
            ),
          ),
        );
      },
    );
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
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _LogoHeader(
            showBackButton: true,
            onBack: _step > 0 ? _prev : widget.onSwitchToLogin,
          ),
        ),
        if (_step > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
            child: _StepProgress(step: _step, total: _totalSteps),
          ),
        Expanded(
          child: PageView(
            controller: _pageCtrl,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _StepEmailPassword(
                nameCtrl: _nameCtrl,
                emailCtrl: _emailCtrl,
                passwordCtrl: _passwordCtrl,
                obscure: _passwordObscure,
                agreedToTerms: _agreedToTerms,
                onToggleObscure: () =>
                    setState(() => _passwordObscure = !_passwordObscure),
                onToggleTerms: () =>
                    setState(() => _agreedToTerms = !_agreedToTerms),
                googleLoading: _googleLoading,
                appleLoading: _appleLoading,
                onGoogle: _loginWithGoogle,
                onApple: _loginWithApple,
                onSwitchToLogin: widget.onSwitchToLogin,
              ),
              _StepRole(
                selected: _role,
                onSelect: (role) => setState(() => _role = role),
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
                )
              else
                _StepPersonal(
                  nameCtrl: _nameCtrl,
                  role: _role,
                  budget: _budget,
                  onBudget: (v) =>
                      setState(() => _budget = (v / 100).round() * 100),
                ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
              22, 4, 22, 14 + MediaQuery.of(context).padding.bottom),
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

// ─── Success Sheet ────────────────────────────────────────────────────────────

class _DomeClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, 48)
      ..quadraticBezierTo(size.width / 2, 0, size.width, 48)
      ..lineTo(size.width, size.height)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _AnimatedSuccessSheet extends StatefulWidget {
  const _AnimatedSuccessSheet({required this.onContinue});
  final VoidCallback onContinue;

  @override
  State<_AnimatedSuccessSheet> createState() => _AnimatedSuccessSheetState();
}

class _AnimatedSuccessSheetState extends State<_AnimatedSuccessSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack),
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 1.0, curve: Curves.easeIn),
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _DomeClipper(),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(24, 60, 24, 28 + MediaQuery.of(context).padding.bottom),
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 30,
              offset: Offset(0, -10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _scaleAnimation,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  for (final angle in [0.0, 0.6, 1.2, 1.8, 2.4, 3.0, 3.6, 4.2, 4.8, 5.4])
                    Transform.translate(
                      offset: Offset(
                          68 * (0.5 - (angle * 1.618 % 1.0)),
                          68 * (0.5 - (angle * 2.414 % 1.0))),
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: [
                            AppColors.primary,
                            AppColors.coral,
                            const Color(0xFFF39C12),
                            const Color(0xFF4A6CF7),
                          ][angle.toInt() % 4]
                              .withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF2ECC71),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2ECC71).withValues(alpha: 0.35),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 42,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'הצלחה!',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'החשבון שלך נוצר בהצלחה ומוכן כעת.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      onPressed: widget.onContinue,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      child: const Text(
                        'המשך לאפליקציה',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Step Progress ────────────────────────────────────────────────────────────

class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.step, required this.total});
  final int step;
  final int total;

  static const _labels = ['חשבון', 'תפקיד', 'פרטים', 'נכס'];

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
                    color: i < step ? AppColors.primary : _kInputBorder,
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
              color: isDone || isActive ? AppColors.primary : _kInputBorder,
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
                color:
                    isActive ? AppColors.primary : AppColors.textDisabled,
                fontSize: 10,
                fontWeight: FontWeight.w700)),
      ],
    );
  }
}

// ─── Step: Email & Password ───────────────────────────────────────────────────

class _StepEmailPassword extends StatelessWidget {
  const _StepEmailPassword({
    required this.nameCtrl,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.obscure,
    required this.agreedToTerms,
    required this.onToggleObscure,
    required this.onToggleTerms,
    required this.googleLoading,
    required this.appleLoading,
    required this.onGoogle,
    required this.onApple,
    required this.onSwitchToLogin,
  });

  final TextEditingController nameCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final bool obscure;
  final bool agreedToTerms;
  final VoidCallback onToggleObscure;
  final VoidCallback onToggleTerms;
  final bool googleLoading;
  final bool appleLoading;
  final VoidCallback onGoogle;
  final VoidCallback onApple;
  final VoidCallback onSwitchToLogin;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title
          const Text(
            'יצירת חשבון',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.navy,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5),
          ),
          const SizedBox(height: 8),
          const Text(
            'מלאו את שמכם המלא, אימייל וסיסמה כדי להירשם ולהתחיל.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 24),

          // Social buttons
          _SocialRow(
            googleLoading: googleLoading,
            appleLoading: appleLoading,
            onGoogle: onGoogle,
            onApple: onApple,
          ),
          const SizedBox(height: 20),
          const _OrDivider(),
          const SizedBox(height: 20),

          // Name
          const _FieldLabel(label: 'שם מלא'),
          const SizedBox(height: 6),
          _CleanTextField(
            controller: nameCtrl,
            hint: 'שם ושם משפחה',
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 16),

          // Email
          const _FieldLabel(label: 'כתובת אימייל'),
          const SizedBox(height: 6),
          _CleanTextField(
            controller: emailCtrl,
            hint: 'name@example.com',
            keyboardType: TextInputType.emailAddress,
            textDirection: TextDirection.ltr,
          ),
          const SizedBox(height: 16),

          // Password
          const _FieldLabel(label: 'סיסמה'),
          const SizedBox(height: 6),
          _CleanTextField(
            controller: passwordCtrl,
            obscureText: obscure,
            hint: '••••••••',
            suffixIcon: GestureDetector(
              onTap: onToggleObscure,
              child: Icon(
                obscure
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                color: AppColors.textSecondary,
                size: 20,
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Terms toggle
          Row(
            children: [
              GestureDetector(
                onTap: onToggleTerms,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: agreedToTerms ? AppColors.primary : Colors.white,
                    border: Border.all(
                      color: agreedToTerms
                          ? AppColors.primary
                          : _kInputBorder,
                      width: 1.5,
                    ),
                  ),
                  child: agreedToTerms
                      ? const Icon(Icons.check_rounded,
                          size: 13, color: Colors.white)
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary),
                    children: const [
                      TextSpan(text: 'אני מסכים/ה ל'),
                      TextSpan(
                        text: 'תנאי השימוש',
                        style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: ' ו'),
                      TextSpan(
                        text: 'מדיניות הפרטיות',
                        style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Switch to login
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('כבר יש לך חשבון? ',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
                GestureDetector(
                  onTap: onSwitchToLogin,
                  child: const Text('התחברות',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
        ],
      ),
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
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('מה מביא אותך לכאן?',
              style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5)),
          const SizedBox(height: 4),
          const Text('בחרו מסלול כדי שנוכל להתאים את החוויה',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 22),
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
            color: selected ? accent : _kInputBorder,
            width: selected ? 0 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? accent.withValues(alpha: 0.24)
                  : const Color(0x0A072946),
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
              child:
                  Icon(icon, color: selected ? Colors.white : accent, size: 26),
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
                    : _kInputBorder.withValues(alpha: 0.6),
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
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('תקציב השכירות שלך',
              style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5)),
          const SizedBox(height: 6),
          const Text(
              'הגדר את התקציב החודשי כדי שנוכל להתאים עבורך את הדירות הטובות ביותר.',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 24),
          if (isTenant)
            _CompactBudgetPicker(budget: budget, onBudget: onBudget),
        ],
      ),
    );
  }
}

// ─── Compact Budget Picker ────────────────────────────────────────────────────

class _CompactBudgetPicker extends StatelessWidget {
  const _CompactBudgetPicker({required this.budget, required this.onBudget});
  final int budget;
  final ValueChanged<double> onBudget;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kInputBorder),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A072946), blurRadius: 8, offset: Offset(0, 2))
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
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
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
            Expanded(
              child: _PillButton(
                label: nextLabel,
                loading: loading,
                onTap: onNext,
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
                    color:
                        AppColors.textSecondary.withValues(alpha: 0.75))),
          ),
        ],
      ],
    );
  }
}

// ─── Pill Button ──────────────────────────────────────────────────────────────

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: FilledButton(
        onPressed: loading ? null : onTap,
        style: FilledButton.styleFrom(
          backgroundColor: _kPillBtn,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999)),
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: Colors.white))
            : Text(label,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800)),
      ),
    );
  }
}

// ─── Field Label ──────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label,
        style: const TextStyle(
            color: AppColors.navy,
            fontSize: 13,
            fontWeight: FontWeight.w700));
  }
}

// ─── Clean TextField ──────────────────────────────────────────────────────────

class _CleanTextField extends StatelessWidget {
  const _CleanTextField({
    this.controller,
    this.hint,
    this.keyboardType,
    this.textDirection,
    this.obscureText = false,
    this.suffixIcon,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController? controller;
  final String? hint;
  final TextInputType? keyboardType;
  final TextDirection? textDirection;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _kInputBorder),
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
        hintText: hint,
        suffixIcon: suffixIcon != null
            ? Padding(
                padding: const EdgeInsets.only(left: 12),
                child: suffixIcon,
              )
            : null,
        filled: true,
        fillColor: _kInputFill,
        hintStyle: TextStyle(
            color: AppColors.textSecondary.withValues(alpha: 0.6),
            fontWeight: FontWeight.w400),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
        ),
      ),
    );
  }
}

// ─── Auth TextField (legacy alias for steps that still use it) ────────────────

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: label),
        const SizedBox(height: 6),
        _CleanTextField(
          controller: controller,
          hint: hint,
          keyboardType: keyboardType,
          textDirection: textDirection,
          obscureText: obscureText,
          suffixIcon: suffixIcon,
          textCapitalization: textCapitalization,
        ),
      ],
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
    'מרפסת', 'חניה', 'מעלית', 'מיזוג', 'ממ"ד',
    'מחסן', 'גינה', 'ריהוט', 'מחמדים', 'אינטרנט',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text('פרטי הנכס',
                  style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5)),
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
          _AuthTextField(
            controller: cityCtrl,
            label: 'עיר / שכונה',
            icon: IconsaxPlusBold.location,
          ),
          const SizedBox(height: 12),
          _RoomsStepper(rooms: rooms, onRooms: onRooms),
          const SizedBox(height: 14),
          const Text('מה יש בנכס?',
              style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 14,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 9),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kInputBorder),
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
              : _kInputBorder.withValues(alpha: 0.6),
        ),
        child: Icon(icon,
            size: 16, color: filled ? Colors.white : AppColors.textSecondary),
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
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected ? AppColors.primary : Colors.white,
          border: Border.all(
              color: selected ? AppColors.primary : _kInputBorder),
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

class _EulaSection extends StatelessWidget {
  const _EulaSection({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
          const SizedBox(height: 3),
          Text(body,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}
