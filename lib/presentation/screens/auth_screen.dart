import 'dart:async';
import 'package:dating_app/core/ui/platform_fx.dart';
import 'dart:ui';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/constants/brand_palette.dart';
import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/services/apple_auth_service.dart';
import 'package:dating_app/core/services/google_auth_service.dart';
import 'package:dating_app/core/services/notif_admin_gate.dart';
import 'package:dating_app/core/services/notification_permission_service.dart';
import 'package:dating_app/presentation/screens/admin/notif_console_screen.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/data/repositories/property_repository.dart';
import 'package:dating_app/presentation/screens/home_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:dating_app/presentation/widgets/rently_icon.dart';
import 'package:provider/provider.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:dating_app/presentation/widgets/animations/micro_animations.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────

const _kScreenBg = AppColors.slate100;
const _kCardBg = Colors.white;
const _kInputBorder = AppColors.slate200;
const _kInputFill = AppColors.slate50;

/// Fixed source-teal brand for the ENTIRE entry flow (welcome / login / signup
/// / role-pick / guest entry). The entry experience must NEVER render the
/// broker-black accent — a broker only gets black once inside the app. Using a
/// compile-time constant here (instead of the runtime-swappable
/// [_kBrandTeal]) makes the entry screens structurally immune to any
/// global accent flip that happens while a session is being established.
const Color _kBrandTeal = AppColors.tealBrand;
const Color _kPillBtn = _kBrandTeal;

// ─── Auth Screen ──────────────────────────────────────────────────────────────

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

enum AuthView { welcome, login, register }

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  AuthView _currentView = AuthView.welcome;

  // Role chosen via the top "אני בעל דירה" CTA. null → tenant (the default).
  String? _pendingRole;

  final _googleAuthService = GoogleAuthService();
  final _appleAuthService = AppleAuthService();
  bool _googleLoading = false;
  bool _appleLoading = false;

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

  Future<void> _onEnter() async {
    // Crossing the entry → in-app boundary. Flip the "inside the app" flag that
    // gates broker-black theming, so the accent only switches to black AFTER we
    // leave the entry flow — never on the auth screens themselves. This is the
    // single seam through which welcome/login/register/guest entry all reach
    // HomeScreen, so one call here covers every path.
    context.read<DatingProvider>().markEnteredApp();

    // Admin gate: the notification-broadcast admin (custom claim
    // `notifAdmin: true`) is routed to the console instead of HomeScreen.
    final isAdmin = await NotifAdminGate.isAdmin();
    if (!mounted) return;

    if (isAdmin) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, animation, __) => const NotifConsoleScreen(),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => const HomeScreen(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );

    // First-launch notification permission rationale + request (once per
    // install). Runs after we've reached HomeScreen so the dialog sits over it.
    if (!mounted) return;
    await NotificationPermissionService.maybeRequestOnFirstLaunch(context);
  }

  // Top "אני בעל דירה" CTA: pick landlord vs agent, then jump into the register
  // flow with that role pre-set. Tenants never see this — they're the default.
  Future<void> _onLandlordCta() async {
    final picked = await _promptLandlordOrAgent(context);
    if (!mounted || picked == null) return;
    setState(() {
      _pendingRole = picked;
      _currentView = AuthView.register;
    });
  }

  // Wide/tablet register tab account-type selector. Same landlord/broker dialog
  // as the mobile CTA, but the wide layout switches tabs instead of views, so it
  // sets _pendingRole and moves to the register tab. Picking nothing (dismiss)
  // leaves the role untouched.
  Future<void> _onWidePickAccountType() async {
    final picked = await _promptLandlordOrAgent(context);
    if (!mounted || picked == null) return;
    setState(() => _pendingRole = picked);
    _tabController.animateTo(1);
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

  Future<void> _loginWithGoogleForWelcome() async {
    if (_googleLoading) return;
    if (!AppConfig.enableGoogleSignIn) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(milliseconds: 2500),
          content: Text('כניסה עם Google לא מופעלת בסביבת ההרצה הזו')));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _googleLoading = true);
    try {
      final result = await _googleAuthService.signIn();
      if (!mounted) return;

      final provider = context.read<DatingProvider>();
      // Default to tenant; landlord/agent is set via the top "אני בעל דירה" CTA.
      final role = _pendingRole ?? 'tenant';

      await provider.applyGoogleIdentity(
          displayName: result.displayName, photoUrl: result.photoUrl);
      await provider.setUserRole(role, explicit: true);
      if (!mounted) return;
      _onEnter();
    } on GoogleAuthCanceledException {
      // no-op
    } on GoogleAuthConfigException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(milliseconds: 2500),
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
          const SnackBar(
              duration: Duration(milliseconds: 2500),
              content: Text('הכניסה עם Google נכשלה. נסו שוב.')));
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _loginWithAppleForWelcome() async {
    if (_appleLoading) return;
    FocusScope.of(context).unfocus();
    setState(() => _appleLoading = true);
    try {
      final result = await _appleAuthService.signIn();
      if (!mounted) return;

      final provider = context.read<DatingProvider>();
      // Default to tenant; landlord/agent is set via the top "אני בעל דירה" CTA.
      final role = _pendingRole ?? 'tenant';

      await provider.applyGoogleIdentity(
          displayName: result.displayName, photoUrl: null, source: 'apple');
      await provider.setUserRole(role, explicit: true);
      if (!mounted) return;
      _onEnter();
    } on AppleAuthCanceledException {
      // user dismissed — no-op
    } on AppleAuthUnsupportedException {
      if (!mounted) return;
      _showAppleError('כניסה עם Apple זמינה במכשירי Apple בלבד.');
    } on SignInWithAppleAuthorizationException catch (e, st) {
      if (!mounted) return;
      if (e.code == AuthorizationErrorCode.canceled) return;
      debugPrint('[AppleAuth] AUTH-EXC ${e.code.name}: ${e.message}\n$st');
      _showAppleError(
          'הכניסה עם Apple נכשלה.\n\nקוד: ${e.code.name}\nפרטים: ${e.message}');
    } on FirebaseAuthException catch (e, st) {
      if (!mounted) return;
      debugPrint('[AppleAuth] FIREBASE ${e.code}: ${e.message}\n$st');
      _showAppleError(
          '${_appleFirebaseErrorMessage(e.code)}\n\n[firebase:${e.code}]');
    } catch (e, st) {
      if (!mounted) return;
      debugPrint('[AppleAuth] GENERIC ${e.runtimeType}: $e\n$st');
      _showAppleError('הכניסה עם Apple נכשלה.\n\n${e.runtimeType}: $e');
    } finally {
      if (mounted) setState(() => _appleLoading = false);
    }
  }

  String _appleFirebaseErrorMessage(String code) {
    switch (code) {
      case 'operation-not-allowed':
        return 'כניסה עם Apple לא מופעלת כרגע. נסו שוב מאוחר יותר.';
      case 'account-exists-with-different-credential':
        return 'כתובת המייל כבר רשומה עם שיטת כניסה אחרת. נסו להיכנס עם Google.';
      case 'invalid-credential':
        return 'פרטי ה-Apple אינם תקינים. נסו שוב.';
      case 'user-disabled':
        return 'החשבון הזה הושבת. פנו לתמיכה.';
      default:
        return 'הכניסה עם Apple נכשלה ($code). נסו שוב.';
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
        content: SingleChildScrollView(
          child: SelectableText(message,
              style: const TextStyle(color: AppColors.slate600, height: 1.4)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('סגור', style: TextStyle(color: AppColors.slate500)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _kBrandTeal,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _onGuestEnter();
            },
            child: const Text('כניסה כאורח'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 1040;
    if (isWide) {
      return Scaffold(
        backgroundColor: _kScreenBg,
        body: _WideLayout(
          tabController: _tabController,
          onLogin: _onEnter,
          onGuestLogin: _onGuestEnter,
          onDone: _onEnter,
          registerRole: _pendingRole ?? 'tenant',
          onPickAccountType: _onWidePickAccountType,
        ),
      );
    }

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: child,
        ),
        child: _buildMobileContent(),
      ),
    );
  }

  Widget _buildMobileContent() {
    switch (_currentView) {
      case AuthView.welcome:
        return _WelcomePortal(
          key: const ValueKey('welcome_portal'),
          // Taking the tenant path ("מחפש דירה") must clear any landlord/broker
          // role left over from a prior "בעל דירה" tap, otherwise the stale
          // _pendingRole would register/log this user in as a landlord.
          onLogin: () => setState(() {
            _pendingRole = null;
            _currentView = AuthView.login;
          }),
          onGoogleLogin: _loginWithGoogleForWelcome,
          onAppleLogin: _loginWithAppleForWelcome,
          onGuestLogin: _onGuestEnter,
          onLandlordCta: _onLandlordCta,
        );
      case AuthView.login:
        return Stack(
          key: const ValueKey('login_view'),
          children: [
            Image.network(
              'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?q=80&w=1000',
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(color: AppColors.navy);
              },
              errorBuilder: (context, error, stackTrace) => Container(color: AppColors.navy),
            ),
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.5),
              ),
            ),
            SafeArea(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                child: _LoginTab(
                  onLogin: _onEnter,
                  onGuestLogin: _onGuestEnter,
                  onSwitchToRegister: () => setState(() => _currentView = AuthView.register),
                  onBack: () => setState(() => _currentView = AuthView.welcome),
                ),
              ),
            ),
          ],
        );
      case AuthView.register:
        return Stack(
          key: const ValueKey('register_view'),
          children: [
            Image.network(
              'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?q=80&w=1000',
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(color: AppColors.navy);
              },
              errorBuilder: (context, error, stackTrace) => Container(color: AppColors.navy),
            ),
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.5),
              ),
            ),
            SafeArea(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                child: _RegisterFlow(
                  initialRole: _pendingRole ?? 'tenant',
                  onDone: _onEnter,
                  onSwitchToLogin: () => setState(() => _currentView = AuthView.login),
                  onBack: () => setState(() => _currentView = AuthView.welcome),
                ),
              ),
            ),
          ],
        );
    }
  }
}

