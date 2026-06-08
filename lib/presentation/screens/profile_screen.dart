import 'dart:io';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/google_auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/features/user/profile/edit_profile_screen.dart';
import 'package:dating_app/presentation/screens/add_property_screen.dart';
import 'package:dating_app/presentation/screens/auth_screen.dart';
import 'package:dating_app/presentation/screens/landlord_properties_screen.dart';
import 'package:dating_app/presentation/screens/matches_screen.dart';
import 'package:dating_app/presentation/screens/message_screen.dart';
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:dating_app/presentation/widgets/rentch_icon.dart';
import 'package:provider/provider.dart';

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

    try {
      await GoogleAuthService().signOut();
    } catch (_) {}
    await provider.deleteAccount();

    if (!context.mounted) return;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
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
          return const Scaffold(
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
                              const RentchIcon(
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
                                  decoration: const BoxDecoration(
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
                                          child: const RentchIcon(
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
                                  child: const RentchIcon(
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
                                RentchIcon(IconsaxPlusLinear.user,
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
                          _ActionRow(
                            icon: IconsaxPlusLinear.trash,
                            label: 'מחיקת חשבון',
                            onTap: () => _confirmDeleteAccount(context),
                            isDestructive: true,
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
          icon: const RentchIcon(IconsaxPlusLinear.edit,
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
                        Container(
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
                                ? const RentchIcon(
                                    IconsaxPlusLinear.profile_circle,
                                    color: Colors.white,
                                    size: 34)
                                : null,
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
                        const RentchIcon(IconsaxPlusLinear.money,
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
              const RentchIcon(IconsaxPlusLinear.star_1,
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
              RentchIcon(
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
                        style: const TextStyle(
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
                child: RentchIcon(
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
            'שדרג לגרסת הפרו של Rentch לקבלת נתונים חיים עשירים יותר, התאמות ללא הגבלה ועוד פיצ\'רים מתקדמים.',
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
          const _SettingsDivider(),
          _ProfileMenuItem(
            icon: IconsaxPlusLinear.setting_2,
            label: 'הגדרות התראות',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const _SettingsSubPage(
                    title: 'הגדרות התראות',
                    items: [
                      _SubPageSettingItem(
                        icon: IconsaxPlusLinear.notification,
                        title: 'התראות בנייד',
                        subtitle: 'קבל עדכונים בזמן אמת על מכשירך',
                        isSwitch: true,
                      ),
                      _SubPageSettingItem(
                        icon: IconsaxPlusLinear.sms,
                        title: 'התראות אימייל',
                        subtitle: 'קבל סיכומים שבועיים ועדכוני מערכת',
                        isSwitch: true,
                      ),
                      _SubPageSettingItem(
                        icon: IconsaxPlusLinear.user_add,
                        title: 'פניות שוכרים',
                        subtitle: 'התראות על התאמות ולידים חדשים',
                        isSwitch: true,
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
                  builder: (_) => const _SettingsSubPage(
                    title: 'תמיכה ועזרה',
                    items: [
                      _SubPageSettingItem(
                        icon: IconsaxPlusLinear.message_question,
                        title: 'מרכז עזרה ומדריכים',
                        subtitle: 'שאלות נפוצות ומאמרי תמיכה',
                      ),
                      _SubPageSettingItem(
                        icon: IconsaxPlusLinear.call_calling,
                        title: 'צור קשר עם התמיכה',
                        subtitle: 'אנחנו כאן לעזור 24/7',
                      ),
                      _SubPageSettingItem(
                        icon: IconsaxPlusLinear.document_text,
                        title: 'תנאי שימוש ומדיניות',
                        subtitle: 'הסכם שימוש ושמירה על פרטיות',
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
            icon: IconsaxPlusLinear.user_octagon,
            label: 'החלף חשבון לשוכר',
            color: AppColors.primary,
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22)),
                  title: const Text('החלפת חשבון',
                      style: TextStyle(
                          color: AppColors.navy, fontWeight: FontWeight.w900)),
                  content: const Text(
                    'האם ברצונך להחליף את מצב החשבון למצב שוכר?',
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
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('החלף'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await provider.setUserRole('tenant');
              }
            },
          ),
          const _SettingsDivider(),
          _ProfileMenuItem(
            icon: IconsaxPlusLinear.logout,
            label: 'יציאה מהחשבון',
            color: AppColors.coral,
            onTap: onLogout,
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
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
              RentchIcon(
                IconsaxPlusLinear.arrow_left,
                size: 16,
                color: activeColor.withValues(alpha: 0.4),
              ),
            ],
          ),
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
                        child: RentchIcon(
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
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  item.icon,
                                  size: 20,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.title,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary,
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
                                RentchIcon(
                                  IconsaxPlusLinear.arrow_left,
                                  size: 16,
                                  color: AppColors.textPrimary.withValues(alpha: 0.4),
                                ),
                            ],
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
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool isSwitch;
  final bool initialSwitchValue;
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
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
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
              RentchIcon(IconsaxPlusLinear.arrow_left,
                  size: 16,
                  color: AppColors.textSecondary.withValues(alpha: 0.5)),
            ],
          ),
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
            child: RentchIcon(
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
            child: RentchIcon(
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
          const RentchIcon(
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
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
            RentchIcon(
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
