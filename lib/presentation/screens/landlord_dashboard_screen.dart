import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/google_auth_service.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/features/user/profile/edit_profile_screen.dart';
import 'package:dating_app/presentation/screens/add_property_screen.dart'
    show AddPropertyScreen, EditPropertyScreen;
import 'package:dating_app/presentation/screens/message_screen.dart';
import 'package:dating_app/presentation/screens/auth_screen.dart';
import 'package:dating_app/presentation/screens/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

class LandlordDashboardScreen extends StatelessWidget {
  const LandlordDashboardScreen({super.key});

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          'יציאה מהחשבון',
          style: TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: const Text(
          'האם אתה בטוח שברצונך לצאת?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'ביטול',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.coral,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('יציאה'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
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
        final stats = provider.landlordStats;
        final profile = provider.tenantProfile;
        final recentMatches = provider.matches.take(2).toList();
        final latestProperty =
            provider.myProperties.isNotEmpty ? provider.myProperties.first : null;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: AppColors.background,
            title: const Text('דשבורד משכיר'),
            actions: [
              IconButton(
                tooltip: 'עריכת פרופיל',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => profile == null
                        ? const ProfileScreen()
                        : EditProfileScreen(profile: profile),
                  ),
                ),
                icon: const Icon(IconsaxPlusLinear.edit),
              ),
              IconButton(
                tooltip: 'התנתקות',
                onPressed: () => _confirmLogout(context),
                icon: const Icon(IconsaxPlusLinear.logout),
              ),
              const SizedBox(width: 6),
            ],
          ),
          body: provider.isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              : SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                    children: [
                      _DashHero(
                        landlordName: profile?.name ?? 'בעל הדירה',
                        pendingCount: stats.pendingCount,
                        onAddProperty: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AddPropertyScreen(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _LandlordProfileActions(
                        profile: profile,
                        onEditProfile: () {
                          if (profile == null) return;
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => EditProfileScreen(profile: profile),
                            ),
                          );
                        },
                        onOpenProfile: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ProfileScreen(),
                          ),
                        ),
                        onLogout: () => _confirmLogout(context),
                      ),
                      const SizedBox(height: 14),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        childAspectRatio: 1.2,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        children: [
                          _StatCard(
                            title: 'דירות פעילות',
                            value: '${stats.propertiesCount}',
                            icon: IconsaxPlusBold.building_3,
                            accent: AppColors.primary,
                          ),
                          _StatCard(
                            title: 'מועמדים ממתינים',
                            value: '${stats.pendingCount}',
                            icon: IconsaxPlusBold.profile_2user,
                            accent: AppColors.navy,
                          ),
                          _StatCard(
                            title: 'מאצ׳ים פתוחים',
                            value: '${stats.matchesCount}',
                            icon: IconsaxPlusBold.heart,
                            accent: AppColors.coral,
                          ),
                          _StatCard(
                            title: 'יחס המרה',
                            value: '${stats.conversionRate.round()}%',
                            icon: IconsaxPlusBold.chart_2,
                            accent: const Color(0xFF1B9C6A),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _TodayPanel(
                        pendingCount: stats.pendingCount,
                        propertiesCount: stats.propertiesCount,
                        matchesCount: stats.matchesCount,
                        onAddProperty: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AddPropertyScreen(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (latestProperty != null)
                        _FocusCard(property: latestProperty),
                      if (latestProperty != null) const SizedBox(height: 18),
                      _SectionTitle(
                        title: 'התאמות אחרונות',
                        subtitle: 'שיחות פעילות שכדאי להמשיך מהן',
                      ),
                      const SizedBox(height: 10),
                      if (recentMatches.isEmpty)
                        const _EmptyPanel(
                          title: 'עדיין אין התאמות',
                          subtitle:
                              'ברגע ששוכרים יתחילו לאהוב נכסים, ההתאמות יופיעו כאן.',
                        )
                      else
                        ...recentMatches.map(
                          (match) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _RecentMatchCard(match: match),
                          ),
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _DashHero extends StatelessWidget {
  const _DashHero({
    required this.landlordName,
    required this.pendingCount,
    required this.onAddProperty,
  });

  final String landlordName;
  final int pendingCount;
  final VoidCallback onAddProperty;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF06243A), Color(0xFF0E516A)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  IconsaxPlusBold.home_2,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$pendingCount ממתינים',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'שלום $landlordName, זה מרכז הבקרה שלך',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'מכאן אפשר להוסיף נכס, לראות מה מחכה לטיפול, ולעבור במהירות למסך הסוויפים וההתאמות.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onAddProperty,
            icon: const Icon(IconsaxPlusBold.add_square, size: 16),
            label: const Text('הוסף דירה חדשה'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.navy,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LandlordProfileActions extends StatelessWidget {
  const _LandlordProfileActions({
    required this.profile,
    required this.onEditProfile,
    required this.onOpenProfile,
    required this.onLogout,
  });

  final TenantProfile? profile;
  final VoidCallback onEditProfile;
  final VoidCallback onOpenProfile;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.primary.withValues(alpha: 0.14),
                child: const Icon(
                  IconsaxPlusBold.profile_circle,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile?.name ?? 'פרופיל בעל דירה',
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'הפרטים האלו מוצגים לשוכרים לפני שהם פונים אליך.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: profile == null ? null : onEditProfile,
                  icon: const Icon(IconsaxPlusLinear.edit, size: 16),
                  label: const Text('עריכת פרופיל'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onOpenProfile,
                  icon: const Icon(IconsaxPlusLinear.eye, size: 16),
                  label: const Text('תצוגה מלאה'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.navy,
                    side: const BorderSide(color: AppColors.borderLight),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _LogoutPill(onTap: onLogout),
            ],
          ),
        ],
      ),
    );
  }
}

class _LogoutPill extends StatelessWidget {
  const _LogoutPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'יציאה מהחשבון',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.coral.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            IconsaxPlusLinear.logout,
            color: AppColors.coral,
          ),
        ),
      ),
    );
  }
}

