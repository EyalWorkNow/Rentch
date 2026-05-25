import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/services/google_auth_service.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

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
    if (mounted) {
      _onEnter();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 1040;

    return Scaffold(
      backgroundColor: AppColors.navy,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF031726), Color(0xFF072946), Color(0xFF0F5671)],
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
            padding: const EdgeInsets.fromLTRB(26, 20, 26, 16),
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
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SvgPicture.asset(
          'assets/images/rentch_logo_full.svg',
          height: 44,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          placeholderBuilder: (_) => const Text(
            'Rentch',
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
        ),
        const SizedBox(height: 16),
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
        const SizedBox(height: 16),
        Row(
          children: [
            _FeaturePill(
                icon: IconsaxPlusBold.building, label: 'דירות מותאמות'),
            const SizedBox(width: 10),
            _FeaturePill(icon: IconsaxPlusBold.heart, label: 'התאמה אישית'),
          ],
        ),
      ],
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
          height: 58,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          placeholderBuilder: (_) => const Text(
            'Rentch',
            style: TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.5,
            ),
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          'הדרך המהירה\nלמצוא את הבית הבא שלך.',
          style: TextStyle(
            color: Colors.white,
            fontSize: 44,
            height: 1.1,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.3,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Rentch מחבר שוכרים ומשכירים בחוויה חכמה, מהירה וברורה.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 17,
            height: 1.6,
            fontWeight: FontWeight.w500,
          ),
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
    return Column(
      children: const [
        _WideFeatureItem(
          icon: IconsaxPlusBold.building,
          title: 'גלילת דירות חכמה',
          subtitle: 'מציג רק את מה שמתאים לפרופיל שלך',
        ),
        SizedBox(height: 14),
        _WideFeatureItem(
          icon: IconsaxPlusBold.heart,
          title: 'התאמה דו-כיוונית',
          subtitle: 'שוכרים ומשכירים מאשרים זה את זה',
        ),
        SizedBox(height: 14),
        _WideFeatureItem(
          icon: IconsaxPlusBold.message,
          title: 'צ׳אט ישיר',
          subtitle: 'תקשורת ממוקדת בין הצדדים',
        ),
      ],
    );
  }
}

