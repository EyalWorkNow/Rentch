import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:dating_app/core/constants/app_colors.dart';

/// Grow "Digital Payments" method groups. The chosen code is sent to the server
/// as `group`; the hosted Grow page then opens directly on that method.
class PaymentGroup {
  static const int card = 100;
  static const int bit = 120;
  static const int googlePay = 150;
  static const int applePay = 160;
}

/// A single selectable payment method.
class _Method {
  const _Method(this.group, this.label, this.icon, {this.accent});
  final int group;
  final String label;
  final IconData icon;
  final Color? accent;
}

/// The methods available on this platform. Card + Bit everywhere; Apple Pay on
/// iOS only, Google Pay on Android only.
List<_Method> _availableMethods() {
  final isIOS = !kIsWeb && Platform.isIOS;
  final isAndroid = !kIsWeb && Platform.isAndroid;
  return [
    if (isIOS)
      const _Method(PaymentGroup.applePay, 'Apple Pay', Icons.apple,
          accent: Colors.black),
    if (isAndroid)
      const _Method(PaymentGroup.googlePay, 'Google Pay', IconsaxPlusBold.wallet_money),
    const _Method(PaymentGroup.bit, 'ביט', IconsaxPlusBold.mobile),
    const _Method(PaymentGroup.card, 'כרטיס אשראי', IconsaxPlusBold.card),
  ];
}

/// Shows the payment-method picker and returns the chosen Grow `group` code, or
/// null if dismissed. [amountLabel] (e.g. "₪45 / חודש", "₪50") is shown so the
/// user sees exactly what they're about to pay before choosing a method.
Future<int?> showPaymentMethodSheet(
  BuildContext context, {
  required String amountLabel,
  String title = 'בחירת אמצעי תשלום',
  String? subtitle,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _PaymentMethodSheet(
      amountLabel: amountLabel,
      title: title,
      subtitle: subtitle,
    ),
  );
}

class _PaymentMethodSheet extends StatelessWidget {
  const _PaymentMethodSheet({
    required this.amountLabel,
    required this.title,
    this.subtitle,
  });

  final String amountLabel;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final methods = _availableMethods();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: 20 + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.slate200,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: AppColors.slate900)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondary)),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(amountLabel,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary)),
                ),
              ],
            ),
            const SizedBox(height: 18),
            for (final m in methods) ...[
              _MethodTile(
                method: m,
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).pop(m.group);
                },
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(IconsaxPlusBold.lock_1,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text('תשלום מאובטח · Grow · Morning',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({required this.method, required this.onTap});
  final _Method method;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = method.accent ?? AppColors.primary;
    return Material(
      color: AppColors.slate50,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.slate200),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(method.icon, size: 22, color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(method.label,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.slate900)),
              ),
              const Icon(IconsaxPlusLinear.arrow_left_2,
                  size: 18, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
