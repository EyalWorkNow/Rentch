import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/message_screen.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

class MatchesScreen extends StatelessWidget {
  const MatchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DatingProvider>(
      builder: (context, provider, _) {
        final matches = provider.matches;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.navy,
            surfaceTintColor: Colors.transparent,
            automaticallyImplyLeading: true,
            iconTheme: const IconThemeData(color: Colors.white),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'התאמות',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (matches.isNotEmpty)
                  Text(
                    '${matches.length} דירות שאהבת',
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
          body: provider.isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : matches.isEmpty
                  ? const _EmptyMatches()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                      itemCount: matches.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final match = matches[index];
                        final property =
                            provider.propertyById(match.propertyId);
                        if (property == null) return const SizedBox.shrink();

                        return _MatchCard(
                          match: match,
                          property: property,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  MessageScreen(matchId: match.id),
                            ),
                          ),
                        );
                      },
                    ),
        );
      },
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.match,
    required this.property,
    required this.onTap,
  });

  final RentalMatch match;
  final RentalProperty property;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final imageUrl =
        property.imageUrls.isNotEmpty ? property.imageUrls.first : '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE2ECF1), width: 1.2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x06072946),
              blurRadius: 18,
              offset: Offset(0, 6),
            )
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                width: 90,
                height: 94,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE2ECF1), width: 1),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(17),
                  child: imageUrl.isEmpty
                      ? Container(
                          color: AppColors.primaryLight2,
                          child: const Icon(IconsaxPlusBold.building,
                              color: AppColors.primary, size: 28),
                        )
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: AppColors.primaryLight2,
                            child: const Icon(IconsaxPlusBold.building,
                                color: AppColors.primary, size: 28),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      property.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(IconsaxPlusLinear.money,
                            size: 12, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          '${property.priceLabel} • ${property.roomsLabel} חדרים',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    if (match.messages.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            IconsaxPlusLinear.message,
                            size: 11,
                            color: AppColors.textSecondary.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              match.messages.last.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textSecondary.withValues(alpha: 0.8),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _StatusChip(
                          label: match.contractSent ? 'חוזה נשלח' : 'צ׳אט פתוח',
                          color: match.contractSent
                              ? const Color(0xFF27AE60)
                              : AppColors.primary,
                          icon: match.contractSent
                              ? IconsaxPlusBold.document_text
                              : IconsaxPlusBold.message,
                        ),
                        if (match.ownerSigned)
                          const _StatusChip(
                            label: 'בעלים חתם',
                            color: Color(0xFF27AE60),
                            icon: IconsaxPlusBold.pen_tool,
                          ),
                        if (match.tenantSigned)
                          const _StatusChip(
                            label: 'שוכר חתם',
                            color: Color(0xFF27AE60),
                            icon: IconsaxPlusBold.edit,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(left: 16),
              child: Icon(IconsaxPlusLinear.arrow_left,
                  size: 16, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.18), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyMatches extends StatelessWidget {
  const _EmptyMatches();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                IconsaxPlusBold.heart_tick,
                color: AppColors.primary,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'עוד אין התאמות',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'כשתאהב דירה ובעל הדירה יאשר אותך — ההתאמה תופיע כאן.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