// ─── Wide Layout ──────────────────────────────────────────────────────────────

class _WideLayout extends StatelessWidget {
  const _WideLayout({
    required this.tabController,
    required this.onLogin,
    required this.onGuestLogin,
    required this.onDone,
    required this.registerRole,
    required this.onPickAccountType,
  });

  final TabController tabController;
  final VoidCallback onLogin;
  final VoidCallback onGuestLogin;
  final VoidCallback onDone;

  /// Role for the register tab: 'tenant' (default), 'landlord' or 'broker'.
  final String registerRole;

  /// Opens the landlord/broker account-type dialog for the register tab.
  final VoidCallback onPickAccountType;

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
                                      tabController.animateTo(1),
                                  onBack: () {},
                              ),
                              Column(
                                children: [
                                  _WideAccountTypeSelector(
                                    role: registerRole,
                                    onPick: onPickAccountType,
                                  ),
                                  const SizedBox(height: 12),
                                  Expanded(
                                    child: _RegisterFlow(
                                      // Keyed by role so re-picking the account
                                      // type rebuilds the flow with the new role
                                      // (the flow captures initialRole once).
                                      key: ValueKey('wide_register_$registerRole'),
                                      initialRole: registerRole,
                                      onDone: onDone,
                                      onSwitchToLogin: () =>
                                          tabController.animateTo(0),
                                      onBack: () {},
                                    ),
                                  ),
                                ],
                              ),
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

// ─── Wide Account-Type Selector ───────────────────────────────────────────────

/// Sits above the register form in the wide/tablet layout. Shows the currently
/// chosen account type and opens the landlord/broker dialog so the wide flow can
/// register a landlord or broker (mirrors the mobile "אני בעל דירה" CTA).
class _WideAccountTypeSelector extends StatelessWidget {
  const _WideAccountTypeSelector({required this.role, required this.onPick});

  final String role;
  final VoidCallback onPick;

  static const _labels = {
    'tenant': 'מחפש/ת דירה',
    'landlord': 'בעל/ת דירה',
    'broker': 'מתווך/ת נדל״ן',
  };

  @override
  Widget build(BuildContext context) {
    final isTenant = role == 'tenant';
    final label = _labels[role] ?? _labels['tenant']!;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onPick,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _kInputFill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kInputBorder),
        ),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _kBrandTeal.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
                isTenant
                    ? IconsaxPlusLinear.profile_circle
                    : IconsaxPlusLinear.home,
                color: _kBrandTeal,
                size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('סוג חשבון',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                Text(label,
                    style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 14,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          Text(isTenant ? 'בעל דירה / מתווך' : 'שינוי',
              style: const TextStyle(
                  color: _kBrandTeal,
                  fontSize: 13,
                  fontWeight: FontWeight.w800)),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_left_rounded,
              color: _kBrandTeal, size: 20),
        ]),
      ),
    );
  }
}

// ─── Logo Header for Mobile ──────────────────────────────────────────────────

class _LogoHeader extends StatelessWidget {
  const _LogoHeader({
    required this.showBackButton,
    this.onBack,
    this.isDark = false,
    this.logoHeight = 34,
  });

  final bool showBackButton;
  final VoidCallback? onBack;
  final bool isDark;
  final double logoHeight;

