import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/design/design_system.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/property_detail_screen.dart';
import 'package:dating_app/presentation/widgets/rently_icon.dart';
import 'package:dating_app/presentation/widgets/safe_image.dart';
import 'package:dating_app/presentation/widgets/scale_bounce.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

/// Chat Partner Profile Details Screen — matching the exact visual specification
/// provided in the design screenshot, styled in Rently's sleek dark luxury
/// aesthetic and design tokens.
class ChatPartnerProfileScreen extends StatefulWidget {
  const ChatPartnerProfileScreen({
    super.key,
    required this.partnerName,
    this.partnerAvatarUrl = '',
    this.partnerSubtitle,
    this.property,
    this.messageCount = 0,
    this.isLandlord = false,
  });

  final String partnerName;
  final String partnerAvatarUrl;
  final String? partnerSubtitle;
  final RentalProperty? property;
  final int messageCount;
  final bool isLandlord;

  @override
  State<ChatPartnerProfileScreen> createState() =>
      _ChatPartnerProfileScreenState();
}

class _ChatPartnerProfileScreenState extends State<ChatPartnerProfileScreen> {
  // Real media count for the linked property (images + videos), used by the
  // stats card and the gallery overflow badge.
  int get _photoCount {
    final p = widget.property;
    if (p == null) return 0;
    final fromMedia = p.media.length;
    return fromMedia > 0 ? fromMedia : p.imageUrls.length;
  }

