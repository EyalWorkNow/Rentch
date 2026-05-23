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
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: const [
            BoxShadow(
                color: AppColors.shadow, blurRadius: 14, offset: Offset(0, 6))
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(22),
              ),
              child: SizedBox(
                width: 100,
                height: 116,
                child: imageUrl.isEmpty
                    ? Container(
                        color: AppColors.primaryLight2,
                        child: const Icon(IconsaxPlusBold.building,
                            color: AppColors.primary, size: 32),
                      )
                    : Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: AppColors.primaryLight2,
                          child: const Icon(IconsaxPlusBold.building,
                              color: AppColors.primary, size: 32),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      property.address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 5),
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
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        _StatusChip(
                          label: match.contractSent ? 'חוזה נשלח' : 'צ׳אט פתוח',
                          color: match.contractSent
                              ? const Color(0xFF14A87A)
                              : AppColors.primary,
                        ),
                        if (match.ownerSigned)
                          const _StatusChip(
                              label: 'בעלים חתם',
                              color: Color(0xFF14A87A)),
                        if (match.tenantSigned)
                          const _StatusChip(
                              label: 'שוכר חתם',
                              color: Color(0xFF14A87A)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(left: 14),
              child: Icon(IconsaxPlusLinear.arrow_left,
                  size: 18, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontWeight: FontWeight.w700, fontSize: 11),
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