class _WideFeatureItem extends StatelessWidget {
  const _WideFeatureItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
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
        color: Colors.white,
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x30072946),
            blurRadius: 40,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag handle (mobile)
          if (!isWide) ...[
            const SizedBox(height: 12),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderLight,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 16),
          ] else
            const SizedBox(height: 28),

          // Tab selector
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isWide ? 28 : 20),
            child: _ModeTabs(controller: tabController),
          ),
          const SizedBox(height: 4),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: tabController,
              children: [
                _LoginTab(onLogin: onLogin, onGuestLogin: onGuestLogin),
                _RegisterFlow(onDone: onDone),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Backdrop Orbs ────────────────────────────────────────────────────────────

class _BackdropOrbs extends StatelessWidget {
  const _BackdropOrbs();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -40,
            child: _GlowOrb(
                size: 260, color: AppColors.primary.withValues(alpha: 0.20)),
          ),
          Positioned(
            left: -90,
            top: 140,
            child: _GlowOrb(
                size: 220, color: Colors.white.withValues(alpha: 0.08)),
          ),
          Positioned(
            bottom: -80,
            left: 40,
            child: _GlowOrb(
                size: 240, color: AppColors.coral.withValues(alpha: 0.14)),
          ),
          Positioned(
            bottom: 90,
            right: 80,
            child: _GlowOrb(
                size: 160, color: Colors.white.withValues(alpha: 0.05)),
          ),
        ],
      ),
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
        gradient: RadialGradient(
          colors: [
            color,
            color.withValues(alpha: color.a * 0.32),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

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
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: const [
            BoxShadow(
              color: Color(0x30072946),
              blurRadius: 30,
              offset: Offset(0, 16),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'המשך כאורח',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'בחרו האם להיכנס כבעל דירה או כדייר שמחפש דירה. אחרי הבחירה תראו מיד גם נתוני פרוקסי, מאצ׳ים ושיחות קיימות.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              _GuestRoleOption(
                title: 'אורח כדייר מחפש דירה',
                subtitle:
                    'דירות פעילות, משכירים שכבר מדברים איתך ומאצ׳ים פתוחים.',
                icon: IconsaxPlusBold.profile_circle,
                color: AppColors.primary,
                onTap: () => Navigator.of(context).pop('tenant'),
              ),
              const SizedBox(height: 12),
              _GuestRoleOption(
                title: 'אורח כבעל דירה',
                subtitle:
                    'נכסים פעילים, מועמדים בתהליך ושיחות קיימות עם שוכרים.',
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
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.borderLight),
          color: color.withValues(alpha: 0.06),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(IconsaxPlusLinear.arrow_left_2, color: color, size: 18),
          ],
        ),
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
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F7FA),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: TabBar(
        controller: controller,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelPadding: EdgeInsets.zero,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryDark],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x3313BEC9),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        labelColor: Colors.white,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        tabs: const [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.login_rounded, size: 17),
                SizedBox(width: 7),
                Text('כניסה'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_add_alt_1_rounded, size: 17),
                SizedBox(width: 7),
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
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _googleLoading = false;
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('יש למלא מספר טלפון')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('כניסה עם Google לא מופעלת בסביבת ההרצה הזו'),
        ),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _googleLoading = true);

    try {
      final result = await _googleAuthService.signIn();
      if (!mounted) return;
      final provider = context.read<DatingProvider>();
      await provider.applyGoogleIdentity(
        displayName: result.displayName,
        photoUrl: result.photoUrl,
      );
      await provider.setUserRole(provider.userRole);
      if (!mounted) return;
      widget.onLogin();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'כניסה עם Google לא הושלמה: $error',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _googleLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Greeting
          const Text(
            'ברוכים הבאים',
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              height: 1.1,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'הכנסו עם מספר הטלפון שלכם',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 26),

          // Fields
          _AuthTextField(
            controller: _phoneCtrl,
            label: 'מספר טלפון',
            hint: '05X-XXXXXXX',
            icon: IconsaxPlusLinear.call,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
          ),
          const SizedBox(height: 12),
          _AuthTextField(
            controller: _passwordCtrl,
            label: 'סיסמה',
            icon: IconsaxPlusLinear.lock,
            obscureText: _obscure,
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                color: AppColors.textSecondary,
                size: 20,
              ),
            ),
          ),
          const SizedBox(height: 26),

          // Primary CTA
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              onPressed: _loading ? null : _login,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
              ),
              icon: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white),
                    )
                  : const Icon(Icons.login_rounded, size: 20),
              label: Text(
                _loading ? 'מתחבר...' : 'כניסה לחשבון',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (AppConfig.enableGoogleSignIn) ...[
            SizedBox(
              height: 56,
              child: OutlinedButton.icon(
                onPressed: _googleLoading ? null : _loginWithGoogle,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.navy,
                  side: const BorderSide(color: AppColors.borderLight),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                icon: _googleLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: AppColors.navy,
                        ),
                      )
                    : const Icon(IconsaxPlusLinear.profile_circle, size: 18),
                label: const Text(
                  'כניסה עם Google',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Guest CTA
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: widget.onGuestLogin,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.navy,
                side: const BorderSide(color: AppColors.borderLight),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              icon: Icon(IconsaxPlusLinear.eye, size: 18),
              label: const Text(
                'המשך כאורח',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 22),

          // Demo notice
          Row(
            children: [
              Icon(
                IconsaxPlusLinear.shield_tick,
                size: 13,
                color: AppColors.textSecondary.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 6),
              Text(
                'זהו דמו — הנתונים נשמרים מקומית',
                style: TextStyle(
                  color: AppColors.textSecondary.withValues(alpha: 0.5),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
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
  final _phoneCtrl = TextEditingController();
  int _budget = 7000;
  double _rooms = 2;
  String _moveIn = 'גמיש';
  bool _loading = false;

  int get _totalSteps => _role == 'landlord' ? 2 : 3;

  @override
  void dispose() {
    _pageCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
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

    final isLast = (_role == 'landlord' && _step == 1) ||
        (_role == 'tenant' && _step == 2);

    if (isLast) {
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
                importantDetails: [],
              ))
          .copyWith(
        name: _nameCtrl.text.trim(),
        budgetMax: _budget,
        desiredRooms: _rooms,
        moveInWindow: _moveIn,
      ),
    );

    await provider.setUserRole(_role);
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) widget.onDone();
  }

  String get _nextLabel {
    final isLast = (_role == 'landlord' && _step == 1) ||
        (_role == 'tenant' && _step == 2);
    return isLast ? 'בואו נתחיל' : 'הבא';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Step progress
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: _StepDots(step: _step, total: _totalSteps),
        ),

        // Step pages
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
                phoneCtrl: _phoneCtrl,
                role: _role,
              ),
              if (_role != 'landlord')
                _StepPreferences(
                  budget: _budget,
                  rooms: _rooms,
                  moveIn: _moveIn,
                  onBudget: (v) =>
                      setState(() => _budget = (v / 100).round() * 100),
                  onRooms: (v) => setState(() => _rooms = (v * 2).round() / 2),
                  onMoveIn: (v) => setState(() => _moveIn = v),
                ),
            ],
          ),
        ),

        // Nav buttons
        Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            14 + MediaQuery.of(context).padding.bottom,
          ),
          child: _NavButtons(
            step: _step,
            nextLabel: _nextLabel,
            loading: _loading,
            onPrev: _step > 0 ? _prev : null,
            onNext: _next,
          ),
        ),
      ],
    );
  }
}