  void _openProperty() {
    final p = widget.property;
    if (p == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      settings: const RouteSettings(name: 'PropertyDetailScreen'),
      builder: (_) => PropertyDetailScreen(property: p, entrySource: 'chat'),
    ));
  }

  Future<void> _sharePartner() async {
    final p = widget.property;
    final text = p != null
        ? '${widget.partnerName} · ${p.city} — דרך Rently'
        : '${widget.partnerName} — דרך Rently';
    await Share.share(text, subject: widget.partnerName);
  }

  String _formatNumber(int number) {
    final str = number.toString();
    final result = StringBuffer();
    for (var i = 0; i < str.length; i++) {
      final reverseIndex = str.length - i;
      result.write(str[i]);
      if (reverseIndex > 1 && reverseIndex % 3 == 1) {
        result.write(',');
      }
    }
    return result.toString();
  }

  @override
  Widget build(BuildContext context) {
    // Default luxury dark palette matching the design reference screenshot
    const bgColor = Color(0xFF0F1318);
    const cardBgColor = Color(0xFF191F28);
    const cardBorderColor = Color(0xFF262E3B);

    final displayAvatar = widget.partnerAvatarUrl.isNotEmpty
        ? widget.partnerAvatarUrl
        : (widget.property?.imageUrls.isNotEmpty == true
            ? widget.property!.imageUrls.first
            : '');

    final samplePhotos = (widget.property?.imageUrls ?? []).take(4).toList();

    return Scaffold(
      backgroundColor: bgColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.primary.withValues(alpha: 0.15),
              bgColor,
              bgColor,
            ],
            stops: const [0.0, 0.35, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Top Navigation Bar ───────────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Back button
                    ScaleBounce(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.1),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                        ),
                        child: const Icon(
                          Icons.chevron_left_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ),

                    // Actions menu button
                    ScaleBounce(
                      onTap: () {
                        _showActionsBottomSheet(context);
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.1),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                        ),
                        child: const Icon(
                          Icons.more_vert_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Scrollable Body ──────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Column(
                    children: [
                      // ── Large Centered Profile Header ────────────────────
                      Center(
                        child: Column(
                          children: [
                            Stack(
                              children: [
                                Container(
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color:
                                          AppColors.primary.withValues(alpha: 0.4),
                                      width: 2.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.25),
                                        blurRadius: 20,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: ClipOval(
                                    child: SafeImage(
                                      source: displayAvatar,
                                      fit: BoxFit.cover,
                                      fallback: Container(
                                        color: AppColors.navy,
                                        child: const Center(
                                          child: Icon(
                                            Icons.person_rounded,
                                            size: 52,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                                // (No presence dot — we can't truthfully know the
                                // partner's online status; the realtime flag only
                                // reflects our own socket, so showing it would lie.)
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Full Name
                            Text(
                              widget.partnerName,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 4),

                            // Phone Number / Subtitle
                            Text(
                              widget.partnerSubtitle ?? '',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.65),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // ── 3 Stat Summary Cards Row (REAL data) ────────────
                      Row(
                        children: [
                          Expanded(
                            child: _StatCard(
                              label: 'הודעות',
                              value: _formatNumber(widget.messageCount),
                              bgColor: cardBgColor,
                              borderColor: cardBorderColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatCard(
                              label: 'תמונות',
                              value: _photoCount.toString(),
                              bgColor: cardBgColor,
                              borderColor: cardBorderColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatCard(
                              label: 'חדרים',
                              value: widget.property != null
                                  ? widget.property!.rooms
                                      .toString()
                                      .replaceAll('.0', '')
                                  : '—',
                              bgColor: cardBgColor,
                              borderColor: cardBorderColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Media and Photos Gallery Section ─────────────────
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cardBgColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: cardBorderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Gallery Title Header Row → opens the property.
                            GestureDetector(
                              onTap: _openProperty,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'מדיה ותמונות',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: Colors.white.withValues(alpha: 0.6),
                                    size: 22,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Photo thumbnails row
                            Row(
                              children: List.generate(4, (index) {
                                final isLast = index == 3;
                                final imgSource = index < samplePhotos.length
                                    ? samplePhotos[index]
                                    : displayAvatar;

                                return Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      left: index < 3 ? 8.0 : 0.0,
                                    ),
                                    child: AspectRatio(
                                      aspectRatio: 1.0,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(14),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            SafeImage(
                                              source: imgSource,
                                              fit: BoxFit.cover,
                                              fallback: Container(
                                                color: Colors.white10,
                                                child: const Icon(
                                                  Icons.image_rounded,
                                                  color: Colors.white38,
                                                ),
                                              ),
                                            ),

                                            // Real overflow badge on the 4th tile.
                                            if (isLast && _photoCount > 4)
                                              GestureDetector(
                                                onTap: _openProperty,
                                                child: Container(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.6),
                                                  child: Center(
                                                    child: Text(
                                                      '+${_photoCount - 4}',
                                                      style: const TextStyle(
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Open the linked property (the real subject of the chat).
                      if (widget.property != null) ...[
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: cardBgColor,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: cardBorderColor),
                          ),
                          child: _SettingTile(
                            icon: IconsaxPlusLinear.house_2,
                            title: 'הדירה בשיחה',
                            trailing: Icon(
                              Icons.chevron_right_rounded,
                              color: Colors.white.withValues(alpha: 0.5),
                              size: 22,
                            ),
                            onTap: _openProperty,
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // ── Secondary Actions Container ───────────────────────
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: cardBgColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: cardBorderColor),
                        ),
                        child: Column(
                          children: [
                            // Block User
                            _SettingTile(
                              icon: Icons.block_rounded,
                              iconColor: AppColors.coral,
                              title: 'חסימת משתמש',
                              titleColor: AppColors.coral,
                              trailing: const Icon(
                                Icons.chevron_right_rounded,
                                color: AppColors.coral,
                                size: 22,
                              ),
                              onTap: () {
                                _confirmBlockUser(context);
                              },
                            ),
                            const _Divider(),

                            // Clear chat
                            _SettingTile(
                              icon: IconsaxPlusLinear.trash,
                              iconColor: AppColors.coral,
                              title: 'מחיקת היסטוריית השיחה',
                              titleColor: AppColors.coral,
                              trailing: const Icon(
                                Icons.chevron_right_rounded,
                                color: AppColors.coral,
                                size: 22,
                              ),
                              onTap: () {
                                _confirmClearChat(context);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
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

  void _showActionsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF191F28),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.partnerName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            if (widget.property != null)
              ListTile(
                leading: const Icon(Icons.home_rounded, color: Colors.white),
                title: const Text('פתיחת הדירה',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _openProperty();
                },
              ),
            ListTile(
              leading: const Icon(Icons.share_rounded, color: Colors.white),
              title: const Text('שיתוף',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _sharePartner();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmBlockUser(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF191F28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'חסום את "${widget.partnerName}"?',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'המשתמש לא יוכל יותר ליצור איתך קשר או לצפות במודעות שלך.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ביטול', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.coral,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              // Real block: hides all their listings + reports to moderation
              // (Apple requires a block to notify the developer).
              await context
                  .read<DatingProvider>()
                  .blockOwner(widget.partnerName);
              if (!context.mounted) return;
              Navigator.pop(context);
            },
            child: const Text('חסום',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmClearChat(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF191F28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'מחיקת היסטוריית השיחה',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'פעולה זו תמחק את כל ההודעות בשיחה זו. האם להמשיך?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ביטול', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.coral,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              // Signal the chat screen to clear its history, then return to it.
              Navigator.pop(context, 'clear_history');
            },
            child: const Text('מחק',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ─── Stat Card Widget ────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.bgColor,
    required this.borderColor,
  });

  final String label;
  final String value;
  final Color bgColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Setting Tile Widget ─────────────────────────────────────────────────────
class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.title,
    required this.trailing,
    required this.onTap,
    this.iconColor,
    this.titleColor,
  });

  final IconData icon;
  final String title;
  final Widget trailing;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final effectiveIconColor = iconColor ?? Colors.white.withValues(alpha: 0.9);
    final effectiveTitleColor = titleColor ?? Colors.white;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            RentlyIcon(
              icon,
              color: effectiveIconColor,
              size: 20,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: effectiveTitleColor,
                ),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

// ─── Divider Line ────────────────────────────────────────────────────────────
class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 50,
      endIndent: 16,
      color: Colors.white.withValues(alpha: 0.07),
    );
  }
}
