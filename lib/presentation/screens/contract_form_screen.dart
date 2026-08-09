import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/aws_client.dart';
import 'package:dating_app/data/models/rental_contract.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/data/repositories/contract_repository.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:dating_app/presentation/features/billing/checkout_webview_screen.dart';
import 'package:dating_app/presentation/features/billing/payment_method_selector.dart';
import 'package:dating_app/presentation/screens/contract_detail_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

// The 5 `TextDirection.rtl` uses in this file are a DELIBERATE exception to
// the app-wide language switch: rental contracts are Israeli legal documents
// and stay Hebrew regardless of the reader's chosen app language — same
// reasoning a lease wouldn't get machine-translated just because the UI did.
// Do not "fix" these to follow `Directionality.of(context)`.
/// Landlord-facing flow to draft + send a rental contract for a match.
///
/// The body of the lease comes from one of two sources:
///   • the STANDARD residential-lease template "מטעם עורכי הדין של Rently",
///     auto-filled from the property/match data; or
///   • that text after the PAID (50₪) "שפר עם AI" pass tailored it.
/// Either way the disclaimer "אינו תחליף לייעוץ משפטי" rides along.
class ContractFormScreen extends StatefulWidget {
  const ContractFormScreen({super.key, required this.matchId});
  final String matchId;

  @override
  State<ContractFormScreen> createState() => _ContractFormScreenState();
}

class _ContractFormScreenState extends State<ContractFormScreen> {
  final _rentCtrl = TextEditingController();
  final _depositCtrl = TextEditingController();
  final _termsCtrl = TextEditingController();
  int _durationMonths = 12;
  DateTime _startDate = DateTime.now().add(const Duration(days: 14));
  bool _sending = false;

  /// Which lease body the landlord is using. Starts on the standard template.
  ContractTemplateKind _template = ContractTemplateKind.standard;

  /// True once the ₪50 AI one-off payment completes via the real Morning
  /// checkout (`createOneOffCheckout` + `CheckoutWebViewScreen` in `_showPaywall`).
  bool _aiPaid = false;
  bool _aiBusy = false;

  static const _durations = [6, 12, 18, 24, 36];
  static const int _aiPriceShekel = 50;

  final ContractRepository _contracts = ContractRepository();

  @override
  void dispose() {
    _rentCtrl.dispose();
    _depositCtrl.dispose();
    _termsCtrl.dispose();
    super.dispose();
  }

