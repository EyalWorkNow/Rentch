import 'dart:io';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/add_property_screen.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

class LandlordPropertiesScreen extends StatelessWidget {
  const LandlordPropertiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DatingProvider>(
      builder: (context, provider, _) {
        final properties = provider.myProperties;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: AppColors.background,
            title: const Text('הדירות שלי'),
          ),
          body: provider.isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              : SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                        child: _PropertiesHeader(
                          count: properties.length,
                          onAdd: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AddPropertyScreen(),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: properties.isEmpty
                            ? const _EmptyPropertiesState()
                            : ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 120),
                                itemBuilder: (context, index) {
                                  return _PropertyManageCard(
                                    property: properties[index],
                                    onRemove: () => context
                                        .read<DatingProvider>()
                                        .removeLandlordProperty(
                                          properties[index].id,
                                        ),
                                  );
                                },
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                                itemCount: properties.length,
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

class _PropertiesHeader extends StatelessWidget {
  const _PropertiesHeader({
    required this.count,
    required this.onAdd,
  });

  final int count;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  IconsaxPlusBold.buildings_2,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ניהול דירות',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$count נכסים פעילים בחשבון שלך',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(IconsaxPlusBold.add_square, size: 16),
              label: const Text('הוסף דירה'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PropertyManageCard extends StatelessWidget {
  const _PropertyManageCard({
    required this.property,
    required this.onRemove,
  });

  final RentalProperty property;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final imageUrl = property.imageUrls.isNotEmpty ? property.imageUrls.first : '';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: SizedBox(
              height: 160,
              width: double.infinity,
              child: _PropertyThumb(imageUrl: imageUrl),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        property.address,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        property.priceLabel,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _PropertyMeta(label: '${property.roomsLabel} חדרים'),
                    _PropertyMeta(label: '${property.sizeM2} מ"ר'),
                    _PropertyMeta(
                      label: property.entryDate.isEmpty
                          ? 'כניסה גמישה'
                          : property.entryDate,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: onRemove,
                      icon: const Icon(IconsaxPlusLinear.trash, size: 16),
                      label: const Text('הסר נכס'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.coral,
                        side: const BorderSide(color: AppColors.coral),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.navy.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          'מופיע כרגע בדשבורד ובמסך הסוויפים',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.navy,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
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

class _PropertyThumb extends StatelessWidget {
  const _PropertyThumb({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.startsWith('/') || imageUrl.startsWith('file://')) {
      final path = imageUrl.startsWith('file://') ? imageUrl.substring(7) : imageUrl;
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    if (imageUrl.isNotEmpty) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() => Container(
        color: AppColors.primaryLight2,
        child: const Icon(
          IconsaxPlusBold.building,
          size: 42,
          color: AppColors.primary,
        ),
      );
}

class _PropertyMeta extends StatelessWidget {
  const _PropertyMeta({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primaryLight2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.navy,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyPropertiesState extends StatelessWidget {
  const _EmptyPropertiesState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                IconsaxPlusBold.buildings,
                size: 36,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'עדיין לא הוספת דירות',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'הוסף נכס ראשון כדי להתחיל לקבל לייקים, מועמדים ושיחות.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