class _TodayPanel extends StatelessWidget {
  const _TodayPanel({
    required this.pendingCount,
    required this.propertiesCount,
    required this.matchesCount,
    required this.onAddProperty,
  });

  final int pendingCount;
  final int propertiesCount;
  final int matchesCount;
  final VoidCallback onAddProperty;

  @override
  Widget build(BuildContext context) {
    final tasks = <_TaskItem>[
      _TaskItem(
        icon: IconsaxPlusBold.profile_2user,
        title: pendingCount == 0
            ? 'אין מועמדים שמחכים לאישור'
            : '$pendingCount מועמדים מחכים לאישור',
        subtitle: 'טפל מהר כדי לשמור על מומנטום עם שוכרים רציניים.',
        color: AppColors.primary,
      ),
      _TaskItem(
        icon: IconsaxPlusBold.building,
        title: propertiesCount == 0
            ? 'עוד לא פרסמת דירה'
            : '$propertiesCount דירות פעילות במערכת',
        subtitle: 'אפשר להוסיף תמונות ועדכונים כדי לשפר פניות.',
        color: AppColors.navy,
      ),
      _TaskItem(
        icon: IconsaxPlusBold.message,
        title: matchesCount == 0 ? 'אין שיחות פתוחות' : '$matchesCount שיחות פתוחות',
        subtitle: 'שיחות פעילות מופיעות למטה כדי לסגור ביקור מהר.',
        color: AppColors.coral,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF4),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFFE0B8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: _SectionTitle(
                  title: 'מה דורש טיפול היום',
                  subtitle: 'סדר עבודה קצר לבעל הדירה',
                ),
              ),
              IconButton.filled(
                onPressed: onAddProperty,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(IconsaxPlusLinear.add),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...tasks.map(
            (task) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TaskRow(item: task),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskItem {
  const _TaskItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.item});

  final _TaskItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: item.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(item.icon, color: item.color, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w900,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.subtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent, size: 18),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusCard extends StatelessWidget {
  const _FocusCard({required this.property});

  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () => _showQuickActions(context),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: _SectionTitle(
                    title: 'פוקוס להיום',
                    subtitle: 'הנכס האחרון שהוספת ונמצא כרגע במעקב',
                  ),
                ),
                _QuickEditButton(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => EditPropertyScreen(property: property),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        property.address,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${property.priceLabel} • ${property.roomsLabel} חדרים • ${property.sizeM2} מ"ר',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'פעיל',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
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

  void _showQuickActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PropertyQuickActionsSheet(property: property),
    );
  }
}

class _RecentMatchCard extends StatelessWidget {
  const _RecentMatchCard({required this.match});

  final RentalMatch match;

