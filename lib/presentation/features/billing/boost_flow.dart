import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/aws_client.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/features/billing/checkout_launcher.dart';
import 'package:dating_app/presentation/features/billing/payment_method_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

/// Shared "הקפצת מודעה" (boost) flow used by every landlord surface (property
/// detail, my-properties). No subscription is required to BUY a boost — the paid
/// ₪10/₪50 one-off works for anyone; only the free monthly quota needs an active
/// subscription. Subscribers see their remaining quota first; everyone can pay.
Future<void> showBoostFlow(BuildContext context, RentalProperty p) async {
  final provider = context.read<DatingProvider>();
  final messenger = ScaffoldMessenger.of(context);
  void snack(String msg, {bool ok = false}) {
    messenger.showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: ok ? const Color(0xFF22C55E) : AppColors.coral,
    ));
  }

  final sub = provider.subscription;
  final hasQuota = sub?.canBoost ?? false;
  final choice = await showModalBottomSheet<_BoostChoice>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _BoostOptionsSheet(
      hasQuota: hasQuota,
      remaining: sub?.boostRemaining ?? 0,
      unlimited: sub?.boostUnlimited ?? false,
      isSubscriber: sub?.entitled ?? false,
    ),
  );
  if (choice == null || !context.mounted) return;

  switch (choice) {
    case _BoostChoice.regularQuota:
      await _runQuotaBoost(context, p, provider, snack);
    case _BoostChoice.regularPaid:
      await _runPaidBoost(context, p, provider, snack,
          product: 'boost_regular',
          amountAgorot: 1000,
          tier: PropertyBoostTier.regular,
          label: 'הקפצה רגילה');
    case _BoostChoice.ultraPaid:
      await _runPaidBoost(context, p, provider, snack,
          product: 'boost_ultra',
          amountAgorot: 5000,
          tier: PropertyBoostTier.ultra,
          label: 'הקפצת Ultra');
  }
}

// Free quota boost (regular tier) via the subscription.
Future<void> _runQuotaBoost(BuildContext context, RentalProperty p,
    DatingProvider provider, void Function(String, {bool ok}) snack) async {
  final r = await AwsApiClient.instance.boostProperty(p.id);
  if (!context.mounted) return;
  if (r.ok) {
    provider.applyLocalBoost(
        p.id, r.boostedUntil ?? DateTime.now().add(const Duration(days: 7)),
        tier: PropertyBoostTier.regular);
    await provider.refreshSubscription();
    snack(
      r.unlimited
          ? 'המודעה הוקפצה לראש הפיד! 🚀'
          : 'המודעה הוקפצה! נותרו ${r.remaining ?? 0} הקפצות החודש.',
      ok: true,
    );
  } else if (r.error == 'quota_exceeded') {
    snack('ניצלת את מכסת ההקפצות החודשית.');
  } else {
    snack('לא הצלחנו להקפיץ כרגע. נסו שוב.');
  }
}

// Paid one-off boost (₪10 regular / ₪50 ultra): pick a payment method → hosted
// checkout → verify → stamp the tier locally. Works with or without a subscription.
Future<void> _runPaidBoost(
  BuildContext context,
  RentalProperty p,
  DatingProvider provider,
  void Function(String, {bool ok}) snack, {
  required String product,
  required int amountAgorot,
  required PropertyBoostTier tier,
  required String label,
}) async {
  final amountLabel = '₪${amountAgorot ~/ 100}';
  final group = await showPaymentMethodSheet(context,
      amountLabel: amountLabel, subtitle: label);
  if (group == null || !context.mounted) return;

  final name = provider.tenantProfile?.name;
  String? url;
  try {
    url = await AwsApiClient.instance.createOneOffCheckout(
      amountAgorot: amountAgorot,
      product: product,
      propertyId: p.id,
      group: group,
      name: name,
    );
  } catch (_) {
    url = null; // a 4xx/5xx throws — treat as "couldn't open", don't get stuck
  }
  if (!context.mounted) return;
  final checkoutUrl = url;
  if (checkoutUrl == null) {
    snack('פתיחת התשלום נכשלה. נסו שוב.');
    return;
  }
  final paid = await openHostedCheckout(
    context,
    url: checkoutUrl,
    group: group,
    amountLabel: amountLabel,
  );
  if (paid != true || !context.mounted) return;

  final r = await AwsApiClient.instance
      .confirmOneOffBoost(product: product, propertyId: p.id);
  if (!context.mounted) return;
  final until = r.boostedUntil ?? DateTime.now().add(const Duration(days: 7));
  // Stamp locally so the listing (and its gold Ultra frame) float up now, even
  // if the server confirm is still catching up.
  provider.applyLocalBoost(p.id, until, tier: tier);
  await provider.refreshSubscription();
  snack('$label בוצעה! המודעה עלתה לראש הפיד 🚀', ok: true);
}