// ─── Step Dots ────────────────────────────────────────────────────────────────

class _StepDots extends StatelessWidget {
  const _StepDots({required this.step, required this.total});

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              height: 5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: i <= step ? AppColors.primary : AppColors.borderLight,
              ),
            ),
          ),
        ],
        const SizedBox(width: 12),
        Text(
          '${step + 1}/$total',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'מה מביא אותך לכאן?',
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'בחרו מסלול כדי שנוכל להתאים את החוויה',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
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
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: selected ? accent : Colors.white,
          border: Border.all(
            color: selected ? accent : AppColors.borderLight,
            width: selected ? 0 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color:
                  selected ? accent.withValues(alpha: 0.25) : AppColors.shadow,
              blurRadius: selected ? 20 : 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.18)
                    : accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                color: selected ? Colors.white : accent,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: selected ? Colors.white : AppColors.navy,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: selected
                          ? Colors.white.withValues(alpha: 0.75)
                          : AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white
                    : AppColors.borderLight.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(
                selected ? Icons.check_rounded : Icons.circle_outlined,
                size: 14,
                color: selected ? accent : AppColors.textDisabled,
              ),
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
    required this.phoneCtrl,
    required this.role,
  });

  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final String role;

  @override
  Widget build(BuildContext context) {
    final isLandlord = role == 'landlord';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'פרטים אישיים',
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isLandlord
                ? 'הפרטים יופיעו על הנכסים שלכם'
                : 'בעלי הדירות יוכלו להכיר אתכם',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 22),
          _AuthTextField(
            controller: nameCtrl,
            label: 'שם מלא',
            icon: IconsaxPlusLinear.user,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          _AuthTextField(
            controller: phoneCtrl,
            label: 'מספר טלפון',
            hint: '05X-XXXXXXX',
            icon: IconsaxPlusLinear.call,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
          ),
        ],
      ),
    );
  }
}

