import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/compare_screen.dart';
import 'package:dating_app/presentation/screens/property_detail_screen.dart';
import 'package:dating_app/presentation/widgets/safe_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// "הדירות ששמרתי" — the tenant's saved/favorite listings.
///
/// This is the home for the saved-apartments concept: a clear RTL list of the
/// listings the tenant marked with ❤. From here — and only when there are 2 or
/// more saved — the user can open [CompareScreen] to compare their saved
/// apartments, so compare's purpose is self-evident (compare YOUR saved ones).
class SavedPropertiesScreen extends StatelessWidget {
  const SavedPropertiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DatingProvider>();
    final saved = provider.savedProperties;
    final canCompare = saved.length >= 2;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text(
            'הדירות ששמרתי',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
        ),
        body: saved.isEmpty
            ? _EmptyState()
            : Column(
                children: [
                  if (canCompare) _CompareButton(),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: saved.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _SavedCard(
                        property: saved[i],
                        provider: provider,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Clear "compare my saved apartments" call-to-action. Only shown when 2+ are
/// saved, so it appears exactly when it's useful.
class _CompareButton extends StatelessWidget {
  // Not const: references AppColors.primary (mutable static).
  // ignore: prefer_const_constructors_in_immutables
  _CompareButton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CompareScreen()),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textOnPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
          icon: const Icon(Icons.compare_arrows_rounded, size: 24),
          label: const Text(
            'השווה דירות שמורות',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

/// Compact card: photo, where/address, price, optional match-%, unsave heart.
class _SavedCard extends StatelessWidget {
  _SavedCard({required this.property, required this.provider});

  final RentalProperty property;
  final DatingProvider provider;

  @override
  Widget build(BuildContext context) {
    final p = property;
    final match = provider.displayMatchScore(p);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                PropertyDetailScreen(property: p, entrySource: 'saved'),
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.borderLight),
          ),
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 92,
                  height: 92,
                  child: SafeImage(
                    source: p.imageUrl,
                    fallback: Container(
                      color: AppColors.primaryLight2,
                      child: const Icon(
                        Icons.home_rounded,
                        color: AppColors.textDisabled,
                        size: 32,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _title(p),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${p.priceLabel} ${p.priceSuffixLabel}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (match != null) ...[
                      const SizedBox(height: 6),
                      _MatchBadge(score: match),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'הסר מהשמורים',
                onPressed: () => provider.toggleSave(p.id),
                icon: const Icon(
                  Icons.favorite_rounded,
                  color: AppColors.error,
                  size: 28,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _title(RentalProperty p) {
    final where = p.neighborhood.trim().isNotEmpty
        ? p.neighborhood.trim()
        : p.city.trim();
    return where.isNotEmpty ? where : p.address;
  }
}

class _MatchBadge extends StatelessWidget {
  // Not const: references AppColors.primary (mutable static).
  // ignore: prefer_const_constructors_in_immutables
  _MatchBadge({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'התאמה $score%',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.favorite_border_rounded,
              size: 72,
              color: AppColors.textDisabled,
            ),
            const SizedBox(height: 20),
            const Text(
              'עדיין לא שמרת דירות — סמנו ❤ בדירות שאהבתם כדי לחזור אליהן בקלות.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
