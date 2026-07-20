import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/finance/rental_tax.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// "מס הכנסה — בקלות": a dead-simple rental-income tax helper for older,
/// non-technical Israeli landlords. One rent input → one clear verdict.
class TaxHelperScreen extends StatefulWidget {
  const TaxHelperScreen({super.key, this.initialMonthlyRent});

  /// Optional rent to prefill (e.g. from the landlord's property).
  final double? initialMonthlyRent;

  @override
  State<TaxHelperScreen> createState() => _TaxHelperScreenState();
}

class _TaxHelperScreenState extends State<TaxHelperScreen> {
  late final TextEditingController _controller;
  double _rent = 0;

  @override
  void initState() {
    super.initState();
    final prefill = widget.initialMonthlyRent;
    _rent = prefill ?? 0;
    _controller = TextEditingController(
      text: (prefill != null && prefill > 0) ? prefill.round().toString() : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onRentChanged(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^0-9]'), '');
    setState(() => _rent = cleaned.isEmpty ? 0 : double.parse(cleaned));
  }

  @override
  Widget build(BuildContext context) {
    final result = RentalTax.assess(_rent);
    final hasInput = _rent > 0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          foregroundColor: AppColors.textPrimary,
          title: const Text(
            'מס הכנסה — בקלות',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'כמה שכר דירה אתה מקבל בחודש?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                _RentField(controller: _controller, onChanged: _onRentChanged),
                const SizedBox(height: 24),
                if (hasInput) _VerdictCard(result: result),
                if (hasInput) const SizedBox(height: 20),
                if (hasInput) _WhatDoesItMean(result: result),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Rent input ────────────────────────────────────────────────────────────

class _RentField extends StatelessWidget {
  _RentField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textAlign: TextAlign.right,
      style: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        prefixIcon: const Padding(
          padding: EdgeInsets.only(left: 12, right: 4),
          child: Text(
            '₪',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        hintText: '0',
        hintStyle: const TextStyle(color: AppColors.textDisabled),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.borderLight, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }
}

// ─── Verdict ───────────────────────────────────────────────────────────────

class _VerdictCard extends StatelessWidget {
  const _VerdictCard({required this.result});

  final RentalTaxResult result;

  @override
  Widget build(BuildContext context) {
    final exempt = result.isFullyExempt;
    final Color accent = exempt ? AppColors.success : AppColors.warning;
    final String mark = exempt ? '✓' : '△';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            child: Text(
              mark,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: AppColors.textOnPrimary,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              result.plainHebrewSummary,
              style: const TextStyle(
                fontSize: 18,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── "מה זה אומר?" expander ──────────────────────────────────────────────────

class _WhatDoesItMean extends StatelessWidget {
  _WhatDoesItMean({required this.result});

  final RentalTaxResult result;

  String _ceiling() => '₪${kExemptCeilingMonthly.round()}'; // 5,654

  String _body() {
    if (result.isFullyExempt) {
      return 'יש תקרת פטור על שכר דירה למגורים: ${_ceiling()} בחודש (נכון ל-2026). '
          'כל עוד שכר הדירה שלך מתחת לתקרה הזו — אתה פטור ממס, '
          'ואין צורך לדווח על ההכנסה הזו.';
    }
    return 'יש תקרת פטור על שכר דירה למגורים: ${_ceiling()} בחודש (נכון ל-2026). '
        'מעל התקרה יש מס. הדרך הכי פשוטה היא "המסלול של 10%": '
        'משלמים 10% מכל שכר הדירה, בלי חישובים מסובכים ובלי ניכויים. '
        'במקרה שלך זה ${_money(result.tenPercentMonthly)} בחודש.'
        '${result.requiresAnnualReport ? ' בסכומים גבוהים (מעל ₪375,000 בשנה) צריך גם להגיש דוח שנתי.' : ''}';
  }

  String _money(double v) => '₪${v.round()}';

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: const Text(
            'מה זה אומר?',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          iconColor: AppColors.primary,
          collapsedIconColor: AppColors.textSecondary,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                _body(),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.6,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