  int _asInt(String s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  DateTime get _endDate =>
      DateTime(_startDate.year, _startDate.month + _durationMonths, _startDate.day);

  // ── Auto-fill facts pulled from the property/match for the template ─────────

  ({String landlord, String tenant, String title}) _parties() {
    final provider = context.read<DatingProvider>();
    final match = provider.matchById(widget.matchId);
    final property = provider.propertyById(match?.propertyId ?? '');
    final landlord = (property?.ownerName ?? '').trim();
    final title = (property?.address ?? '').trim();
    // The authoritative tenant name is resolved server-side at create time; the
    // draft template uses a neutral placeholder.
    return (
      landlord: landlord.isNotEmpty ? landlord : 'בעל הדירה',
      tenant: 'השוכר',
      title: title.isNotEmpty ? title : 'הנכס נשוא ההסכם',
    );
  }

  /// Rebuilds the standard-template text from the current numbers. Called when
  /// the user lands on / returns to the standard template.
  void _fillStandardTemplate() {
    final p = _parties();
    _termsCtrl.text = StandardLeaseTemplate.fill(
      landlordName: p.landlord,
      tenantName: p.tenant,
      propertyTitle: p.title,
      monthlyRent: _asInt(_rentCtrl.text),
      deposit: _asInt(_depositCtrl.text),
      durationMonths: _durationMonths,
      startDate: _startDate,
      endDate: _endDate,
    );
  }

  @override
  void initState() {
    super.initState();
    // Defer until context is available for the provider read.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fillStandardTemplate();
    });
  }

  // ── AI improve (paid) ──────────────────────────────────────────────────────

  Future<void> _onTapAi() async {
    if (!_aiPaid) {
      final paid = await _showPaywall();
      if (paid != true) return;
      setState(() => _aiPaid = true);
    }
    await _runAiImprove();
  }

  /// Shows the intro sheet, then — on confirm — creates a REAL one-off 50₪
  /// Morning payment and collects it in the hosted checkout WebView. Returns
  /// true only when the hosted page reports a successful payment.
  Future<bool?> _showPaywall() async {
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _PaywallSheet(priceShekel: _aiPriceShekel),
    );
    if (confirm != true || !mounted) return false;

    final l10n = AppLocalizations.of(context)!;
    // Choose a payment method (card / Bit / Apple Pay / Google Pay).
    final group = await showPaymentMethodSheet(context,
        amountLabel: '₪$_aiPriceShekel',
        subtitle: l10n.contractFormScreenCa38cedb);
    if (group == null || !mounted) return false;

    final provider = context.read<DatingProvider>();
    final email = FirebaseAuth.instance.currentUser?.email;
    final name = provider.tenantProfile?.name;
    String? url;
    try {
      url = await AwsApiClient.instance.createOneOffCheckout(
        amountAgorot: _aiPriceShekel * 100,
        description: l10n.contractFormScreenA7aa0554,
        product: 'contract',
        email: email,
        name: name,
        group: group,
      );
    } catch (_) {
      url = null;
    }
    if (!mounted) return false;
    if (url == null) {
      _err(l10n.contractFormScreen5ff8838c);
      return false;
    }
    final checkoutUrl = url; // promote to non-null for the closure
    final paid = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'CheckoutWebViewScreen'),
        builder: (_) => CheckoutWebViewScreen(
          url: checkoutUrl,
          amountLabel: '₪$_aiPriceShekel',
        ),
      ),
    );
    return paid == true;
  }

  Future<void> _runAiImprove() async {
    final p = _parties();
    setState(() => _aiBusy = true);
    final improved = await _contracts.improveWithAi(
      contractText: _termsCtrl.text.trim(),
      propertyTitle: p.title,
      monthlyRent: _asInt(_rentCtrl.text),
      deposit: _asInt(_depositCtrl.text),
      durationMonths: _durationMonths,
      landlordName: p.landlord,
      tenantName: p.tenant,
    );
    if (!mounted) return;
    setState(() => _aiBusy = false);
    if (improved == null) {
      _err(AppLocalizations.of(context)!.contractFormScreen0bf10733);
      return;
    }
    setState(() {
      _template = ContractTemplateKind.aiTailored;
      _termsCtrl.text = improved;
    });
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text(AppLocalizations.of(context)!.contractFormScreenC2278e7d)),
    );
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null) {
      setState(() => _startDate = picked);
      if (_template == ContractTemplateKind.standard) _fillStandardTemplate();
    }
  }

  Future<void> _send() async {
    final rent = _asInt(_rentCtrl.text);
    if (rent <= 0) {
      _err(AppLocalizations.of(context)!.contractFormScreenCbbabf55);
      return;
    }
    setState(() => _sending = true);
    final provider = context.read<DatingProvider>();
    final contract = await provider.createRentalContract(
      matchId: widget.matchId,
      monthlyRent: rent,
      deposit: _asInt(_depositCtrl.text),
      durationMonths: _durationMonths,
      startDate: _startDate,
      terms: _termsCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (contract == null) {
      _err(AppLocalizations.of(context)!.contractFormScreen8e5a493e);
      return;
    }
    HapticFeedback.mediumImpact();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            ContractDetailScreen(contractId: contract.id, matchId: widget.matchId),
      ),
    );
  }

  void _err(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final isAi = _template == ContractTemplateKind.aiTailored;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(l10n.contractFormScreen64202d91)),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: SizedBox(
          height: 54,
          child: FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(IconsaxPlusLinear.document_text, size: 18),
            label: Text(_sending
                ? l10n.contractFormScreenEdb89494
                : l10n.contractFormScreenC1c55cf9),
          ),
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _card(
              title: l10n.contractFormScreen1b58c9a0,
              icon: IconsaxPlusLinear.money_recive,
              children: [
                _numberField(_rentCtrl, l10n.contractFormScreen0ae58e28,
                    IconsaxPlusLinear.money),
                const SizedBox(height: 12),
                _numberField(_depositCtrl, l10n.contractFormScreen99d1d056,
                    IconsaxPlusLinear.security),
                _DepositLegalityNote(
                  deposit: _asInt(_depositCtrl.text),
                  monthlyRent: _asInt(_rentCtrl.text),
                  termMonths: _durationMonths,
                ),
                const SizedBox(height: 18),
                Text(l10n.contractFormScreenBdecb11c,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _durations.map((m) {
                    final sel = m == _durationMonths;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _durationMonths = m);
                        if (_template == ContractTemplateKind.standard) {
                          _fillStandardTemplate();
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          color: sel ? AppColors.primary : AppColors.background,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: sel
                                  ? AppColors.primary
                                  : AppColors.borderLight),
                        ),
                        child: Text(l10n.contractFormScreenBf1cf58d(m),
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: sel ? Colors.white : AppColors.navy)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),
                GestureDetector(
                  onTap: _pickStartDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.borderLight),
                    ),
                    child: Row(
                      children: [
                        RentlyCalendarIcon(),
                        const SizedBox(width: 12),
                        Text(l10n.contractFormScreenB7cdc163,
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text(
                          '${_startDate.day}/${_startDate.month}/${_startDate.year}',
                          style: const TextStyle(
                              color: AppColors.navy,
                              fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Template + AI ─────────────────────────────────────────────────
            _card(
              title: l10n.contractFormScreen67e27f00,
              icon: IconsaxPlusLinear.document_favorite,
              children: [
                _StandardTemplateBadge(active: !isAi),
                const SizedBox(height: 12),
                _AiImproveTile(
                  active: isAi,
                  paid: _aiPaid,
                  busy: _aiBusy,
                  priceShekel: _aiPriceShekel,
                  onTap: _aiBusy ? null : _onTapAi,
                ),
                if (isAi) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: () {
                      setState(() => _template = ContractTemplateKind.standard);
                      _fillStandardTemplate();
                    },
                    icon: const Icon(IconsaxPlusLinear.refresh, size: 16),
                    label: Text(l10n.contractFormScreen9e1017ad),
                  ),
                ],
                const SizedBox(height: 14),
                Text(l10n.contractFormScreen30664b86,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                TextField(
                  controller: _termsCtrl,
                  maxLines: 14,
                  minLines: 8,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                      fontSize: 12.5, height: 1.55, color: AppColors.navy),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.borderLight),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _DisclaimerNote(),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(IconsaxPlusLinear.shield_tick,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.contractFormScreen374bbbdf,
                    style: const TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberField(
      TextEditingController c, String label, IconData icon) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textDirection: TextDirection.rtl,
      onChanged: (_) {
        if (_template == ContractTemplateKind.standard) _fillStandardTemplate();
        // Rebuild so the inline deposit-legality note re-evaluates.
        setState(() {});
      },
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18, color: AppColors.primary),
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
      ),
    );
  }

  Widget _card(
      {required String title,
      required IconData icon,
      required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle),
                child: Icon(icon, size: 16, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Text(title,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppColors.navy)),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class RentlyCalendarIcon extends StatelessWidget {
  RentlyCalendarIcon({super.key});
  @override
  Widget build(BuildContext context) =>
      Icon(IconsaxPlusLinear.calendar_1, size: 18, color: AppColors.primary);
}

// ─── Standard template badge ──────────────────────────────────────────────────

class _StandardTemplateBadge extends StatelessWidget {
  _StandardTemplateBadge({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: active
            ? AppColors.primary.withValues(alpha: 0.08)
            : AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? AppColors.primary : AppColors.borderLight,
          width: active ? 1.4 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle),
            child: Icon(IconsaxPlusBold.document_text,
                size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppLocalizations.of(context)!.contractFormScreenE34604a7,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: AppColors.navy)),
                const SizedBox(height: 2),
                Text(StandardLeaseTemplate.credit,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary)),
              ],
            ),
          ),
          if (active)
            Icon(Icons.check_circle_rounded,
                color: AppColors.primary, size: 22),
        ],
      ),
    );
  }
}