// ─── Step: Preferences ───────────────────────────────────────────────────────

class _StepPreferences extends StatelessWidget {
  const _StepPreferences({
    required this.budget,
    required this.rooms,
    required this.moveIn,
    required this.onBudget,
    required this.onRooms,
    required this.onMoveIn,
  });

  final int budget;
  final double rooms;
  final String moveIn;
  final ValueChanged<double> onBudget;
  final ValueChanged<double> onRooms;
  final ValueChanged<String> onMoveIn;

  static const _moveInOptions = [
    'מיידי',
    'תוך חודש',
    '1-3 חודשים',
    '3-6 חודשים',
    'גמיש',
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'העדפות חיפוש',
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'אפשר לשנות הכל מאוחר יותר',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),
          _PreferenceCard(
            label: 'תקציב מקסימלי',
            value: '₪${_fmt(budget)}',
            child: _PreferenceSlider(
              value: budget.toDouble().clamp(2000, 20000),
              min: 2000,
              max: 20000,
              divisions: 180,
              onChanged: onBudget,
            ),
          ),
          const SizedBox(height: 12),
          _PreferenceCard(
            label: 'מספר חדרים',
            value: rooms % 1 == 0 ? rooms.toInt().toString() : '$rooms',
            child: _PreferenceSlider(
              value: rooms.clamp(1, 6),
              min: 1,
              max: 6,
              divisions: 10,
              onChanged: onRooms,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'מועד כניסה',
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _moveInOptions.map((opt) {
              final sel = opt == moveIn;
              return GestureDetector(
                onTap: () => onMoveIn(opt),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: sel ? AppColors.primary : Colors.white,
                    border: Border.all(
                      color: sel ? AppColors.primary : AppColors.borderLight,
                    ),
                    boxShadow: sel
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.22),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ]
                        : [],
                  ),
                  child: Text(
                    opt,
                    style: TextStyle(
                      color: sel ? Colors.white : AppColors.navy,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ─── Nav Buttons ─────────────────────────────────────────────────────────────

class _NavButtons extends StatelessWidget {
  const _NavButtons({
    required this.step,
    required this.nextLabel,
    required this.loading,
    required this.onPrev,
    required this.onNext,
  });

  final int step;
  final String nextLabel;
  final bool loading;
  final VoidCallback? onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onPrev != null) ...[
          SizedBox(
            height: 54,
            width: 54,
            child: OutlinedButton(
              onPressed: onPrev,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.navy,
                side: const BorderSide(color: AppColors.borderLight),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: loading ? null : onNext,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              icon: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.3, color: Colors.white),
                    )
                  : const Icon(Icons.arrow_back_ios_rounded, size: 16),
              label: Text(
                nextLabel,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
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
      borderRadius: BorderRadius.circular(18),
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
        fillColor: const Color(0xFFF8FBFD),
        labelStyle: const TextStyle(
            color: AppColors.textSecondary, fontWeight: FontWeight.w600),
        hintStyle: TextStyle(
            color: AppColors.textSecondary.withValues(alpha: 0.7),
            fontWeight: FontWeight.w500),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 58, minHeight: 56),
        prefixIcon: Padding(
          padding: const EdgeInsets.all(10),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 17),
          ),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
      ),
    );
  }
}

// ─── Preference Widgets ───────────────────────────────────────────────────────

class _PreferenceCard extends StatelessWidget {
  const _PreferenceCard({
    required this.label,
    required this.value,
    required this.child,
  });

  final String label;
  final String value;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFD),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 14,
                        fontWeight: FontWeight.w800)),
              ),
              Text(value,
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _PreferenceSlider extends StatelessWidget {
  const _PreferenceSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 5,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: const Color(0xFFD0EDF0),
        overlayColor: AppColors.primary.withValues(alpha: 0.18),
      ),
      child: Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        onChanged: onChanged,
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
