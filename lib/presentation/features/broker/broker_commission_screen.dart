import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/broker_deal.dart';
import 'package:dating_app/data/repositories/broker_deal_repository.dart';
import 'package:flutter/material.dart';

/// עמלות ופייפליין כספי — commission pipeline dashboard.
///
/// Three honest numbers a broker rarely sees in one place: the expected
/// commission still in flight (sum of open deals' amount × pct), the commission
/// actually won this calendar month, and a per-deal breakdown. Local CRUD via
/// [BrokerDealRepository]; no backend.
class BrokerCommissionScreen extends StatefulWidget {
  const BrokerCommissionScreen({super.key, this.repository});

  /// Injectable for tests; defaults to the SharedPreferences-backed repo.
  final BrokerDealRepository? repository;

  @override
  State<BrokerCommissionScreen> createState() => _BrokerCommissionScreenState();
}

/// Pure dashboard totals derived from a deal list. Kept separate so the math is
/// testable and self-checkable.
class CommissionTotals {
  const CommissionTotals({
    required this.expectedPipeline,
    required this.wonThisMonth,
    required this.openCount,
  });

  final double expectedPipeline;
  final double wonThisMonth;
  final int openCount;
}

/// Sums expected pipeline (open deals) and commission won in [now]'s month.
/// Pure; includes an assert self-check that the parts never exceed the whole.
CommissionTotals commissionTotals(List<BrokerDeal> deals, DateTime now) {
  final monthKey = BrokerDeal.monthKey(now);
  var expected = 0.0;
  var wonMonth = 0.0;
  var wonAll = 0.0;
  var openCount = 0;
  for (final d in deals) {
    if (d.isOpen) {
      expected += d.commissionAmount;
      openCount++;
    } else if (d.isWon) {
      wonAll += d.commissionAmount;
      if (d.closedMonth == monthKey) wonMonth += d.commissionAmount;
    }
  }

  final totals = CommissionTotals(
    expectedPipeline: expected,
    wonThisMonth: wonMonth,
    openCount: openCount,
  );

  // Self-check: per-month won can't exceed all-time won, and neither total can
  // be negative (commissionAmount is clamped at 0 in the model).
  assert(() {
    final ok = wonMonth <= wonAll + 1e-6 &&
        expected >= -1e-6 &&
        wonMonth >= -1e-6;
    if (!ok) {
      throw StateError('commissionTotals invariant broken: '
          'expected=$expected wonMonth=$wonMonth wonAll=$wonAll');
    }
    return true;
  }());

  return totals;
}

class _BrokerCommissionScreenState extends State<BrokerCommissionScreen> {
  late final BrokerDealRepository _repo =
      widget.repository ?? BrokerDealRepository();

  List<BrokerDeal> _deals = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await _repo.loadAll();
    if (!mounted) return;
    setState(() {
      _deals = list;
      _loading = false;
    });
  }

  Future<void> _openEditor([BrokerDeal? existing]) async {
    final result = await showModalBottomSheet<BrokerDeal>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DealEditor(existing: existing),
    );
    if (result == null) return;
    await _repo.save(result);
    await _reload();
  }

  Future<void> _delete(BrokerDeal d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('למחוק את העסקה?'),
          content: Text(d.propertyTitle.trim().isEmpty
              ? 'הרשומה תימחק לצמיתות.'
              : '"${d.propertyTitle.trim()}" תימחק לצמיתות.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ביטול')),
            FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('מחק')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _repo.delete(d.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final totals = commissionTotals(_deals, DateTime.now());
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('עמלות ופייפליין'),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(color: AppColors.divider, height: 1, thickness: 1),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          onPressed: () => _openEditor(),
          icon: const Icon(Icons.add),
          label: const Text('עסקה חדשה',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _statCard(
                          'צפי בצנרת',
                          _money(totals.expectedPipeline),
                          '${totals.openCount} עסקאות פתוחות',
                          AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _statCard(
                          'נסגר החודש',
                          _money(totals.wonThisMonth),
                          'עמלה שהתקבלה',
                          AppColors.success,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const Text('כל העסקאות',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 12),
                  if (_deals.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'אין עדיין עסקאות. הוסף עסקה כדי לעקוב אחר העמלות.',
                        style: TextStyle(
                            fontSize: 16, color: AppColors.textSecondary),
                      ),
                    )
                  else
                    for (final d in _deals) _dealCard(d),
                ],
              ),
      ),
    );
  }

  Widget _statCard(String label, String value, String sub, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w900, color: color)),
          const SizedBox(height: 4),
          Text(sub,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _dealCard(BrokerDeal d) {
    final stageColor = d.isWon
        ? AppColors.success
        : d.isOpen
            ? AppColors.primary
            : AppColors.textDisabled;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: const [
          BoxShadow(color: AppColors.shadow, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  d.propertyTitle.isEmpty ? 'עסקה ללא שם' : d.propertyTitle,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: stageColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(d.stage.hebrewLabel,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: stageColor)),
              ),
            ],
          ),
          if (d.clientName.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('לקוח: ${d.clientName}',
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _miniStat('שווי עסקה', _money(d.dealAmount)),
              ),
              Expanded(
                child: _miniStat('עמלה (${_pct(d.commissionPct)}%)',
                    _money(d.commissionAmount)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => _openEditor(d),
                icon: const Icon(Icons.edit_outlined, size: 20),
                label: const Text('עריכה'),
                style:
                    TextButton.styleFrom(foregroundColor: AppColors.primaryDark),
              ),
              TextButton.icon(
                onPressed: () => _delete(d),
                icon: const Icon(Icons.delete_outline, size: 20),
                label: const Text('מחיקה'),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
        ],
      );
}