/// What the landlord chose in the boost sheet.
enum _BoostChoice { regularQuota, regularPaid, ultraPaid }

/// Boost options sheet — regular (quota or ₪10) + Ultra (₪50, gold). When the
/// monthly quota is spent it becomes the "out of boosts, buy one" popup; for a
/// non-subscriber it's simply "boost your listing for ₪10".
class _BoostOptionsSheet extends StatelessWidget {
  const _BoostOptionsSheet({
    required this.hasQuota,
    required this.remaining,
    required this.unlimited,
    required this.isSubscriber,
  });

  final bool hasQuota;
  final int remaining;
  final bool unlimited;
  final bool isSubscriber;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF13171D),
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, 20 + MediaQuery.of(context).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              hasQuota
                  ? 'הקפצת המודעה'
                  : (isSubscriber
                      ? 'נגמרו ההקפצות שלך החודש'
                      : 'הקפיצו את המודעה'),
              style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(
              hasQuota
                  ? 'קפיצה לראש הפיד = יותר צופים, מהר יותר.'
                  : (isSubscriber
                      ? 'רוצה שהדירה תמשיך לבלוט? הקפיצו אותה עכשיו.'
                      : 'תמורת ₪10 הדירה תעלה לראש הפיד ותגיע לכפול שוכרים היום.'),
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 18),
            // ── Regular boost ──
            _BoostOptionCard(
              icon: IconsaxPlusBold.flash_1,
              accent: const Color(0xFF256BFD), // Vibrant blue instead of dynamic primary which might be black
              title: 'הקפצה רגילה',
              subtitle: '×2 חשיפה · ראש הפיד · 7 ימים',
              trailing: hasQuota
                  ? (unlimited ? 'כלול' : 'נותרו $remaining')
                  : '₪10',
              trailingIsPrice: !hasQuota,
              onTap: () => Navigator.of(context).pop(
                  hasQuota ? _BoostChoice.regularQuota : _BoostChoice.regularPaid),
            ),
            const SizedBox(height: 12),
            // ── Ultra boost (always paid, gold) ──
            _BoostOptionCard(
              icon: IconsaxPlusBold.crown_1,
              accent: AppColors.amber,
              gold: true,
              title: 'הקפצת Ultra',
              subtitle: '×5 חשיפה · מסגרת זהב · קדימות על הקפצות רגילות · 7 ימים',
              trailing: '₪50',
              trailingIsPrice: true,
              onTap: () => Navigator.of(context).pop(_BoostChoice.ultraPaid),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoostOptionCard extends StatelessWidget {
  const _BoostOptionCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.trailingIsPrice,
    required this.onTap,
    this.gold = false,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final String trailing;
  final bool trailingIsPrice;
  final bool gold;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: gold ? AppColors.amber.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(28),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
                color: gold ? AppColors.amber.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.08),
                width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 24, color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w900,
                            color: Colors.white)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                            color: Color(0xFF94A3B8))),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: trailingIsPrice ? accent : accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(trailing,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: trailingIsPrice ? (gold ? const Color(0xFF13171D) : Colors.white) : accent)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