// ─── AI improve tile (paid) ───────────────────────────────────────────────────

class _AiImproveTile extends StatelessWidget {
  _AiImproveTile({
    required this.active,
    required this.paid,
    required this.busy,
    required this.priceShekel,
    required this.onTap,
  });

  final bool active;
  final bool paid;
  final bool busy;
  final int priceShekel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withValues(alpha: 0.10),
              AppColors.superLike.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.borderLight,
            width: active ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: AppColors.superLike.withValues(alpha: 0.13), shape: BoxShape.circle),
              child: busy
                  ? Padding(
                      padding: const EdgeInsets.all(9),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary),
                    )
                  : const Icon(IconsaxPlusBold.magicpen,
                      size: 18, color: AppColors.superLike),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(l10n.contractFormScreenCbfee77a,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: AppColors.navy)),
                      const SizedBox(width: 8),
                      if (!paid)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.superLike,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                              l10n.contractFormScreen311875d1(priceShekel),
                              style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white)),
                        )
                      else if (active)
                        Icon(Icons.check_circle_rounded,
                            color: AppColors.primary, size: 18),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    busy
                        ? l10n.contractFormScreen82a64993
                        : l10n.contractFormScreen3750438e,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            if (!busy)
              const Icon(Icons.chevron_left_rounded,
                  color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

// ─── Deposit legality (חוק שכירות הוגנת) ──────────────────────────────────────

/// Inline, NON-BLOCKING note shown under the deposit field. Warns (amber) when
/// the entered cash-cost security exceeds the legal cap, and always explains the
/// difference between a שטר חוב and a צ'ק ביטחון.
class _DepositLegalityNote extends StatelessWidget {
  const _DepositLegalityNote({
    required this.deposit,
    required this.monthlyRent,
    required this.termMonths,
  });

  final int deposit;
  final int monthlyRent;
  final int termMonths;

  @override
  Widget build(BuildContext context) {
    final legality = depositLegality(deposit, monthlyRent, termMonths);
    // Nothing useful to show until there's a rent + a deposit.
    if (legality.cap <= 0 || deposit <= 0) return const SizedBox.shrink();

    const tip =
        'שימו לב: שטר חוב או ערבות צד ג׳ אינם "פיקדון במזומן" ואינם כפופים לתקרה זו; '
        'צ׳ק ביטחון שמופקד נספר כפיקדון במזומן.';

    if (legality.ok) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          tip,
          textDirection: TextDirection.rtl,
          style: const TextStyle(
              fontSize: 11, height: 1.45, color: AppColors.textSecondary),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(IconsaxPlusLinear.warning_2,
                size: 16, color: AppColors.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    legality.message,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    tip,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                        fontSize: 11,
                        height: 1.45,
                        color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Disclaimer ───────────────────────────────────────────────────────────────

class _DisclaimerNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(IconsaxPlusLinear.info_circle,
              size: 16, color: AppColors.warning),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              StandardLeaseTemplate.disclaimer,
              style: TextStyle(
                  fontSize: 11.5, height: 1.5, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Paywall sheet (stub) ─────────────────────────────────────────────────────

class _PaywallSheet extends StatelessWidget {
  _PaywallSheet({required this.priceShekel});
  final int priceShekel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.borderLight,
                    borderRadius: BorderRadius.circular(999)),
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                    color: AppColors.superLike.withValues(alpha: 0.13), shape: BoxShape.circle),
                child: const Icon(IconsaxPlusBold.magicpen,
                    size: 26, color: AppColors.superLike),
              ),
            ),
            const SizedBox(height: 14),
            Text(l10n.contractFormScreenA78d435c,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy)),
            const SizedBox(height: 6),
            Text(
              '${l10n.contractFormScreenF4a6089f}${l10n.contractFormScreenC0583fa2}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13, height: 1.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Row(
                children: [
                  Icon(IconsaxPlusLinear.tag,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Text(l10n.contractFormScreen99b411b6,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.navy)),
                  const Spacer(),
                  Text('$priceShekel ₪',
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                // Confirms intent; the real 50₪ charge happens next in the
                // hosted checkout WebView (see _showPaywall).
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(IconsaxPlusLinear.card, size: 18),
                label: Text(l10n.contractFormScreenFa001394(priceShekel)),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.contractFormScreen98c8a5b8),
            ),
            const SizedBox(height: 4),
            const Text(
              StandardLeaseTemplate.disclaimer,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 10.5, height: 1.4, color: AppColors.textDisabled),
            ),
          ],
        ),
      ),
    );
  }
}