class _DealEditor extends StatefulWidget {
  _DealEditor({this.existing});

  final BrokerDeal? existing;

  @override
  State<_DealEditor> createState() => _DealEditorState();
}

class _DealEditorState extends State<_DealEditor> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.propertyTitle ?? '');
  late final TextEditingController _client =
      TextEditingController(text: widget.existing?.clientName ?? '');
  late final TextEditingController _amount = TextEditingController(
      text: (widget.existing?.dealAmount ?? 0) == 0
          ? ''
          : widget.existing!.dealAmount.toStringAsFixed(0));
  late final TextEditingController _pctCtrl = TextEditingController(
      text: (widget.existing?.commissionPct ?? 0) == 0
          ? ''
          : _pct(widget.existing!.commissionPct));

  late BrokerDealStage _stage = widget.existing?.stage ?? BrokerDealStage.open;

  @override
  void dispose() {
    _title.dispose();
    _client.dispose();
    _amount.dispose();
    _pctCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final base = widget.existing;
    final id = base?.id ?? 'deal_${DateTime.now().microsecondsSinceEpoch}';
    final stage = _stage;
    // A deal counts toward "won this month" only when it's marked won; stamp the
    // current month at that point (keep an existing stamp on edit if already won).
    final closedMonth = stage == BrokerDealStage.won
        ? (base?.isWon == true && base!.closedMonth.isNotEmpty
            ? base.closedMonth
            : BrokerDeal.monthKey(DateTime.now()))
        : '';
    final deal = BrokerDeal(
      id: id,
      propertyTitle: _title.text.trim(),
      clientName: _client.text.trim(),
      dealAmount: double.tryParse(_amount.text.trim()) ?? 0,
      commissionPct: double.tryParse(_pctCtrl.text.trim()) ?? 0,
      stage: stage,
      closedMonth: closedMonth,
    );
    Navigator.of(context).pop(deal);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final livePct = double.tryParse(_pctCtrl.text.trim()) ?? 0;
    final liveAmount = double.tryParse(_amount.text.trim()) ?? 0;
    final liveCommission =
        (liveAmount <= 0 || livePct <= 0) ? 0.0 : liveAmount * livePct / 100;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.borderLight,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.existing == null ? 'עסקה חדשה' : 'עריכת עסקה',
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 16),
              _field(_title, 'כתובת / שם הנכס'),
              _field(_client, 'שם הלקוח'),
              _field(_amount, 'שווי עסקה (₪)',
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {})),
              _field(_pctCtrl, 'אחוז עמלה (%)',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {})),
              if (liveCommission > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text('עמלה צפויה: ${_money(liveCommission)}',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryDark)),
                ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  for (final s in BrokerDealStage.values)
                    ChoiceChip(
                      label: Text(s.hebrewLabel),
                      selected: _stage == s,
                      onSelected: (_) => setState(() => _stage = s),
                      selectedColor: AppColors.primaryLight,
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _stage == s
                            ? AppColors.textOnPrimary
                            : AppColors.textPrimary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textOnPrimary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('שמירה',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {TextInputType? keyboardType, ValueChanged<String>? onChanged}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: keyboardType,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: AppColors.primaryLight2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// ₪ with thousands separators, no decimals.
String _money(double value) {
  final rounded = value.round();
  final digits = rounded.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return '₪${rounded < 0 ? '-' : ''}$buf';
}

String _pct(double v) => v % 1 == 0 ? v.toInt().toString() : v.toString();