  static String _verificationLabel(RentalMatch m) {
    if (m.ownerSigned && m.tenantSigned) return 'מאומת מלא';
    if (m.contractSent) return 'חוזה נשלח';
    if (m.messages.length >= 3) return 'שיחה פעילה';
    return 'ממתין';
  }

  static Color _verificationColor(RentalMatch m) {
    if (m.ownerSigned && m.tenantSigned) return const Color(0xFF1B9C6A);
    if (m.contractSent) return AppColors.primary;
    if (m.messages.length >= 3) return AppColors.navy;
    return AppColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<DatingProvider>();
    final property = provider.propertyById(match.propertyId);
    if (property == null) return const SizedBox.shrink();
    final latestMessage = match.messages.isNotEmpty ? match.messages.last : null;
    final verLabel = _verificationLabel(match);
    final verColor = _verificationColor(match);

    return GestureDetector(
      onLongPress: () => _showQuickActions(context, match),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.primaryLight2,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                IconsaxPlusBold.message,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          property.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.navy,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _VerificationBadge(label: verLabel, color: verColor),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    latestMessage?.text ?? 'שיחה חדשה ממתינה',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      height: 1.4,
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

  void _showQuickActions(BuildContext context, RentalMatch m) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _MatchQuickActionsSheet(match: m),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        children: [
          const Icon(IconsaxPlusLinear.message_question,
              color: AppColors.textSecondary),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Feature #24: Verification Badge ─────────────────────────────────────────

class _VerificationBadge extends StatelessWidget {
  const _VerificationBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(IconsaxPlusBold.verify, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Feature #30: Quick Edit Button ──────────────────────────────────────────

class _QuickEditButton extends StatelessWidget {
  const _QuickEditButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'עריכת נכס',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            IconsaxPlusLinear.edit,
            size: 16,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}

// ─── Feature #30: Property Quick Actions Bottom Sheet ─────────────────────────

class _PropertyQuickActionsSheet extends StatelessWidget {
  const _PropertyQuickActionsSheet({required this.property});

  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 16 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.borderLight,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            property.address,
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            property.priceLabel,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 18),
          _QuickActionTile(
            icon: IconsaxPlusLinear.edit,
            label: 'ערוך פרטי הנכס',
            color: AppColors.primary,
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EditPropertyScreen(property: property),
                ),
              );
            },
          ),
          _QuickActionTile(
            icon: IconsaxPlusBold.trash,
            label: 'הסר נכס מהרשימה',
            color: AppColors.coral,
            onTap: () async {
              Navigator.pop(context);
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22)),
                  title: const Text('הסרת נכס',
                      style: TextStyle(
                          color: AppColors.navy, fontWeight: FontWeight.w900)),
                  content: const Text('האם אתה בטוח שברצונך להסיר נכס זה?',
                      style: TextStyle(color: AppColors.textSecondary)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('ביטול',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.coral),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('הסר'),
                    ),
                  ],
                ),
              );
              if (confirmed == true && context.mounted) {
                await context
                    .read<DatingProvider>()
                    .removeLandlordProperty(property.id);
              }
            },
          ),
          _QuickActionTile(
            icon: IconsaxPlusLinear.share,
            label: 'שתף קישור לנכס',
            color: AppColors.navy,
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('שיתוף בקרוב...')),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Feature #30: Match Quick Actions Bottom Sheet ─────────────────────────────

class _MatchQuickActionsSheet extends StatelessWidget {
  const _MatchQuickActionsSheet({required this.match});

  final RentalMatch match;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 16 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.borderLight,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'פעולות מהירות',
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 18),
          _QuickActionTile(
            icon: IconsaxPlusLinear.message,
            label: 'פתח שיחה',
            color: AppColors.primary,
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MessageScreen(matchId: match.id),
                ),
              );
            },
          ),
          _QuickActionTile(
            icon: IconsaxPlusLinear.calendar,
            label: 'תאם ביקור',
            color: AppColors.navy,
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('תיאום ביקור בקרוב...')),
              );
            },
          ),
          _QuickActionTile(
            icon: IconsaxPlusLinear.close_circle,
            label: 'סגור התאמה',
            color: AppColors.coral,
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                color: color == AppColors.coral ? AppColors.coral : AppColors.navy,
                fontWeight: FontWeight.w700,
                fontSize: 14.5,
              ),
            ),
            const Spacer(),
            Icon(
              IconsaxPlusLinear.arrow_left,
              size: 16,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
