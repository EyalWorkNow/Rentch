import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/constants/brand_palette.dart';
import 'package:dating_app/core/services/google_auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dating_app/data/models/broker_design_models.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/features/user/profile/edit_profile_screen.dart';
import 'package:dating_app/presentation/screens/add_property_screen.dart';
import 'package:dating_app/presentation/screens/auth_screen.dart';
import 'package:dating_app/presentation/screens/landlord_properties_screen.dart';
import 'package:dating_app/presentation/screens/matches_screen.dart';
import 'package:dating_app/presentation/screens/message_screen.dart';
import 'package:dating_app/presentation/widgets/safe_image.dart';
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:dating_app/presentation/widgets/scale_bounce.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dating_app/presentation/widgets/rently_icon.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dating_app/presentation/widgets/animations/micro_animations.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('מחיקת חשבון',
            style:
                TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900)),
        content: const Text(
          'פעולה זו תמחק לצמיתות את החשבון ואת כל הנתונים שלך. לא ניתן לבטל פעולה זו.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('מחק חשבון'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;
    final provider = context.read<DatingProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // deleteAccount() removes the Firebase Auth credential itself, so it must run
    // while the user is still signed in (do NOT sign out first).
    try {
      await provider.deleteAccount();
    } on ReauthRequiredException catch (e) {
      // Email/password account: ask for the password inline and complete the
      // deletion in-flow, instead of bouncing the user back to the login screen.
      if (e.needsPassword) {
        if (!context.mounted) return;
        final password = await _promptDeletePassword(context);
        if (password == null || password.isEmpty) return; // cancelled — stay
        try {
          await provider.deleteAccount(reauthPassword: password);
        } on ReauthRequiredException {
          messenger.showSnackBar(const SnackBar(
            content: Text('הסיסמה שגויה. נסו שוב למחוק את החשבון.'),
          ));
          return;
        } catch (_) {}
        if (!context.mounted) return;
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthScreen()),
          (_) => false,
        );
        return;
      }
      // OAuth (Google/Apple): re-login then retry.
      messenger.showSnackBar(const SnackBar(
        duration: Duration(milliseconds: 3500),
        content: Text(
            'מטעמי אבטחה יש להתחבר מחדש ולאחר מכן למחוק את החשבון.'),
      ));
      try {
        await GoogleAuthService().signOut();
      } catch (_) {}
      if (!context.mounted) return;
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (_) => false,
      );
      return;
    } catch (_) {}

    if (!context.mounted) return;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  /// Inline password prompt used when Firebase requires a fresh login before
  /// deleting an email/password account. Returns the entered password, or null
  /// if the user cancels.
  Future<String?> _promptDeletePassword(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('אישור מחיקה',
            style:
                TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'מטעמי אבטחה הזינו את הסיסמה כדי להשלים את מחיקת החשבון.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                hintText: 'סיסמה',
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.borderLight),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ביטול',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('מחק חשבון'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('יציאה מהחשבון',
            style:
                TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900)),
        content: const Text(
          'האם אתה בטוח שברצונך לצאת?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.coral,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('יציאה'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;
    final provider = context.read<DatingProvider>();
    final navigator = Navigator.of(context);

    try {
      await GoogleAuthService().signOut();
    } catch (_) {}
    await provider.logout();

    if (!context.mounted) return;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DatingProvider>(
      builder: (context, provider, _) {
        final profile = provider.tenantProfile;
        if (provider.isLoading || profile == null) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
                child: CircularProgressIndicator(color: AppColors.primary)),
          );
        }

        if (provider.isLandlord) {
          return _LandlordProfileScreen(
            profile: profile,
            provider: provider,
            onLogout: () => _confirmLogout(context),
            onDeleteAccount: () => _confirmDeleteAccount(context),
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFFF1F5F9),
                  Color(0xFFF8FAFC),
                  Color(0xFFE6F9FB), // light teal instead of pink
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 130),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Bar Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'הפרופיל שלי',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              const RentlyIcon(
                                IconsaxPlusLinear.notification,
                                color: Color(0xFF0F172A),
                                size: 20,
                              ),
                              Positioned(
                                top: 12,
                                right: 12,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary, // App primary color instead of pink
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Avatar area (Mockup Style)
                    Center(
                      child: Column(
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              // Teal outer circle ring
                              Container(
                                width: 253,
                                height: 253,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [
                                      AppColors.primary,
                                      AppColors.primary.withValues(alpha: 0.3),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                              ),
                              // White inner ring
                              Container(
                                width: 239,
                                height: 239,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              // Actual profile picture
                              ClipOval(
                                child: SizedBox(
                                  width: 220,
                                  height: 220,
                                  child: profile.photoUrl.isNotEmpty
                                      ? (profile.photoUrl.startsWith('/')
                                          ? Image.file(File(profile.photoUrl),
                                              fit: BoxFit.cover)
                                          : Image.network(profile.photoUrl,
                                              fit: BoxFit.cover))
                                      : Container(
                                          color: const Color(0xFFE2E8F0),
                                          child: const RentlyIcon(
                                            IconsaxPlusLinear.user,
                                            size: 100,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                ),
                              ),
                              // Checked teal badge overlay
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary, // App primary color instead of pink
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 3.5),
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            Colors.black.withValues(alpha: 0.1),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                profile.name,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                key: const Key('profile_edit_button'),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        EditProfileScreen(profile: profile),
                                  ),
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: const RentlyIcon(
                                    IconsaxPlusLinear.edit_2,
                                    size: 14,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'שוכר',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Profile Completion progress card (Mockup Style)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'שלמות הפרופיל שלי',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              Text(
                                '${provider.profileCompletion}%',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: provider.profileCompletion / 100,
                              minHeight: 10,
                              backgroundColor: const Color(0xFFF1F5F9),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFF0F172A),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Stats bar (Mockup Style individual boxes)
                    Row(
                      children: [
                        Expanded(
                          child: _MockupStatBox(
                            count: provider.likesCount.toString(),
                            label: 'אהבתי',
                            icon: IconsaxPlusBold.heart,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _MockupStatBox(
                            count: provider.matchesCount.toString(),
                            label: 'התאמות',
                            icon: IconsaxPlusBold.messages_2,
                            color: AppColors.coral,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _MockupStatBox(
                            count: provider.passedCount.toString(),
                            label: 'דילגתי',
                            icon: Icons.close_rounded,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Search Preferences Grouped Container
                    const Text(
                      'הגדרות',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _PreferenceTile(
                            icon: IconsaxPlusLinear.money,
                            label: 'תקציב מקסימלי',
                            value: _fmt(profile.budgetMax),
                          ),
                          const _SettingsDivider(),
                          _PreferenceTile(
                            icon: IconsaxPlusLinear.building,
                            label: 'מספר חדרים',
                            value: '${profile.desiredRooms} חדרים',
                          ),
                          const _SettingsDivider(),
                          _PreferenceTile(
                            icon: IconsaxPlusLinear.calendar,
                            label: 'מועד כניסה',
                            value: profile.moveInWindow,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // About me
                    if (profile.bio.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                RentlyIcon(IconsaxPlusLinear.user,
                                    size: 18, color: Color(0xFF64748B)),
                                SizedBox(width: 8),
                                Text(
                                  'עליי',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              profile.bio,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF475569),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Actions Container
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          _ActionRow(
                            icon: IconsaxPlusLinear.logout,
                            label: 'יציאה מהחשבון',
                            onTap: () => _confirmLogout(context),
                            isDestructive: true,
                          ),
                          const _SettingsDivider(),
                          // Account deletion (App Store 5.1.1(v)) — the demo
                          // account is a tenant, so it MUST appear here too.
                          // Understated (normal dark row, not a loud CTA).
                          _ActionRow(
                            icon: IconsaxPlusLinear.trash,
                            label: 'מחיקת חשבון',
                            onTap: () => _confirmDeleteAccount(context),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Sliver header
// ---------------------------------------------------------------------------

class _ProfileSliverHeader extends StatefulWidget {
  const _ProfileSliverHeader({
    required this.profile,
    required this.profileCompletion,
    required this.onEdit,
  });

  final TenantProfile profile;
  final int profileCompletion;
  final VoidCallback onEdit;

  @override
  State<_ProfileSliverHeader> createState() => _ProfileSliverHeaderState();
}

class _ProfileSliverHeaderState extends State<_ProfileSliverHeader> {
  int _currentPage = 0;
  final _pageCtrl = PageController();

  @override
  void didUpdateWidget(covariant _ProfileSliverHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextPage = oldWidget.profile.id == widget.profile.id
        ? _safePhotoIndex(_currentPage)
        : 0;
    if (nextPage != _currentPage || oldWidget.profile.id != widget.profile.id) {
      _currentPage = nextPage;
      _jumpToCurrentPageAfterBuild();
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  int _safePhotoIndex(int index) {
    final photoCount = widget.profile.photoUrls.length;
    if (photoCount <= 0) return 0;
    return index.clamp(0, photoCount - 1).toInt();
  }

  void _jumpToCurrentPageAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageCtrl.hasClients) return;
      _pageCtrl.jumpToPage(_safePhotoIndex(_currentPage));
    });
  }

  /// Pick the first meaningful badge detail from importantDetails.
  String? _badgeDetail(List<String> details) {
    if (details.isEmpty) return null;
    return details.first;
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final photos = profile.photoUrls;
    final badge = _badgeDetail(profile.importantDetails);
    final safeCurrentPage = _safePhotoIndex(_currentPage);

    return SliverAppBar(
      expandedHeight: 340,
      pinned: false,
      automaticallyImplyLeading: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
      title: const Text('הפרופיל שלי'),
      actions: [
        TextButton.icon(
          onPressed: widget.onEdit,
          icon: const RentlyIcon(IconsaxPlusLinear.edit,
              color: Colors.white, size: 16),
          label: const Text(
            'עריכה',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          style: TextButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        const SizedBox(width: 12),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Photo carousel (or fallback)
            photos.isEmpty
                ? Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.navy, Color(0xFF0D3D60)],
                      ),
                    ),
                  )
                : PageView.builder(
                    controller: _pageCtrl,
                    itemCount: photos.length,
                    onPageChanged: (i) => setState(() => _currentPage = i),
                    itemBuilder: (_, i) => _ProfileImageCell(url: photos[i]),
                  ),

            // Invisible tap zones for gallery navigation
            if (photos.length > 1)
              Positioned.fill(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () {
                            if (safeCurrentPage > 0) {
                              _pageCtrl.previousPage(
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeInOut,
                              );
                            }
                          },
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () {
                            if (safeCurrentPage < photos.length - 1) {
                              _pageCtrl.nextPage(
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeInOut,
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Gradient overlay
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xEE072946), Colors.transparent],
                    stops: [0.0, 0.65],
                  ),
                ),
              ),
            ),

            // Photo dots
            if (photos.length > 1)
              Positioned(
                bottom: 88,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(photos.length, (i) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: safeCurrentPage == i ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: safeCurrentPage == i
                              ? AppColors.primary
                              : Colors.white.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      );
                    }),
                  ),
                ),
              ),

            // Name, avatar, budget
            Positioned(
              bottom: 20,
              right: 20,
              left: 20,
              child: IgnorePointer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar with white border + completion mini chart
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AvatarPulseRing(
                          active: true,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                            child: CircleAvatar(
                              radius: 36,
                              backgroundColor: AppColors.primary,
                              backgroundImage: profile.photoUrl.isNotEmpty &&
                                      !profile.photoUrl.startsWith('/')
                                  ? NetworkImage(profile.photoUrl)
                                  : null,
                              foregroundImage: profile.photoUrl.startsWith('/')
                                  ? FileImage(File(profile.photoUrl))
                                  : null,
                              child: profile.photoUrl.isEmpty
                                  ? const RentlyIcon(
                                      IconsaxPlusLinear.profile_circle,
                                      color: Colors.white,
                                      size: 34)
                                  : null,
                            ),
                          ),
                        ),
                        if (widget.profileCompletion < 100)
                          Positioned(
                            bottom: -5,
                            left: -5,
                            child: _MiniCompletion(
                                percent: widget.profileCompletion),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      profile.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          badge,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const RentlyIcon(IconsaxPlusLinear.money,
                            size: 14, color: Colors.white60),
                        const SizedBox(width: 5),
                        Text(
                          'תקציב עד ${_fmt(profile.budgetMax)} • ${profile.desiredRooms} חדרים',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile image cell
// ---------------------------------------------------------------------------

class _ProfileImageCell extends StatelessWidget {
  const _ProfileImageCell({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return _fallback();
    if (url.startsWith('/') || url.startsWith('file://')) {
      final path = url.startsWith('file://') ? url.substring(7) : url;
      return Image.file(File(path),
          fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallback());
    }
    return Image.network(url,
        fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallback());
  }

  Widget _fallback() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.navy, Color(0xFF0D3D60)],
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Stats bar
// ---------------------------------------------------------------------------

class _StatsBar extends StatelessWidget {
  const _StatsBar({
    required this.likes,
    required this.matches,
    required this.passed,
  });

  final int likes;
  final int matches;
  final int passed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _StatBarItem(
              icon: IconsaxPlusLinear.heart,
              color: AppColors.primary,
              value: likes.toString(),
              label: 'אהבתי',
              isFirst: true,
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: AppColors.borderLight,
            ),
            _StatBarItem(
              icon: IconsaxPlusLinear.message,
              color: const Color(0xFF4A6CF7),
              value: matches.toString(),
              label: 'התאמות',
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: AppColors.borderLight,
            ),
            _StatBarItem(
              icon: IconsaxPlusLinear.close_circle,
              color: AppColors.coral,
              value: passed.toString(),
              label: 'דילגתי',
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatBarItem extends StatelessWidget {
  const _StatBarItem({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    this.isFirst = false,
    this.isLast = false,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.04),
          borderRadius: BorderRadius.horizontal(
            left: isLast ? const Radius.circular(20) : Radius.zero,
            right: isFirst ? const Radius.circular(20) : Radius.zero,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section card
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 12, offset: Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: AppColors.primary),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Preference row
// ---------------------------------------------------------------------------

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Divider
// ---------------------------------------------------------------------------

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, thickness: 1, color: AppColors.borderLight);
  }
}

// ---------------------------------------------------------------------------
// Review card
// ---------------------------------------------------------------------------

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});
  final AppReview review;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const RentlyIcon(IconsaxPlusLinear.star_1,
                  color: Color(0xFFE8A84A), size: 15),
              const SizedBox(width: 5),
              Text(
                '${review.rating}/5',
                style: const TextStyle(
                    fontWeight: FontWeight.w900, color: AppColors.navy),
              ),
              const SizedBox(width: 8),
              Text(
                review.authorName,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            review.text,
            style: const TextStyle(
                color: AppColors.textSecondary, height: 1.4, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Action tile
// ---------------------------------------------------------------------------

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? AppColors.coral : AppColors.navy;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: color,
                  ),
                ),
              ),
              RentlyIcon(
                IconsaxPlusLinear.arrow_left,
                size: 16,
                color: AppColors.textSecondary.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mini completion chart
// ---------------------------------------------------------------------------

class _MiniCompletion extends StatelessWidget {
  const _MiniCompletion({required this.percent});
  final int percent;

  @override
  Widget build(BuildContext context) {
    final color = percent >= 80
        ? const Color(0xFF27AE60)
        : percent >= 50
            ? AppColors.primary
            : const Color(0xFFF39C12);
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              value: percent / 100,
              strokeWidth: 3,
              backgroundColor: AppColors.borderLight,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          Text(
            '$percent',
            style: const TextStyle(
              fontSize: 7,
              fontWeight: FontWeight.w900,
              color: AppColors.navy,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _fmt(int value) {
  final raw = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final remaining = raw.length - i;
    buffer.write(raw[i]);
    if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
  }
  return '₪$buffer';
}

// ===========================================================================
// LANDLORD PROFILE — full redesign
// ===========================================================================

class _LandlordProfileScreen extends StatelessWidget {
  const _LandlordProfileScreen({
    required this.profile,
    required this.provider,
    required this.onLogout,
    required this.onDeleteAccount,
  });

  final TenantProfile profile;
  final DatingProvider provider;
  final VoidCallback onLogout;
  final VoidCallback onDeleteAccount;

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}';
    return name.isNotEmpty ? name[0] : '?';
  }

  Widget _buildHeader(BuildContext context) {
    return const Center(
      child: Text(
        'פרופיל',
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildProfileCard(
      BuildContext context, String tenantName, String email, String photoUrl) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2), width: 2),
            ),
            child: ClipOval(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    child: Center(
                      child: Text(
                        _initials(tenantName),
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  if (photoUrl.isNotEmpty)
                    (photoUrl.startsWith('/')
                        ? Image.file(File(photoUrl), fit: BoxFit.cover)
                        : Image.network(photoUrl, fit: BoxFit.cover)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tenantName,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (provider.isBroker) ...[
                  const SizedBox(height: 5),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: BrandPalette.broker.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(IconsaxPlusLinear.briefcase,
                            size: 12, color: BrandPalette.broker.primary),
                        const SizedBox(width: 4),
                        Text(
                          'מתווך נדל״ן',
                          style: TextStyle(
                            color: BrandPalette.broker.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  email,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => EditProfileScreen(profile: profile)),
            ),
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFFF5F7FA),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: RentlyIcon(
                  IconsaxPlusLinear.edit_2,
                  color: AppColors.textPrimary,
                  size: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'שדרג ל-PRO',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.textPrimary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'PRO',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'שדרג לגרסת הפרו של Rently לקבלת נתונים חיים עשירים יותר, התאמות ללא הגבלה ועוד פיצ\'רים מתקדמים.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    duration: Duration(milliseconds: 2500),
                    content: Text('תכונה זו תהיה זמינה בקרוב!'),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.star, color: Colors.white, size: 18),
              label: const Text(
                'שדרג עכשיו',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsGroup(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          _ProfileMenuItem(
            icon: IconsaxPlusLinear.user,
            label: 'פרטי חשבון',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => EditProfileScreen(profile: profile)),
            ),
          ),
          if (provider.isBroker) ...[
            const _SettingsDivider(),
            _ProfileMenuItem(
              icon: IconsaxPlusLinear.color_swatch,
              label: 'מיתוג ותבניות',
              color: BrandPalette.broker.primary,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const BrokerBrandingScreen(),
                ),
              ),
            ),
          ],
          const _SettingsDivider(),
          _ProfileMenuItem(
            icon: IconsaxPlusLinear.setting_2,
            label: 'הגדרות',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _SettingsSubPage(
                    title: 'הגדרות',
                    items: [
                      const _SubPageSettingItem(
                        icon: IconsaxPlusLinear.notification,
                        title: 'התראות בנייד',
                        subtitle: 'קבל עדכונים בזמן אמת על מכשירך',
                        isSwitch: true,
                      ),
                      const _SubPageSettingItem(
                        icon: IconsaxPlusLinear.sms,
                        title: 'התראות אימייל',
                        subtitle: 'קבל סיכומים שבועיים ועדכוני מערכת',
                        isSwitch: true,
                      ),
                      const _SubPageSettingItem(
                        icon: IconsaxPlusLinear.user_add,
                        title: 'פניות שוכרים',
                        subtitle: 'התראות על התאמות ולידים חדשים',
                        isSwitch: true,
                      ),
                      _SubPageSettingItem(
                        icon: IconsaxPlusLinear.trash,
                        title: 'מחיקת חשבון',
                        subtitle: 'מחק את החשבון והמידע שלך לצמיתות',
                        color: Colors.red.shade700,
                        onTap: onDeleteAccount,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const _SettingsDivider(),
          _ProfileMenuItem(
            icon: IconsaxPlusLinear.security_safe,
            label: 'אבטחת חשבון',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const _SettingsSubPage(
                    title: 'אבטחת חשבון',
                    items: [
                      _SubPageSettingItem(
                        icon: IconsaxPlusLinear.key,
                        title: 'שינוי סיסמה',
                        subtitle: 'עדכן את סיסמת הכניסה לחשבון',
                      ),
                      _SubPageSettingItem(
                        icon: IconsaxPlusLinear.finger_scan,
                        title: 'זיהוי ביומטרי',
                        subtitle: 'התחברות מהירה באמצעות טביעת אצבע או פנים',
                        isSwitch: true,
                      ),
                      _SubPageSettingItem(
                        icon: IconsaxPlusLinear.monitor_mobbile,
                        title: 'מכשירים מחוברים',
                        subtitle: 'נהל את המכשירים המחוברים לחשבונך',
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const _SettingsDivider(),
          _ProfileMenuItem(
            icon: IconsaxPlusLinear.info_circle,
            label: 'תמיכה ועזרה',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _SettingsSubPage(
                    title: 'תמיכה ועזרה',
                    items: [
                      _SubPageSettingItem(
                        icon: IconsaxPlusLinear.message_question,
                        title: 'מרכז עזרה ומדריכים',
                        subtitle: 'שאלות נפוצות ומאמרי תמיכה',
                        onTap: () => launchUrl(
                          Uri.parse('https://rently.app/help'),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                      _SubPageSettingItem(
                        icon: IconsaxPlusLinear.call_calling,
                        title: 'צור קשר עם התמיכה',
                        subtitle: 'אנחנו כאן לעזור 24/7',
                        onTap: () => launchUrl(
                          Uri.parse('mailto:support@rently.app'),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                      _SubPageSettingItem(
                        icon: IconsaxPlusLinear.document_text,
                        title: 'תנאי שימוש ומדיניות',
                        subtitle: 'הסכם שימוש ושמירה על פרטיות',
                        onTap: () => launchUrl(
                          Uri.parse('https://rently.app/privacy'),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSystemActions(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          _ProfileMenuItem(
            icon: IconsaxPlusLinear.logout,
            label: 'יציאה מהחשבון',
            color: AppColors.coral,
            onTap: onLogout,
          ),
          const _SettingsDivider(),
          // Account deletion (App Store Guideline 5.1.1(v)). Kept here next to
          // logout — a normal, discoverable menu row in muted grey rather than a
          // loud red CTA — so a reviewer finds it immediately without it
          // dominating the profile.
          _ProfileMenuItem(
            icon: IconsaxPlusLinear.trash,
            label: 'מחיקת חשבון',
            color: AppColors.textSecondary,
            onTap: onDeleteAccount,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tenantName = profile.name.isNotEmpty ? profile.name : 'בעל דירה';
    String email = '';
    try {
      email = FirebaseAuth.instance.currentUser?.email ?? '';
    } catch (_) {}
    if (email.isEmpty) email = 'לא מחובר';
    final photoUrl = profile.photoUrl;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 24),
              _buildProfileCard(context, tenantName, email, photoUrl),
              const SizedBox(height: 20),
              _buildProBanner(context),
              const SizedBox(height: 20),
              _buildSettingsGroup(context),
              const SizedBox(height: 20),
              _buildSystemActions(context),
              const SizedBox(height: 120),
            ],
          ),
        ),
      ),
    );
  }
}

class BrokerBrandingScreen extends StatefulWidget {
  const BrokerBrandingScreen({super.key});

  @override
  State<BrokerBrandingScreen> createState() => _BrokerBrandingScreenState();
}

class _BrokerBrandingScreenState extends State<BrokerBrandingScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _detectingLogoColors = false;

  Future<void> _pickLogo(DatingProvider provider) async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (file == null || !mounted) return;

      setState(() => _detectingLogoColors = true);
      final detected = await _detectPalette(file);
      if (!mounted) return;

      final current = provider.brokerBranding;
      await provider.updateBrokerBranding(
        current.copyWith(
          logoPath: file.path,
          primaryColorValue: detected?.primary,
          secondaryColorValue: detected?.secondary,
          accentColorValue: detected?.accent,
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            detected == null
                ? 'הלוגו נוסף. לא זוהו צבעים ברורים, אפשר לבחור פלטה ידנית.'
                : 'הלוגו נוסף והצבעים זוהו מהתמונה.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('לא ניתן לקרוא את קובץ הלוגו.')),
      );
    } finally {
      if (mounted) setState(() => _detectingLogoColors = false);
    }
  }

  Future<void> _removeLogo(DatingProvider provider) async {
    await provider.updateBrokerBranding(
      provider.brokerBranding.copyWith(logoPath: ''),
    );
  }

  Future<_DetectedLogoPalette?> _detectPalette(XFile file) async {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 64,
      targetHeight: 64,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (byteData == null) return null;

    final buckets = <int, int>{};
    final data = byteData.buffer.asUint8List();
    for (var i = 0; i + 3 < data.length; i += 16) {
      final r = data[i];
      final g = data[i + 1];
      final b = data[i + 2];
      final a = data[i + 3];
      if (a < 180) continue;
      final color = Color.fromARGB(255, r, g, b);
      final hsl = HSLColor.fromColor(color);
      if (hsl.lightness < 0.14 ||
          hsl.lightness > 0.92 ||
          hsl.saturation < 0.12) {
        continue;
      }
      final bucket = Color.fromARGB(
        255,
        (r ~/ 32) * 32,
        (g ~/ 32) * 32,
        (b ~/ 32) * 32,
      ).value;
      buckets[bucket] = (buckets[bucket] ?? 0) + 1;
    }

    final ranked = buckets.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (ranked.isEmpty) return null;

    final selected = <Color>[];
    for (final entry in ranked) {
      final color = Color(entry.key);
      if (selected.every((existing) => _colorDistance(existing, color) > 74)) {
        selected.add(color);
      }
      if (selected.length == 3) break;
    }
    if (selected.isEmpty) return null;

    final primary = selected.first;
    final secondary =
        selected.length > 1 ? selected[1] : _readablePairFor(primary);
    final accent = selected.length > 2
        ? selected[2]
        : HSLColor.fromColor(primary)
            .withLightness(0.72)
            .withSaturation(0.88)
            .toColor();
    return _DetectedLogoPalette(
      primary: primary.value,
      secondary: secondary.value,
      accent: accent.value,
    );
  }

  double _colorDistance(Color a, Color b) {
    final dr = a.red - b.red;
    final dg = a.green - b.green;
    final db = a.blue - b.blue;
    return (dr * dr + dg * dg + db * db).toDouble();
  }

  Color _readablePairFor(Color color) {
    final hsl = HSLColor.fromColor(color);
    if (hsl.lightness > 0.55) {
      return hsl.withLightness(0.18).withSaturation(0.40).toColor();
    }
    return hsl.withLightness(0.86).withSaturation(0.28).toColor();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DatingProvider>(
      builder: (context, provider, _) {
        if (!provider.isBroker) {
          return Scaffold(
            backgroundColor: const Color(0xFFF5F7FA),
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'מיתוג ותבניות זמינים לחשבון מתווך נדל״ן בלבד.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        final branding = provider.brokerBranding;
        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
          body: SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BrokerBrandingHeader(
                    onBack: () => Navigator.of(context).pop(),
                    onReset: () => provider.updateBrokerBranding(
                      BrokerBrandingConfig.defaults,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _BrokerBrandPreview(branding: branding),
                  const SizedBox(height: 16),
                  _BrokerLogoCard(
                    branding: branding,
                    detecting: _detectingLogoColors,
                    onPick: () => _pickLogo(provider),
                    onRemove:
                        branding.hasLogo ? () => _removeLogo(provider) : null,
                  ),
                  const SizedBox(height: 16),
                  _BrandingSectionShell(
                    title: 'עמוד דירה',
                    child: Column(
                      children: BrokerPropertyTemplate.values
                          .map(
                            (template) => _BrokerPropertyTemplateTile(
                              template: template,
                              branding: branding,
                              selected:
                                  branding.propertyTemplate == template,
                              onTap: () => provider.updateBrokerBranding(
                                branding.copyWith(
                                  propertyTemplate: template,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _BrandingSectionShell(
                    title: 'שיחות',
                    child: Column(
                      children: BrokerChatTemplate.values
                          .map(
                            (template) => _BrokerChatTemplateTile(
                              template: template,
                              branding: branding,
                              selected: branding.chatTemplate == template,
                              onTap: () => provider.updateBrokerBranding(
                                branding.copyWith(chatTemplate: template),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _BrandingSectionShell(
                    title: 'צבעים',
                    child: Column(
                      children: _brokerColorPresets
                          .map(
                            (preset) => _BrokerColorPresetTile(
                              preset: preset,
                              selected: branding.primaryColorValue ==
                                      preset.primary &&
                                  branding.secondaryColorValue ==
                                      preset.secondary &&
                                  branding.accentColorValue == preset.accent,
                              onTap: () => provider.updateBrokerBranding(
                                branding.copyWith(
                                  primaryColorValue: preset.primary,
                                  secondaryColorValue: preset.secondary,
                                  accentColorValue: preset.accent,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DetectedLogoPalette {
  const _DetectedLogoPalette({
    required this.primary,
    required this.secondary,
    required this.accent,
  });

  final int primary;
  final int secondary;
  final int accent;
}

class _BrokerBrandingHeader extends StatelessWidget {
  const _BrokerBrandingHeader({
    required this.onBack,
    required this.onReset,
  });

  final VoidCallback onBack;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: onBack,
          child: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: RentlyIcon(
                IconsaxPlusLinear.arrow_right,
                color: AppColors.textPrimary,
                size: 20,
              ),
            ),
          ),
        ),
        const Expanded(
          child: Text(
            'מיתוג ותבניות',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        GestureDetector(
          onTap: onReset,
          child: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(
                Icons.restart_alt_rounded,
                color: AppColors.textPrimary,
                size: 21,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BrokerBrandPreview extends StatelessWidget {
  const _BrokerBrandPreview({required this.branding});

  final BrokerBrandingConfig branding;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            branding.primaryColor,
            branding.secondaryColor,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 18,
            bottom: 18,
            child: Container(
              width: 98,
              height: 58,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white30),
              ),
            ),
          ),
          Positioned(
            right: 20,
            top: 20,
            child: _BrokerLogoPreview(
              branding: branding,
              size: 58,
              backgroundColor: Colors.white,
            ),
          ),
          Positioned(
            right: 20,
            left: 132,
            bottom: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  branding.propertyTemplate.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  branding.chatTemplate.title,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.76),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 20,
            top: 22,
            child: Row(
              children: [
                _ColorDot(color: branding.primaryColor, size: 18),
                const SizedBox(width: 8),
                _ColorDot(color: branding.secondaryColor, size: 18),
                const SizedBox(width: 8),
                _ColorDot(color: branding.accentColor, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BrokerLogoCard extends StatelessWidget {
  const _BrokerLogoCard({
    required this.branding,
    required this.detecting,
    required this.onPick,
    required this.onRemove,
  });

  final BrokerBrandingConfig branding;
  final bool detecting;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return _BrandingSectionShell(
      title: 'לוגו',
      child: Row(
        children: [
          _BrokerLogoPreview(
            branding: branding,
            size: 68,
            backgroundColor: const Color(0xFFF5F7FA),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detecting ? 'מזהה צבעים...' : 'לוגו משרד',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  branding.hasLogo ? 'משויך לתבניות הנכס והשיחה' : 'לא נבחר',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton.filled(
            onPressed: detecting ? null : onPick,
            style: IconButton.styleFrom(
              backgroundColor: branding.primaryColor,
              foregroundColor: Colors.white,
            ),
            icon: detecting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.image_outlined),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: detecting ? null : onRemove,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ],
      ),
    );
  }
}

class _BrokerLogoPreview extends StatelessWidget {
  const _BrokerLogoPreview({
    required this.branding,
    required this.size,
    required this.backgroundColor,
  });

  final BrokerBrandingConfig branding;
  final double size;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: backgroundColor,
      child: Center(
        child: Icon(
          Icons.business_rounded,
          color: branding.primaryColor,
          size: size * 0.42,
        ),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.30),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(size * 0.30),
        ),
        child: branding.hasLogo
            ? SafeImage(source: branding.logoPath, fallback: fallback)
            : fallback,
      ),
    );
  }
}

class _BrandingSectionShell extends StatelessWidget {
  const _BrandingSectionShell({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _BrokerPropertyTemplateTile extends StatelessWidget {
  const _BrokerPropertyTemplateTile({
    required this.template,
    required this.branding,
    required this.selected,
    required this.onTap,
  });

  final BrokerPropertyTemplate template;
  final BrokerBrandingConfig branding;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _TemplateChoiceTile(
      title: template.title,
      selected: selected,
      onTap: onTap,
      preview: _PropertyTemplatePreview(
        template: template,
        branding: branding,
      ),
    );
  }
}

class _BrokerChatTemplateTile extends StatelessWidget {
  const _BrokerChatTemplateTile({
    required this.template,
    required this.branding,
    required this.selected,
    required this.onTap,
  });

  final BrokerChatTemplate template;
  final BrokerBrandingConfig branding;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _TemplateChoiceTile(
      title: template.title,
      selected: selected,
      onTap: onTap,
      preview: _ChatTemplatePreview(
        template: template,
        branding: branding,
      ),
    );
  }
}

class _TemplateChoiceTile extends StatelessWidget {
  const _TemplateChoiceTile({
    required this.title,
    required this.preview,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final Widget preview;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ScaleBounce(
        onTap: onTap,
        scaleDownTo: 0.98,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFF7F8FF) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? BrandPalette.broker.primary : AppColors.divider,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              preview,
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: selected
                        ? BrandPalette.broker.primary
                        : AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: selected ? BrandPalette.broker.primary : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? BrandPalette.broker.primary
                        : AppColors.borderLight,
                  ),
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 15,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PropertyTemplatePreview extends StatelessWidget {
  const _PropertyTemplatePreview({
    required this.template,
    required this.branding,
  });

  final BrokerPropertyTemplate template;
  final BrokerBrandingConfig branding;

  @override
  Widget build(BuildContext context) {
    final bg = switch (template) {
      BrokerPropertyTemplate.acidHero => branding.accentColor,
      BrokerPropertyTemplate.dashboardGlass => const Color(0xFFEAF5EF),
      BrokerPropertyTemplate.estateCard => const Color(0xFFF5F6F8),
      BrokerPropertyTemplate.galleryEditorial => Colors.white,
      BrokerPropertyTemplate.cinematicGlass => branding.secondaryColor,
      BrokerPropertyTemplate.rentlyClassic => const Color(0xFFE6F9FB),
    };

    return Container(
      width: 58,
      height: 74,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Stack(
        children: [
          Positioned(
            top: template == BrokerPropertyTemplate.cinematicGlass ? 0 : 8,
            left: 8,
            right: 8,
            height: template == BrokerPropertyTemplate.cinematicGlass ? 44 : 30,
            child: Container(
              decoration: BoxDecoration(
                color: template == BrokerPropertyTemplate.cinematicGlass
                    ? Colors.white.withValues(alpha: 0.22)
                    : branding.primaryColor.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(11),
              ),
            ),
          ),
          Positioned(
            right: 8,
            left: 8,
            bottom: 8,
            child: Column(
              children: [
                Container(
                  height: 7,
                  decoration: BoxDecoration(
                    color: template == BrokerPropertyTemplate.cinematicGlass
                        ? Colors.white
                        : branding.secondaryColor,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: branding.primaryColor,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: branding.accentColor,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatTemplatePreview extends StatelessWidget {
  const _ChatTemplatePreview({
    required this.template,
    required this.branding,
  });

  final BrokerChatTemplate template;
  final BrokerBrandingConfig branding;

  @override
  Widget build(BuildContext context) {
    final dark = template == BrokerChatTemplate.nightSuite;
    final bg = switch (template) {
      BrokerChatTemplate.rentlyClassic => const Color(0xFFF6FAFC),
      BrokerChatTemplate.softGlass => branding.primaryColor.withValues(alpha: 0.12),
      BrokerChatTemplate.editorialLight => const Color(0xFFFAF7F1),
      BrokerChatTemplate.nightSuite => branding.secondaryColor,
    };

    return Container(
      width: 58,
      height: 58,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: 30,
              height: 10,
              decoration: BoxDecoration(
                color: branding.primaryColor,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 24,
              height: 10,
              decoration: BoxDecoration(
                color: dark ? Colors.white24 : Colors.white,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const Spacer(),
          Container(
            height: 7,
            decoration: BoxDecoration(
              color: dark ? Colors.white24 : Colors.white,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrokerColorPreset {
  const _BrokerColorPreset({
    required this.name,
    required this.primary,
    required this.secondary,
    required this.accent,
  });

  final String name;
  final int primary;
  final int secondary;
  final int accent;
}

const _brokerColorPresets = [
  _BrokerColorPreset(
    name: 'Lime Noir',
    primary: 0xFF1E1B4B,
    secondary: 0xFF1D1D24,
    accent: 0xFFECFF74,
  ),
  _BrokerColorPreset(
    name: 'Indigo Pro',
    primary: 0xFF6C5CE7,
    secondary: 0xFF111827,
    accent: 0xFF9D90FF,
  ),
  _BrokerColorPreset(
    name: 'Estate Red',
    primary: 0xFFEF2D35,
    secondary: 0xFF232323,
    accent: 0xFFFFF0F0,
  ),
  _BrokerColorPreset(
    name: 'Ocean Mint',
    primary: 0xFF4E8F8B,
    secondary: 0xFF102A35,
    accent: 0xFFE4F4EE,
  ),
  _BrokerColorPreset(
    name: 'Stone Gold',
    primary: 0xFFB39145,
    secondary: 0xFF2D2921,
    accent: 0xFFF3E8CA,
  ),
];

class _BrokerColorPresetTile extends StatelessWidget {
  const _BrokerColorPresetTile({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final _BrokerColorPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ScaleBounce(
        onTap: onTap,
        scaleDownTo: 0.98,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFF7F8FF) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? BrandPalette.broker.primary : AppColors.divider,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              _ColorDot(color: Color(preset.primary), size: 24),
              const SizedBox(width: 8),
              _ColorDot(color: Color(preset.secondary), size: 24),
              const SizedBox(width: 8),
              _ColorDot(color: Color(preset.accent), size: 24),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  preset.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle_rounded,
                  color: BrandPalette.broker.primary,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.size,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
    );
  }
}

class _ProfileMenuItem extends StatelessWidget {
  const _ProfileMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? AppColors.textPrimary;
    return ScaleBounce(
      onTap: onTap,
      scaleDownTo: 0.96,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: activeColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 20,
                color: activeColor,
              ),
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: activeColor,
              ),
            ),
            const Spacer(),
            RentlyIcon(
              IconsaxPlusLinear.arrow_left,
              size: 16,
              color: activeColor.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Settings Sub Page ────────────────────────────────────────────────────────

class _SettingsSubPage extends StatefulWidget {
  const _SettingsSubPage({
    required this.title,
    required this.items,
  });

  final String title;
  final List<_SubPageSettingItem> items;

  @override
  State<_SettingsSubPage> createState() => _SettingsSubPageState();
}

class _SettingsSubPageState extends State<_SettingsSubPage> {
  late Map<String, bool> _switchStates;

  @override
  void initState() {
    super.initState();
    _switchStates = {
      for (final item in widget.items)
        if (item.isSwitch) item.title: item.initialSwitchValue
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 44), // Balancer
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: RentlyIcon(
                          IconsaxPlusLinear.arrow_right,
                          color: AppColors.textPrimary,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // Settings Container Card
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: List.generate(widget.items.length, (index) {
                    final item = widget.items[index];
                    final isLast = index == widget.items.length - 1;

                    return Column(
                      children: [
                        GestureDetector(
                          onTap: item.onTap,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: (item.color ?? AppColors.primary).withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  item.icon,
                                  size: 20,
                                  color: item.color ?? AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.title,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: item.color ?? AppColors.textPrimary,
                                      ),
                                    ),
                                    if (item.subtitle != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        item.subtitle!,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (item.isSwitch)
                                Switch.adaptive(
                                  value: _switchStates[item.title] ?? false,
                                  activeColor: AppColors.primary,
                                  onChanged: (val) {
                                    setState(() {
                                      _switchStates[item.title] = val;
                                    });
                                  },
                                )
                              else
                                RentlyIcon(
                                  IconsaxPlusLinear.arrow_left,
                                  size: 16,
                                  color: (item.color ?? AppColors.textPrimary).withValues(alpha: 0.4),
                                ),
                            ],
                          ),
                        ),
                        ),
                        if (!isLast) const _SettingsDivider(),
                      ],
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubPageSettingItem {
  const _SubPageSettingItem({
    required this.icon,
    required this.title,
    this.subtitle,
    this.isSwitch = false,
    this.initialSwitchValue = true,
    this.onTap,
    this.color,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool isSwitch;
  final bool initialSwitchValue;
  final VoidCallback? onTap;
  final Color? color;
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ScaleBounce(
      onTap: onTap,
      scaleDownTo: 0.96,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          color: AppColors.navy)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            RentlyIcon(IconsaxPlusLinear.arrow_left,
                size: 16,
                color: AppColors.textSecondary.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Redesigned helper widgets for Tenant Profile Screen
// ─────────────────────────────────────────────────────────────────────────────

class _MockupStatBox extends StatelessWidget {
  const _MockupStatBox({
    required this.count,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String count;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: RentlyIcon(
              icon,
              size: 20,
              color: color,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            count,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreferenceTile extends StatelessWidget {
  const _PreferenceTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: RentlyIcon(
              icon,
              size: 20,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Color(0xFF475569),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const RentlyIcon(
            IconsaxPlusLinear.arrow_left,
            size: 16,
            color: Color(0xFF94A3B8),
          ),
        ],
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 1,
      color: Color(0xFFE2E8F0),
      indent: 20,
      endIndent: 20,
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final color =
        isDestructive ? AppColors.coral : const Color(0xFF0F172A);
    return ScaleBounce(
      onTap: onTap,
      scaleDownTo: 0.96,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDestructive
                    ? AppColors.coral.withValues(alpha: 0.1)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 20,
                color: color,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
            RentlyIcon(
              IconsaxPlusLinear.arrow_left,
              size: 16,
              color: isDestructive
                  ? AppColors.coral.withValues(alpha: 0.5)
                  : const Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
    );
  }
}