  @override
  Widget build(BuildContext context) {
    final color = isDark ? Colors.white : AppColors.navy;
    final stackHeight = logoHeight > 34 ? logoHeight + 12 : 48.0;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: SizedBox(
        width: double.infinity,
        height: stackHeight,
        child: Stack(
          alignment: Alignment.center,
          children: [
            BreatheAnimation(
              child: SvgPicture.asset(
                'assets/images/rently_logo_with_text.svg',
                height: logoHeight,
                colorFilter:
                    ColorFilter.mode(color, BlendMode.srcIn),
                placeholderBuilder: (_) => Text('Rently',
                    style: TextStyle(
                        color: color,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1)),
              ),
            ),
            if (showBackButton)
              Positioned(
                right: 0,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? Colors.white.withOpacity(0.12) : Colors.white,
                    border: Border.all(color: isDark ? Colors.white.withOpacity(0.18) : _kInputBorder),
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.arrow_back_rounded,
                        size: 18, color: isDark ? Colors.white : AppColors.navy),
                    onPressed: onBack,
                  ),
                ),
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
          'assets/images/rently_logo_with_text.svg',
          height: 48,
          colorFilter: const ColorFilter.mode(AppColors.navy, BlendMode.srcIn),
          placeholderBuilder: (_) => const Text('Rently',
              style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 38,
                  fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 24),
        const Text(
          'הדרך המהירה\nלמצוא את הבית הבא שלך.',
          style: TextStyle(
              fontFamily: 'SF Hebrew Rounded',
              color: AppColors.navy,
              fontSize: 42,
              height: 1.15,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.2),
        ),
        const SizedBox(height: 14),
        Text(
          'Rently מחבר שוכרים ומשכירים בחוויה חכמה, מהירה וברורה.',
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
          icon: IconsaxPlusLinear.building,
          title: 'גלילת דירות חכמה',
          subtitle: 'מציג רק את מה שמתאים לפרופיל שלך'),
      SizedBox(height: 12),
      _WideFeatureItem(
          icon: IconsaxPlusLinear.heart,
          title: 'התאמה דו-כיוונית',
          subtitle: 'שוכרים ומשכירים מאשרים זה את זה'),
      SizedBox(height: 12),
      _WideFeatureItem(
          icon: IconsaxPlusLinear.message,
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
            color: _kBrandTeal.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14)),
        child: Icon(icon, color: _kBrandTeal, size: 20),
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
      indicatorColor: _kBrandTeal,
      indicatorWeight: 2.5,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: _kInputBorder,
      labelColor: AppColors.navy,
      unselectedLabelColor: AppColors.textSecondary,
      labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
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
    this.isDark = false,
  });

  final bool googleLoading;
  final bool appleLoading;
  final VoidCallback onGoogle;
  final VoidCallback onApple;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AppleAuthService.isAvailable,
      builder: (context, snapshot) {
        final showApple = snapshot.data == true;
        final showGoogle = AppConfig.enableGoogleSignIn;
        if (!showGoogle && !showApple) return const SizedBox.shrink();

        final textColor = isDark ? Colors.white : AppColors.navy;

        return Row(children: [
          if (showGoogle)
            Expanded(
              child: _SocialBtn(
                loading: googleLoading,
                onTap: onGoogle,
                isDark: isDark,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                          color: isDark ? Colors.white.withOpacity(0.15) : AppColors.slate100,
                          borderRadius: BorderRadius.circular(4)),
                      child: Center(
                        child: Text('G',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: isDark ? Colors.white : AppColors.superLike)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('Google',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: textColor)),
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
                isDark: isDark,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.apple_rounded, size: 20, color: isDark ? Colors.white : AppColors.navy),
                    const SizedBox(width: 6),
                    Text('Apple',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: textColor)),
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
  const _SocialBtn({
    required this.loading,
    required this.onTap,
    required this.child,
    this.isDark = false,
  });

  final bool loading;
  final VoidCallback onTap;
  final Widget child;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.15) : _kInputBorder,
            width: 1.5,
          ),
          boxShadow: isDark
              ? const []
              : const [
                  BoxShadow(
                      color: Color(0x0A072946), blurRadius: 8, offset: Offset(0, 2))
                ],
        ),
        child: loading
            ? Center(
                child: ShineDecorator(
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: isDark ? Colors.white : AppColors.navy)),
                ),
              )
            : child,
      ),
    );
  }
}

// ─── OR Divider ───────────────────────────────────────────────────────────────

