import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/aws_client.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:dating_app/presentation/features/billing/checkout_launcher.dart';
import 'package:dating_app/presentation/features/billing/payment_method_selector.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// RENTLY PRO paywall — a focused two-plan (monthly / annual) subscription
/// screen for landlords. Outcome-first B2B copy, one clear comparison, a paid
/// payment-method choice (card / Bit / Apple Pay / Google Pay), and an Ultra
/// boost teaser.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key, this.reason});

  final String? reason;

  static const String _firstLaunchPaywallKey = 'seen_first_launch_paywall_v1';

  /// Presents the paywall once on first launch (gated by SharedPreferences).
  static Future<void> maybeShowOnFirstLaunch(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getBool(_firstLaunchPaywallKey) ?? false;
      if (seen) return;
      await prefs.setBool(_firstLaunchPaywallKey, true);
      if (!context.mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        settings: const RouteSettings(name: 'PaywallScreen'),
        builder: (_) => const PaywallScreen(),
      ));
    } catch (_) {}
  }

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  // Prices in agorot (VAT-inclusive). Kept in sync with the server plans.
  static const int _monthlyAgorot = 4500; // ₪45 / חודש
  static const int _annualAgorot = 45000; // ₪450 / שנה  (₪37.50/ח׳)
  static const int _annualSavingAgorot = _monthlyAgorot * 12 - _annualAgorot; // ₪90

  String _selectedPlan = 'annual'; // annual pre-selected (best value)
  bool _busy = false;
  bool _success = false;
  final TextEditingController _coupon = TextEditingController();

  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  @override
  void dispose() {
    _coupon.dispose();
    super.dispose();
  }

  int get _selectedAgorot =>
      _selectedPlan == 'annual' ? _annualAgorot : _monthlyAgorot;
  String get _periodLabel =>
      _selectedPlan == 'annual' ? _l10n.paywallScreenPerYear : _l10n.paywallScreenPerMonth;
  String get _amountLabel => '${_shekel(_selectedAgorot ~/ 100)}$_periodLabel';

  String _shekel(int amount) => '₪${_thousands(amount)}';

  String _thousands(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer(n < 0 ? '-' : '');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  // ── checkout ────────────────────────────────────────────────────────────────
  Future<void> _continue() async {
    if (_busy) return;
    // 1) Let the landlord pick a payment method (card / Bit / Apple / Google).
    final group = await showPaymentMethodSheet(
      context,
      amountLabel: _amountLabel,
      subtitle: _l10n.paywallScreenSubscriptionSubtitle(
        _selectedPlan == 'annual'
            ? _l10n.paywallScreenAnnualLabel
            : _l10n.paywallScreenMonthlyLabel,
      ),
    );
    if (group == null || !mounted) return;

    setState(() => _busy = true);
    final provider = context.read<DatingProvider>();
    final email = FirebaseAuth.instance.currentUser?.email;
    final name = provider.tenantProfile?.name;
    try {
      final couponCode = _coupon.text.trim();
      final checkout = await AwsApiClient.instance.createCheckout(
        plan: _selectedPlan,
        email: email,
        name: name,
        coupon: couponCode.isEmpty ? null : couponCode,
        group: group,
      );
      if (!mounted) return;
      if (checkout == null) {
        _snack(_l10n.paywallScreenPaymentError);
        setState(() => _busy = false);
        return;
      }
      // Prefer the server's authoritative charged amount (reflects any coupon).
      final chargedAgorot = checkout.priceAgorot ?? _selectedAgorot;
      final result = await openHostedCheckout(
        context,
        url: checkout.url,
        group: group,
        amountLabel: '${_shekel(chargedAgorot ~/ 100)}$_periodLabel',
      );
      if (!mounted) return;
      if (result == true) {
        await _pollUntilEntitled(provider);
      } else {
        setState(() => _busy = false);
      }
    } on AwsApiException catch (e) {
      if (!mounted) return;
      _snack(e.isUnauthorized
          ? _l10n.paywallScreenLoginRequired
          : _l10n.paywallScreenPaymentErrorWithCode('${e.statusCode ?? '—'}'));
      setState(() => _busy = false);
    } catch (_) {
      if (!mounted) return;
      _snack(_l10n.paywallScreenPaymentError);
      setState(() => _busy = false);
    }
  }

  Future<void> _pollUntilEntitled(DatingProvider provider) async {
    await AwsApiClient.instance.confirmSubscription();
    for (var i = 0; i < 10; i++) {
      await provider.refreshSubscription();
      if (!mounted) return;
      if (provider.isSubscribed) {
        setState(() {
          _busy = false;
          _success = true;
        });
        return;
      }
      if (i == 3 || i == 6) await AwsApiClient.instance.confirmSubscription();
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(_l10n.paywallScreenEntitlementPending);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(milliseconds: 2800),
      content: Text(message),
      backgroundColor: AppColors.coral,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          top: false,
          child: _success ? _buildSuccess() : _buildBody(),
        ),
      ),
    );
  }

  // ── body ────────────────────────────────────────────────────────────────────
  Widget _buildBody() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 22),
                _buildPlanCards(),
                const SizedBox(height: 20),
                _buildFeatureList(),
                const SizedBox(height: 14),
                _buildUltraTeaser(),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        _buildBottomCta(),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, MediaQuery.of(context).padding.top + 14, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _brandLockup(),
              const Spacer(),
              Material(
                color: AppColors.slate50,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(IconsaxPlusLinear.close_circle,
                        size: 22, color: AppColors.textSecondary),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            _l10n.paywallScreenHeadline,
            style: const TextStyle(
              color: AppColors.slate900,
              fontSize: 30,
              height: 1.1,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _l10n.paywallScreenSubheadline,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _brandLockup() {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primary, AppColors.primaryDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(IconsaxPlusBold.buildings_2,
              size: 19, color: Colors.white),
        ),
        const SizedBox(width: 9),
        Row(
          children: [
            const Text('RENTLY ',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.slate900,
                    letterSpacing: 0.5)),
            Text('PRO',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                    letterSpacing: 0.5)),
          ],
        ),
      ],
    );
  }

  // ── plan cards ───────────────────────────────────────────────────────────────
  Widget _buildPlanCards() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _PlanCard(
                title: _l10n.paywallScreenMonthlyLabel,
                priceLine: _shekel(_monthlyAgorot ~/ 100),
                periodLine: _l10n.paywallScreenPerMonthShort,
                perMonthNote: _l10n.paywallScreenMonthlyBillingNote,
                boostsNote: _l10n.paywallScreenMonthlyBoostsNote,
                selected: _selectedPlan == 'monthly',
                onTap: () => setState(() => _selectedPlan = 'monthly'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PlanCard(
                title: _l10n.paywallScreenAnnualLabel,
                priceLine: _shekel(_annualAgorot ~/ 100),
                periodLine: _l10n.paywallScreenAnnualPeriodLine,
                perMonthNote: _l10n.paywallScreenAnnualBillingNote,
                boostsNote: _l10n.paywallScreenAnnualBoostsNote,
                selected: _selectedPlan == 'annual',
                highlighted: true,
                ribbon: _l10n.paywallScreenAnnualRibbon(
                    _shekel(_annualSavingAgorot ~/ 100)),
                onTap: () => setState(() => _selectedPlan = 'annual'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── unified feature list ──────────────────────────────────────────────────────
  Widget _buildFeatureList() {
    final features = <(IconData, String)>[
      (IconsaxPlusBold.buildings_2, _l10n.paywallScreenFeatureUnlimitedListings),
      (IconsaxPlusBold.flash_1, _l10n.paywallScreenFeatureBoosts),
      (IconsaxPlusBold.verify, _l10n.paywallScreenFeatureVerifiedBadge),
      (IconsaxPlusBold.ranking_1, _l10n.paywallScreenFeatureSearchPriority),
      (IconsaxPlusBold.people, _l10n.paywallScreenFeatureCandidateManagement),
      (IconsaxPlusBold.calendar_1, _l10n.paywallScreenFeatureCalendar),
      (IconsaxPlusBold.chart_2, _l10n.paywallScreenFeatureMarketInsights),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
        decoration: BoxDecoration(
          color: AppColors.slate50,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.slate200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_l10n.paywallScreenAllPlansInclude,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.slate900)),
            const SizedBox(height: 14),
            for (final f in features) ...[
              _FeatureRow(icon: f.$1, label: f.$2),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUltraTeaser() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.amber, width: 1.3),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.amberDark.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(IconsaxPlusBold.crown_1,
                  size: 22, color: AppColors.amberDark),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_l10n.paywallScreenUltraTeaserTitle,
                      style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.slate900)),
                  const SizedBox(height: 2),
                  Text(_l10n.paywallScreenUltraTeaserBody,
                      style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── bottom CTA + coupon + trust ───────────────────────────────────────────────
  Widget _buildBottomCta() {
    final trialCopy = _selectedPlan == 'annual'
        ? _l10n.paywallScreenAnnualBillingTrial(_shekel(_annualAgorot ~/ 100))
        : _l10n
            .paywallScreenMonthlyBillingTrial(_shekel(_monthlyAgorot ~/ 100));
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
          24, 14, 24, 14 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCouponField(),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
                elevation: 0,
              ),
              onPressed: _busy ? null : _continue,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white),
                    )
                  : Text(
                      _selectedPlan == 'annual'
                          ? _l10n.paywallScreenJoinAnnual
                          : _l10n.paywallScreenJoinMonthly,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w900),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Text(trialCopy,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(IconsaxPlusLinear.lock_1,
                  size: 13, color: AppColors.textSecondary),
              const SizedBox(width: 5),
              Text(_l10n.paywallScreenSecurePayment,
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCouponField() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.slate50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slate200),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          const Icon(IconsaxPlusLinear.ticket_discount,
              size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _coupon,
              textAlign: TextAlign.right,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'\s')),
              ],
              style: const TextStyle(
                  color: AppColors.slate900,
                  fontSize: 14,
                  fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: _l10n.paywallScreenCouponHint,
                hintStyle: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600),
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── success ("thank you") ────────────────────────────────────────────────────
  Widget _buildSuccess() {
    final unlocked = [
      (IconsaxPlusLinear.buildings_2, _l10n.paywallScreenFeatureUnlimitedListings),
      (IconsaxPlusLinear.flash_1, _l10n.paywallScreenFeatureBoostListings),
      (IconsaxPlusLinear.verify, _l10n.paywallScreenFeatureVerifiedAndPriority),
      (IconsaxPlusLinear.magic_star, _l10n.paywallScreenFeatureAiFiltering),
    ];
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 132,
                    height: 132,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                          colors: [Color(0x3322C55E), Color(0x0022C55E)]),
                    ),
                  ),
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF34D399), Color(0xFF22C55E)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF22C55E).withValues(alpha: 0.45),
                          blurRadius: 26,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(IconsaxPlusBold.tick_circle,
                        size: 52, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Text(_l10n.paywallScreenThankYou,
                  style: const TextStyle(
                      color: AppColors.slate900,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5)),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_l10n.paywallScreenWelcomePrefix,
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  Text('RENTLY PRO',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 15,
                          fontWeight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                decoration: BoxDecoration(
                  color: AppColors.slate50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.slate200),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < unlocked.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      Row(children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(unlocked[i].$1,
                              size: 18, color: AppColors.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(unlocked[i].$2,
                              style: const TextStyle(
                                  color: AppColors.slate900,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                        const Icon(IconsaxPlusBold.tick_circle,
                            size: 18, color: Color(0xFF22C55E)),
                      ]),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(IconsaxPlusLinear.sms,
                      size: 15, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 6),
                  Text(_l10n.paywallScreenReceiptSent,
                      style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 26),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(_l10n.paywallScreenLetsStart,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── plan card ───────────────────────────────────────────────────────────────
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.priceLine,
    required this.periodLine,
    required this.perMonthNote,
    required this.boostsNote,
    required this.selected,
    required this.onTap,
    this.highlighted = false,
    this.ribbon,
  });

  final String title;
  final String priceLine;
  final String periodLine;
  final String perMonthNote;
  final String boostsNote;
  final bool selected;
  final bool highlighted;
  final String? ribbon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? AppColors.primary : AppColors.slate200;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: selected ? 2.2 : 1.4),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.14),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: AppColors.slate900)),
                const Spacer(),
                _radio(selected),
              ],
            ),
            if (ribbon != null) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(ribbon!,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900)),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(priceLine,
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: AppColors.slate900,
                        letterSpacing: -0.5)),
              ],
            ),
            const SizedBox(height: 2),
            Text(periodLine,
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            _pill(boostsNote, IconsaxPlusBold.flash_1),
            const SizedBox(height: 8),
            Text(perMonthNote,
                style: const TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _radio(bool on) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? AppColors.primary : Colors.transparent,
        border: Border.all(
            color: on ? AppColors.primary : AppColors.slate200, width: 2),
      ),
      child: on
          ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
          : null,
    );
  }

  Widget _pill(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.primary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(text,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary)),
          ),
        ],
      ),
    );
  }
}

// ── feature row ───────────────────────────────────────────────────────────────
class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 17, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label,
              style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                  color: AppColors.slate900)),
        ),
        const Icon(IconsaxPlusBold.tick_circle,
            size: 18, color: Color(0xFF22C55E)),
      ],
    );
  }
}