class _OrDivider extends StatelessWidget {
  const _OrDivider({this.isDark = false});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final lineColor = isDark ? Colors.white.withOpacity(0.15) : _kInputBorder;
    final textColor = isDark ? Colors.white60 : AppColors.textSecondary.withValues(alpha: 0.7);
    return Row(children: [
      Expanded(child: Divider(color: lineColor)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Text('או',
            style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ),
      Expanded(child: Divider(color: lineColor)),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: PlatformFx.blurSigma(25), sigmaY: PlatformFx.blurSigma(25)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460, maxHeight: 520),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(40),
              border: Border.all(color: Colors.white.withOpacity(0.24), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
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
                          color: Colors.white)),
                  const SizedBox(height: 8),
                  Text(
                    'בחרו האם להיכנס כבעל דירה או כדייר שמחפש דירה.',
                    style: TextStyle(
                        fontSize: 14, height: 1.5, color: Colors.white.withOpacity(0.7)),
                  ),
                  const SizedBox(height: 20),
                  _GuestRoleOption(
                    title: 'אורח כדייר מחפש דירה',
                    subtitle: 'דירות פעילות ומאצ׳ים פתוחים.',
                    icon: IconsaxPlusLinear.profile_circle,
                    color: _kBrandTeal,
                    onTap: () => Navigator.of(context).pop('tenant'),
                  ),
                  const SizedBox(height: 12),
                  _GuestRoleOption(
                    title: 'אורח כבעל דירה',
                    subtitle: 'נכסים פעילים ומועמדים בתהליך.',
                    icon: IconsaxPlusLinear.home,
                    color: _kBrandTeal, // use primary brand color so it pops nicely on dark glass
                    onTap: () => Navigator.of(context).pop('landlord'),
                  ),
                  const SizedBox(height: 12),
                  _GuestRoleOption(
                    title: 'אורח כמתווך נדל״ן',
                    subtitle: 'ניהול נכסים, לידים והתאמות ללקוחות.',
                    icon: IconsaxPlusLinear.briefcase,
                    color: BrandPalette.broker.primary,
                    onTap: () => Navigator.of(context).pop('broker'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Landlord / Agent Role Dialog ─────────────────────────────────────────────

/// Opened by the top "אני בעל דירה" CTA. Lets the user declare a landlord or
/// real-estate-agent account; tenants are the default and never see this.
/// Returns 'landlord' / 'broker', or null if dismissed.
Future<String?> _promptLandlordOrAgent(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const _LandlordAgentDialog(),
  );
}

class _LandlordAgentDialog extends StatelessWidget {
  const _LandlordAgentDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: PlatformFx.blurSigma(25), sigmaY: PlatformFx.blurSigma(25)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460, maxHeight: 520),
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(40),
              border: Border.all(
                  color: Colors.white.withOpacity(0.24), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'כניסה כבעל דירה',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'בחרו את סוג החשבון. מחפשי דירה נכנסים כברירת מחדל.',
                    style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: Colors.white.withOpacity(0.75)),
                  ),
                  const SizedBox(height: 22),
                  _GuestRoleOption(
                    title: 'בעל/ת דירה',
                    subtitle: 'פרסם נכסים, נהל בקשות ומצא דיירים.',
                    icon: IconsaxPlusLinear.home,
                    color: _kBrandTeal,
                    onTap: () => Navigator.of(context).pop('landlord'),
                  ),
                  const SizedBox(height: 12),
                  _GuestRoleOption(
                    title: 'מתווך/ת נדל״ן',
                    subtitle: 'ניהול נכסים, לידים והתאמות ללקוחות.',
                    icon: IconsaxPlusLinear.briefcase,
                    color: BrandPalette.broker.primary,
                    onTap: () => Navigator.of(context).pop('broker'),
                  ),
                ],
              ),
            ),
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
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.18)),
            color: Colors.white.withOpacity(0.05),
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
                          color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: Colors.white.withOpacity(0.7))),
                ],
              ),
            ),
            const RentlyIcon(IconsaxPlusLinear.arrow_left_2, color: Colors.white, size: 16),
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
    required this.onBack,
  });
  final VoidCallback onLogin;
  final VoidCallback onGuestLogin;
  final VoidCallback onSwitchToRegister;
  final VoidCallback onBack;

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
  final _shakeCtrl = ShakeController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _showTerms() async {
    await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'תנאי השימוש',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 360),
      pageBuilder: (ctx, anim1, anim2) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: PlatformFx.blurSigma(8), sigmaY: PlatformFx.blurSigma(8)),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(
                  CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic)),
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
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      _shakeCtrl.shake();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(
              duration: Duration(milliseconds: 2500),
              content: Text('יש למלא אימייל וסיסמה')));
      return;
    }
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password)
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      final provider = context.read<DatingProvider>();
      // Bind the session to the real Firebase UID and pull the user's stored
      // profile + listings back from the backend. Social logins already do this
      // via applyAuthenticatedIdentity; email login must too, otherwise a
      // returning landlord never sees the properties they uploaded.
      final displayName =
          FirebaseAuth.instance.currentUser?.displayName ?? '';
      await provider.applyAuthenticatedIdentity(
          displayName: displayName, source: 'email');
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(milliseconds: 2500),
          content: Text(msg)));
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(milliseconds: 3000),
          content: Text('אין חיבור לרשת. בדוק את החיבור לאינטרנט ונסה שוב.')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    FocusScope.of(context).unfocus();
    final email = _emailCtrl.text.trim();
    final emailValid =
        RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    if (email.isEmpty || !emailValid) {
      _shakeCtrl.shake();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(milliseconds: 2500),
          content: Text('הזינו קודם את כתובת האימייל שלכם לאיפוס הסיסמה')));
      return;
    }
    try {
      await FirebaseAuth.instance
          .sendPasswordResetEmail(email: email)
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(milliseconds: 3000),
          content: Text('שלחנו קישור לאיפוס סיסמה למייל שלך')));
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final msg = switch (e.code) {
        'invalid-email' => 'כתובת האימייל אינה תקינה',
        'user-not-found' => 'לא נמצא חשבון עם האימייל הזה',
        'too-many-requests' => 'יותר מדי ניסיונות, נסה שוב מאוחר יותר',
        _ => 'שגיאה בשליחת קישור האיפוס, נסה שוב',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(milliseconds: 2500),
          content: Text(msg)));
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(milliseconds: 3000),
          content: Text('אין חיבור לרשת. בדוק את החיבור לאינטרנט ונסה שוב.')));
    }
  }

  Future<void> _loginWithGoogle() async {
    if (_googleLoading) return;
    if (!AppConfig.enableGoogleSignIn) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(milliseconds: 2500),
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
      // Login honours the account's stored role (tenant by default); the
      // landlord/agent role is chosen up front via the top CTA, not here.
      await provider.setUserRole(provider.userRole);
      if (!mounted) return;
      widget.onLogin();
    } on GoogleAuthCanceledException {
      // no-op
    } on GoogleAuthConfigException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(milliseconds: 2500),
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
          const SnackBar(
              duration: Duration(milliseconds: 2500),
              content: Text('הכניסה עם Google נכשלה. נסו שוב.')));
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
          displayName: result.displayName, photoUrl: null, source: 'apple');
      // Login honours the account's stored role (tenant by default).
      await provider.setUserRole(provider.userRole);
      if (!mounted) return;
      widget.onLogin();
    } on AppleAuthCanceledException {
      // user dismissed — no-op
    } on AppleAuthUnsupportedException {
      if (!mounted) return;
      _showAppleError('כניסה עם Apple זמינה במכשירי Apple בלבד.');
    } on SignInWithAppleAuthorizationException catch (e, st) {
      if (!mounted) return;
      if (e.code == AuthorizationErrorCode.canceled) return;
      debugPrint('[AppleAuth] AUTH-EXC ${e.code.name}: ${e.message}\n$st');
      _showAppleError(
          'הכניסה עם Apple נכשלה.\n\nקוד: ${e.code.name}\nפרטים: ${e.message}');
    } on FirebaseAuthException catch (e, st) {
      if (!mounted) return;
      debugPrint('[AppleAuth] FIREBASE ${e.code}: ${e.message}\n$st');
      _showAppleError(
          '${_appleFirebaseErrorMessage(e.code)}\n\n[firebase:${e.code}]');
    } catch (e, st) {
      if (!mounted) return;
      debugPrint('[AppleAuth] GENERIC ${e.runtimeType}: $e\n$st');
      _showAppleError('הכניסה עם Apple נכשלה.\n\n${e.runtimeType}: $e');
    } finally {
      if (mounted) setState(() => _appleLoading = false);
    }
  }

  String _appleFirebaseErrorMessage(String code) {
    switch (code) {
      case 'operation-not-allowed':
        return 'כניסה עם Apple לא מופעלת כרגע. נסו שוב מאוחר יותר.';
      case 'account-exists-with-different-credential':
        return 'כתובת המייל כבר רשומה עם שיטת כניסה אחרת. נסו להיכנס עם Google.';
      case 'invalid-credential':
        return 'פרטי ה-Apple אינם תקינים. נסו שוב.';
      case 'user-disabled':
        return 'החשבון הזה הושבת. פנו לתמיכה.';
      default:
        return 'הכניסה עם Apple נכשלה ($code). נסו שוב.';
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
        content: SingleChildScrollView(
          child: SelectableText(message,
              style: const TextStyle(color: AppColors.slate600, height: 1.4)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('סגור', style: TextStyle(color: AppColors.slate500)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _kBrandTeal,
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
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LogoHeader(
              showBackButton: true,
              onBack: widget.onBack,
              isDark: true,
              logoHeight: 135,
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(40),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: PlatformFx.blurSigma(25), sigmaY: PlatformFx.blurSigma(25)),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(color: Colors.white.withOpacity(0.24), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(22),
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title
                  const Text(
                    'ברוכים השבים',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        shadows: [
                          Shadow(
                            color: Color(0x40000000),
                            blurRadius: 10,
                            offset: Offset(0, 2),
                          ),
                        ]),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'התחברו עם כתובת האימייל והסיסמה שלכם כדי לגשת לחשבון.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13.5,
                        height: 1.35,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 20),
                  _SocialRow(
                    googleLoading: _googleLoading,
                    appleLoading: _appleLoading,
                    onGoogle: _loginWithGoogle,
                    onApple: _loginWithApple,
                    isDark: true,
                  ),
                  const SizedBox(height: 16),
                  const _OrDivider(isDark: true),
                  const SizedBox(height: 16),

                  HorizontalShake(
                    controller: _shakeCtrl,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Email
                        const _FieldLabel(label: 'כתובת אימייל', isDark: true),
                        const SizedBox(height: 4),
                        _CleanTextField(
                          controller: _emailCtrl,
                          hint: 'name@example.com',
                          keyboardType: TextInputType.emailAddress,
                          textDirection: TextDirection.ltr,
                          prefixIcon: IconsaxPlusLinear.sms,
                          isDark: true,
                        ),
                        const SizedBox(height: 12),

                        // Password
                        const _FieldLabel(label: 'סיסמה', isDark: true),
                        const SizedBox(height: 4),
                        _CleanTextField(
                          controller: _passwordCtrl,
                          obscureText: _obscure,
                          hint: '••••••••',
                          prefixIcon: IconsaxPlusLinear.key,
                          isDark: true,
                          suffixIcon: EyeMorphIcon(
                            isObscured: _obscure,
                            onTap: () => setState(() => _obscure = !_obscure),
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

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
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(5),
                                color: _rememberMe ? _kBrandTeal : Colors.transparent,
                                border: Border.all(
                                  color:
                                      _rememberMe ? _kBrandTeal : Colors.white.withOpacity(0.25),
                                  width: 1.5,
                                ),
                              ),
                              child: _rememberMe
                                  ? const Icon(Icons.check_rounded,
                                      size: 10, color: Colors.white)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'זכור אותי',
                            style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      TextButton(
                        onPressed: _resetPassword,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'שכחת סיסמה?',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // Login CTA
                  _PillButton(
                    label: 'התחברות',
                    loading: _loading,
                    onTap: _login,
                  ),
                  const SizedBox(height: 14),

                  // Terms of use — presented before login (App Store Guideline 1.2)
                  Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          'בהתחברות אני מאשר/ת את ',
                          style: TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                              fontWeight: FontWeight.w500),
                        ),
                        GestureDetector(
                          onTap: _showTerms,
                          child: const Text(
                            'תנאי השימוש',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                decoration: TextDecoration.underline),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Guest / Anonymous entry
                  Center(
                    child: TextButton(
                      onPressed: widget.onGuestLogin,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(IconsaxPlusLinear.eye, size: 14, color: Colors.white.withOpacity(0.7)),
                          const SizedBox(width: 6),
                          Text('המשך כאורח',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      Colors.white.withOpacity(0.7))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Switch to register
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('אין לך חשבון? ',
                            style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.w500)),
                        GestureDetector(
                          onTap: widget.onSwitchToRegister,
                          child: Text('הרשמה',
                              style: TextStyle(
                                  color: _kBrandTeal,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
      ),
    );
  }
}

// ─── Register Flow ────────────────────────────────────────────────────────────

class _RegisterFlow extends StatefulWidget {
  const _RegisterFlow({
    super.key,
    required this.onDone,
    required this.onSwitchToLogin,
    required this.onBack,
    this.initialRole = 'tenant',
  });
  final VoidCallback onDone;
  final VoidCallback onSwitchToLogin;
  final VoidCallback onBack;

  /// Role chosen before entering signup. 'tenant' (default) or 'landlord' /
  /// 'broker' when the user came in via the top "אני בעל דירה" CTA. There is no
  /// in-flow role step anymore — the role is fixed here.
  final String initialRole;

  @override
  State<_RegisterFlow> createState() => _RegisterFlowState();
}

class _RegisterFlowState extends State<_RegisterFlow> {
  final _pageCtrl = PageController();
  int _step = 0;
  late final String _role = widget.initialRole;
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

  int get _totalSteps => 2;

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
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(
                duration: Duration(milliseconds: 2500),
                content: Text('יש להזין שם מלא')));
        return;
      }
      if (email.isEmpty || !email.contains('@')) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                duration: Duration(milliseconds: 2500),
                content: Text('יש להזין כתובת אימייל תקינה')));
        return;
      }
      if (password.length < 8) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                duration: Duration(milliseconds: 2500),
                content: Text('הסיסמה חייבת להכיל לפחות 8 תווים')));
        return;
      }
      if (!_agreedToTerms) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            duration: Duration(milliseconds: 2500),
            content: Text('יש לאשר את תנאי השימוש ומדיניות הפרטיות')));
        return;
      }
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
      // Sign up with the role chosen before entering the flow (tenant default).
      await provider.setUserRole(_role, explicit: true);
      if (!mounted) return;
      widget.onDone();
    } on GoogleAuthCanceledException {
      // no-op
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              duration: Duration(milliseconds: 2500),
              content: Text('הכניסה עם Google נכשלה. נסו שוב.')));
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
      // Sign up with the role chosen before entering the flow (tenant default).
      await provider.setUserRole(_role, explicit: true);
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
          filter: ImageFilter.blur(sigmaX: PlatformFx.blurSigma(8), sigmaY: PlatformFx.blurSigma(8)),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(
                  CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic)),
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

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      if (!mounted) return;
      final provider = context.read<DatingProvider>();
      final name = _nameCtrl.text.trim();
      // Bind the profile to the real Firebase UID FIRST. Previously this used
      // `(current ?? TenantProfile(id: uid)).copyWith(...)`, but since the
      // provider seeds a default profile at startup, `current` was never null
      // and copyWith preserved the shared constant id 'tenant-local' — so every
      // email user (and all their uploads) ended up under the same owner id.
      // applyAuthenticatedIdentity forces profile.id = uid before the draft
      // property below is created, isolating each user's data correctly.
      await provider.applyAuthenticatedIdentity(displayName: name, source: 'email');
      final bound = provider.tenantProfile;
      if (bound != null) {
        await provider.updateTenantProfile(
          bound.copyWith(
            name: name,
            budgetMax: _budget,
            desiredRooms: 2,
            moveInWindow: 'גמיש',
          ),
        );
      }
      // The user explicitly picked this role on the role step, so mark it
      // explicit — this keeps the role authoritative on relaunch and matches
      // the social-signup paths (which also pass explicit: true).
      await provider.setUserRole(_role, explicit: true);
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(milliseconds: 2500),
          content: Text(msg)));
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
          filter: ImageFilter.blur(sigmaX: PlatformFx.blurSigma(8), sigmaY: PlatformFx.blurSigma(8)),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(
                  CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic)),
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
    final isOptionalStep = _role == 'landlord' && _step == 1;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _LogoHeader(
            showBackButton: true,
            onBack: _step > 0 ? _prev : widget.onBack,
            isDark: true,
          ),
        ),
        if (_step > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: _StepProgress(step: _step, total: _totalSteps),
          ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                16,
                4,
                16,
                12 + MediaQuery.of(context).padding.bottom),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(56),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: PlatformFx.blurSigma(25), sigmaY: PlatformFx.blurSigma(25)),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(56),
                    border: Border.all(color: Colors.white.withOpacity(0.24), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
              children: [
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
                        isDark: true,
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
                          isDark: true,
                        )
                      else
                        _StepPersonal(
                          nameCtrl: _nameCtrl,
                          role: _role,
                          budget: _budget,
                          onBudget: (v) =>
                              setState(() => _budget = (v / 100).round() * 100),
                          isDark: true,
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _NavButtons(
                        nextLabel: _nextLabel,
                        loading: _loading,
                        onPrev: _step > 0 ? _prev : null,
                        onNext: _next,
                        onSkip: isOptionalStep ? _submit : null,
                      ),
                      if (_step == 0) ...[
                        const SizedBox(height: 12),
                        Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('כבר יש לך חשבון? ',
                                  style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500)),
                              GestureDetector(
                                onTap: widget.onSwitchToLogin,
                                child: Text('התחברות',
                                    style: TextStyle(
                                        color: _kBrandTeal,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
      ],
    );
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
        padding: EdgeInsets.fromLTRB(
            24, 60, 24, 28 + MediaQuery.of(context).padding.bottom),
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 30,
                offset: Offset(0, -10)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'תנאי השימוש ב-Rently',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.black,
                  fontSize: 22,
                  fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 200,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'ברוך הבא ל-Rently!\nבשימוש באפליקציה אתה מסכים לתנאים הבאים:',
                      style: TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          height: 1.4),
                    ),
                    SizedBox(height: 12),
                    _EulaSection(
                        title: '1. תוכן הולם',
                        body:
                            'אין לפרסם תוכן פוגעני, גזעני, מיני, מאיים או כל תוכן שפוגע בזכויות אחרים.'),
                    _EulaSection(
                        title: '2. ללא אלימות ואיום',
                        body:
                            'כל צורה של הטרדה, איום, בריונות או התנהגות פוגענית אסורה לחלוטין.'),
                    _EulaSection(
                        title: '3. דיווח תוכן',
                        body:
                            'משתמשים יכולים לדווח על תוכן שפוגע בהנחיות. נטפל בכל דיווח תוך 24 שעות.'),
                    _EulaSection(
                        title: '4. חסימת משתמשים',
                        body: 'ניתן לחסום כל משתמש שמתנהג בצורה לא הולמת.'),
                    _EulaSection(
                        title: '5. פרטיות',
                        body:
                            'אנו מכבדים את פרטיותך. המידע ישמש לצורך התאמת נכסים בלבד.'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDecline,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.slate200),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999)),
                    ),
                    child: const Text('ביטול',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
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
                          borderRadius: BorderRadius.circular(999)),
                    ),
                    child: const Text('אני מסכים/ה',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
        padding: EdgeInsets.fromLTRB(
            24, 60, 24, 28 + MediaQuery.of(context).padding.bottom),
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
                  for (final angle in [
                    0.0,
                    0.6,
                    1.2,
                    1.8,
                    2.4,
                    3.0,
                    3.6,
                    4.2,
                    4.8,
                    5.4
                  ])
                    Transform.translate(
                      offset: Offset(68 * (0.5 - (angle * 1.618 % 1.0)),
                          68 * (0.5 - (angle * 2.414 % 1.0))),
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: [
                            _kBrandTeal,
                            AppColors.coral,
                            AppColors.warning,
                            AppColors.superLike,
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
                      color: AppColors.greenBright,
                      boxShadow: [
                        BoxShadow(
                          color:
                              AppColors.greenBright.withValues(alpha: 0.35),
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
                    color: i < step ? _kBrandTeal : _kInputBorder,
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
            color: isDone || isActive ? _kBrandTeal : Colors.transparent,
            border: Border.all(
              color: isDone || isActive ? _kBrandTeal : _kInputBorder,
              width: 1.5,
            ),
            boxShadow: isDone || isActive
                ? [
                    BoxShadow(
                        color: _kBrandTeal.withValues(alpha: 0.26),
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
                        color: isActive ? Colors.white : AppColors.textDisabled,
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(height: 3),
        Text(label,
            style: TextStyle(
                color: isActive ? _kBrandTeal : AppColors.textDisabled,
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
    this.isDark = false,
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
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title
          Text(
            'יצירת חשבון',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: isDark ? Colors.white : AppColors.navy,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                shadows: const [
                  Shadow(
                    color: Color(0x40000000),
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ]),
          ),
          const SizedBox(height: 6),
          Text(
            'מלאו את שמכם המלא, אימייל וסיסמה כדי להירשם ולהתחיל.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: isDark ? Colors.white70 : AppColors.textSecondary,
                fontSize: 13,
                height: 1.3,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 18),

          // Social buttons
          _SocialRow(
            googleLoading: googleLoading,
            appleLoading: appleLoading,
            onGoogle: onGoogle,
            onApple: onApple,
            isDark: isDark,
          ),
          const SizedBox(height: 14),
          _OrDivider(isDark: isDark),
          const SizedBox(height: 14),

          // Name
          _FieldLabel(label: 'שם מלא', isDark: isDark),
          const SizedBox(height: 4),
          _CleanTextField(
            controller: nameCtrl,
            hint: 'שם ושם משפחה',
            textCapitalization: TextCapitalization.words,
            prefixIcon: IconsaxPlusLinear.user,
            isDark: isDark,
          ),
          const SizedBox(height: 12),

          // Email
          _FieldLabel(label: 'כתובת אימייל', isDark: isDark),
          const SizedBox(height: 4),
          _CleanTextField(
            controller: emailCtrl,
            hint: 'name@example.com',
            keyboardType: TextInputType.emailAddress,
            textDirection: TextDirection.ltr,
            prefixIcon: IconsaxPlusLinear.sms,
            isDark: isDark,
          ),
          const SizedBox(height: 12),

          // Password
          _FieldLabel(label: 'סיסמה', isDark: isDark),
          const SizedBox(height: 4),
          _CleanTextField(
            controller: passwordCtrl,
            obscureText: obscure,
            hint: '••••••••',
            prefixIcon: IconsaxPlusLinear.key,
            isDark: isDark,
            suffixIcon: EyeMorphIcon(
              isObscured: obscure,
              onTap: onToggleObscure,
              color: isDark ? Colors.white : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),

          // Terms toggle
          Row(
            children: [
              GestureDetector(
                onTap: onToggleTerms,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: agreedToTerms ? _kBrandTeal : Colors.transparent,
                    border: Border.all(
                      color: agreedToTerms ? _kBrandTeal : (isDark ? Colors.white.withOpacity(0.6) : _kInputBorder),
                      width: 1.5,
                    ),
                  ),
                  child: agreedToTerms
                      ? const Icon(Icons.check_rounded,
                          size: 12, color: Colors.white)
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(
                        fontSize: 13, color: isDark ? Colors.white : AppColors.textSecondary),
                    children: [
                      TextSpan(text: 'אני מסכים/ה ל'),
                      TextSpan(
                        text: 'תנאי השימוש',
                        style: TextStyle(
                            color: _kBrandTeal,
                            fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: ' ו'),
                      TextSpan(
                        text: 'מדיניות הפרטיות',
                        style: TextStyle(
                            color: _kBrandTeal,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
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
    this.isDark = false,
  });

  final TextEditingController nameCtrl;
  final String role;
  final int budget;
  final ValueChanged<double> onBudget;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final isTenant = role == 'tenant';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('תקציב השכירות שלך',
              style: TextStyle(
                  color: isDark ? Colors.white : AppColors.navy,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5)),
          const SizedBox(height: 6),
          Text(
              'הגדר את התקציב החודשי כדי שנוכל להתאים עבורך את הדירות הטובות ביותר.',
              style: TextStyle(
                  color: isDark ? Colors.white70 : AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 24),
          if (isTenant)
            _CompactBudgetPicker(budget: budget, onBudget: onBudget, isDark: isDark),
        ],
      ),
    );
  }
}

// ─── Compact Budget Picker ────────────────────────────────────────────────────

class _CompactBudgetPicker extends StatelessWidget {
  const _CompactBudgetPicker({required this.budget, required this.onBudget, this.isDark = false});
  final int budget;
  final ValueChanged<double> onBudget;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.08) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.15) : _kInputBorder),
        boxShadow: isDark
            ? const []
            : const [
                BoxShadow(
                    color: Color(0x0A072946), blurRadius: 8, offset: Offset(0, 2))
              ],
      ),
      child: Column(
        children: [
          Row(children: [
            Text('תקציב חודשי',
                style: TextStyle(
                    color: isDark ? Colors.white : AppColors.navy,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('₪${_fmt(budget)}',
                style: TextStyle(
                    color: _kBrandTeal,
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
              activeTrackColor: _kBrandTeal,
              inactiveTrackColor: isDark ? Colors.white.withOpacity(0.12) : AppColors.mist,
              thumbColor: _kBrandTeal,
              overlayColor: _kBrandTeal.withValues(alpha: 0.16),
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
                    color: AppColors.textSecondary.withValues(alpha: 0.75))),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
        child: loading
            ? const ShineDecorator(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white)),
              )
            : Text(label,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      ),
    );
  }
}

// ─── Field Label ──────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, this.isDark = false});
  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Text(label,
        style: TextStyle(
            color: isDark ? Colors.white : AppColors.navy, fontSize: 13, fontWeight: FontWeight.w700));
  }
}

// ─── Clean TextField ──────────────────────────────────────────────────────────

class _CleanTextField extends StatefulWidget {
  const _CleanTextField({
    this.controller,
    this.hint,
    this.keyboardType,
    this.textDirection,
    this.obscureText = false,
    this.suffixIcon,
    this.prefixIcon,
    this.textCapitalization = TextCapitalization.none,
    this.isDark = false,
  });

  final TextEditingController? controller;
  final String? hint;
  final TextInputType? keyboardType;
  final TextDirection? textDirection;
  final bool obscureText;
  final Widget? suffixIcon;
  final IconData? prefixIcon;
  final TextCapitalization textCapitalization;
  final bool isDark;

  @override
  State<_CleanTextField> createState() => _CleanTextFieldState();
}

class _CleanTextFieldState extends State<_CleanTextField> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(
        color: widget.isDark ? Colors.white.withOpacity(0.24) : AppColors.navy.withOpacity(0.08),
        width: 1.2,
      ),
    );

    return Focus(
      onFocusChange: (focused) {
        setState(() {
          _isFocused = focused;
        });
      },
      child: GlowFocusDecorator(
        isFocused: _isFocused,
        borderRadius: 16.0,
        glowColor: _kBrandTeal,
        child: TextField(
          controller: widget.controller,
          keyboardType: widget.keyboardType,
          textDirection: widget.textDirection,
          obscureText: widget.obscureText,
          textCapitalization: widget.textCapitalization,
          style: TextStyle(
              color: widget.isDark ? Colors.white : AppColors.navy, fontSize: 15, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: widget.prefixIcon != null
                ? Icon(widget.prefixIcon, color: widget.isDark ? Colors.white : AppColors.textSecondary.withOpacity(0.7), size: 20)
                : null,
            suffixIcon: widget.suffixIcon != null
                ? Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: widget.suffixIcon,
                  )
                : null,
            filled: true,
            fillColor: widget.isDark ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.65),
            hintStyle: TextStyle(
                color: widget.isDark ? Colors.white.withOpacity(0.45) : AppColors.textSecondary.withValues(alpha: 0.55),
                fontWeight: FontWeight.w400),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: border,
            enabledBorder: border,
            focusedBorder: border.copyWith(
              borderSide: BorderSide(color: _kBrandTeal, width: 1.8),
            ),
          ),
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
    this.isDark = false,
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
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: label, isDark: isDark),
        const SizedBox(height: 6),
        _CleanTextField(
          controller: controller,
          hint: hint,
          keyboardType: keyboardType,
          textDirection: textDirection,
          obscureText: obscureText,
          suffixIcon: suffixIcon,
          prefixIcon: icon,
          textCapitalization: textCapitalization,
          isDark: isDark,
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
    this.isDark = false,
  });

  final TextEditingController cityCtrl;
  final double rooms;
  final List<String> features;
  final ValueChanged<double> onRooms;
  final ValueChanged<String> onToggleFeature;
  final bool isDark;

  static const Map<String, IconData> _featureIcons = {
    'מרפסת': Icons.balcony_rounded,
    'חניה': Icons.local_parking_rounded,
    'מעלית': Icons.elevator_rounded,
    'מיזוג': Icons.ac_unit_rounded,
    'ממ"ד': Icons.security_rounded,
    'مחסן': Icons.warehouse_rounded,
    'גינה': Icons.yard_rounded,
    'ריהוט': Icons.chair_rounded,
    'מחמדים': Icons.pets_rounded,
    'אינטרנט': Icons.wifi_rounded,
  };

  static const _featureTags = [
    'מרפסת',
    'חניה',
    'מעלית',
    'מיזוג',
    'ממ"ד',
    'مחסן',
    'גינה',
    'ריהוט',
    'מחמדים',
    'אינטרנט',
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('פרטי הנכס',
                  style: TextStyle(
                      color: isDark ? Colors.white : AppColors.navy,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5)),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: _kBrandTeal.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('אופציונלי',
                    style: TextStyle(
                        color: _kBrandTeal,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('הגדר את מאפייני הדירה שלך כדי שנוכל לחבר אותך לשוכרים המתאימים ביותר.',
              style: TextStyle(
                  color: isDark ? Colors.white70 : AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 24),
          _AuthTextField(
            controller: cityCtrl,
            label: 'עיר / שכונה',
            icon: IconsaxPlusLinear.location,
            isDark: isDark,
          ),
          const SizedBox(height: 18),
          _RoomsStepper(rooms: rooms, onRooms: onRooms, isDark: isDark),
          const SizedBox(height: 22),
          Text('מה יש בנכס?',
              style: TextStyle(
                  color: isDark ? Colors.white : AppColors.navy,
                  fontSize: 14,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _featureTags
                .map((f) => _FeatureChip(
                      label: f,
                      selected: features.contains(f),
                      onTap: () => onToggleFeature(f),
                      icon: _featureIcons[f],
                      isDark: isDark,
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
  const _RoomsStepper({required this.rooms, required this.onRooms, this.isDark = false});
  final double rooms;
  final ValueChanged<double> onRooms;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final label = rooms % 1 == 0 ? rooms.toInt().toString() : '$rooms';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.08) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.15) : _kInputBorder),
      ),
      child: Row(children: [
        Text('מספר חדרים',
            style: TextStyle(
                color: isDark ? Colors.white : AppColors.navy,
                fontSize: 14,
                fontWeight: FontWeight.w700)),
        const Spacer(),
        _StepperBtn(
          icon: Icons.remove_rounded,
          onTap: () => onRooms((rooms - 0.5).clamp(1.0, 8.0)),
          filled: false,
          isDark: isDark,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(label,
              style: TextStyle(
                  color: _kBrandTeal,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5)),
        ),
        _StepperBtn(
          icon: Icons.add_rounded,
          onTap: () => onRooms((rooms + 0.5).clamp(1.0, 8.0)),
          filled: true,
          isDark: isDark,
        ),
      ]),
    );
  }
}

class _StepperBtn extends StatelessWidget {
  const _StepperBtn({
    required this.icon,
    required this.onTap,
    required this.filled,
    this.isDark = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final color = filled
        ? _kBrandTeal
        : (isDark ? Colors.white.withOpacity(0.12) : _kInputBorder.withValues(alpha: 0.6));
    final iconColor = filled
        ? Colors.white
        : (isDark ? Colors.white : AppColors.textSecondary);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
        child: Icon(icon, size: 16, color: iconColor),
      ),
    );
  }
}

// ─── Feature Chip ─────────────────────────────────────────────────────────────

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.isDark = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final chipBg = selected
        ? _kBrandTeal
        : (isDark ? Colors.white.withOpacity(0.08) : Colors.white);
    final borderCol = selected
        ? _kBrandTeal
        : (isDark ? Colors.white.withOpacity(0.15) : _kInputBorder);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: chipBg,
          border: Border.all(color: borderCol),
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: _kBrandTeal.withValues(alpha: 0.22),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: selected ? Colors.white : (isDark ? Colors.white70 : AppColors.textSecondary),
              ),
              const SizedBox(width: 5),
            ],
            if (selected) ...[
              const Icon(Icons.check_rounded, size: 12, color: Colors.white),
              const SizedBox(width: 5),
            ],
            Text(label,
                style: TextStyle(
                    color: selected ? Colors.white : (isDark ? Colors.white : AppColors.navy),
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
              style: TextStyle(
                  color: _kBrandTeal,
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

class _WelcomePortal extends StatelessWidget {
  final VoidCallback onLogin;
  final VoidCallback onGoogleLogin;
  final VoidCallback onAppleLogin;
  final VoidCallback onGuestLogin;
  final VoidCallback onLandlordCta;

  const _WelcomePortal({
    super.key,
    required this.onLogin,
    required this.onGoogleLogin,
    required this.onAppleLogin,
    required this.onGuestLogin,
    required this.onLandlordCta,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Immersive background image of modern villa
        Image.network(
          'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?q=80&w=1000',
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(color: AppColors.navy);
          },
          errorBuilder: (context, error, stackTrace) {
            return Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.navy, AppColors.slate900],
                ),
              ),
            );
          },
        ),

        // Bottom dark gradient overlay for text readability
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withOpacity(0.92),
                  Colors.black.withOpacity(0.45),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
        ),

        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Top logo / branding
                Align(
                  alignment: Alignment.center,
                  child: BreatheAnimation(
                    child: SvgPicture.asset(
                      'assets/images/rently_logo_with_text.svg',
                      height: 95,
                      colorFilter: const ColorFilter.mode(
                        Colors.white,
                        BlendMode.srcIn,
                      ),
                      placeholderBuilder: (_) => const Text(
                        'Rently',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 65,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                  ),
                ),
                const Spacer(),

                // Title Text (Hebrew, right-aligned)
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'מצאו את המקום\nהמושלם עבורכם',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                      shadows: [
                        Shadow(
                          color: Color(0x59000000),
                          blurRadius: 14,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Account-type Buttons (Tenant / Landlord)
                Row(
                  children: [
                    // Tenant Button (App Brand Primary Teal)
                    Expanded(
                      child: GestureDetector(
                        onTap: onLogin,
                        child: Container(
                          height: 56,
                          decoration: BoxDecoration(
                            color: _kBrandTeal,
                            borderRadius: BorderRadius.circular(28),
                          ),
                          alignment: Alignment.center,
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(IconsaxPlusLinear.search_normal,
                                  color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'מחפש דירה',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Landlord Button (Solid Navy)
                    Expanded(
                      child: GestureDetector(
                        onTap: onLandlordCta,
                        child: Container(
                          height: 56,
                          decoration: BoxDecoration(
                            color: AppColors.navy,
                            borderRadius: BorderRadius.circular(28),
                          ),
                          alignment: Alignment.center,
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(IconsaxPlusLinear.building,
                                  color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'בעל דירה',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Other Ways to sign in
                const Align(
                  alignment: Alignment.center,
                  child: Text(
                    'או התחברו באמצעות',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Social Row (Apple, Google) - No Facebook
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Apple Login Button
                    GestureDetector(
                      onTap: onAppleLogin,
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.12),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.15),
                            width: 1.5,
                          ),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.apple_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),

                    // Google Login Button
                    GestureDetector(
                      onTap: onGoogleLogin,
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.12),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.15),
                            width: 1.5,
                          ),
                        ),
                        child: const Center(
                          child: Text(
                            'G',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Guest Mode option
                Align(
                  alignment: Alignment.center,
                  child: TextButton(
                    onPressed: onGuestLogin,
                    child: const Text(
                      'המשך כאורח',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
