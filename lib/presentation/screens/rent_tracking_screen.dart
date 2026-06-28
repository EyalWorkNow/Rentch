import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rent_ledger.dart';
import 'package:dating_app/data/repositories/rent_ledger_repository.dart';
import 'package:flutter/material.dart';

/// Per-property monthly rent ledger, built for older landlords.
///
/// One big row per month, a giant green "שולם ✓" / red "לא שולם" pill, and a
/// SINGLE tap to toggle paid (which records [RentEntry.paidAt]). The expected
/// amount is auto-filled from the property's [monthlyRent]. A header summarises
/// what was collected this month and how much is still owed.
///
/// Open it with the property's id + title + monthly rent:
/// ```dart
/// Navigator.of(context).push(MaterialPageRoute(
///   builder: (_) => RentTrackingScreen(
///     propertyId: property.id,
///     propertyTitle: property.title,
///     monthlyRent: property.price,
///   ),
/// ));
/// ```
class RentTrackingScreen extends StatefulWidget {
  const RentTrackingScreen({
    super.key,
    required this.propertyId,
    required this.propertyTitle,
    required this.monthlyRent,
    this.repository,
    this.leaseStart,
  });

  /// Stable id used to key the ledger in local storage.
  final String propertyId;

  /// Shown in the app bar so the landlord knows which apartment they're on.
  final String propertyTitle;

  /// Auto-filled expected rent (₪) for newly generated months.
  final int monthlyRent;

  /// Optional injection point for tests; defaults to the real repository.
  final RentLedgerRepository? repository;

  /// Where the first generated month begins. Defaults to the current month.
  final DateTime? leaseStart;

  @override
  State<RentTrackingScreen> createState() => _RentTrackingScreenState();
}

class _RentTrackingScreenState extends State<RentTrackingScreen> {
  late final RentLedgerRepository _repo;
  RentLedger? _ledger;
  bool _loading = true;

  static const List<String> _hebrewMonths = [
    'ינואר',
    'פברואר',
    'מרץ',
    'אפריל',
    'מאי',
    'יוני',
    'יולי',
    'אוגוסט',
    'ספטמבר',
    'אוקטובר',
    'נובמבר',
    'דצמבר',
  ];

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? RentLedgerRepository();
    _load();
  }

  Future<void> _load() async {
    final ledger = await _repo.load(widget.propertyId);
    if (!mounted) return;
    setState(() {
      _ledger = ledger;
      _loading = false;
    });
  }

  String _monthLabel(RentEntry e) =>
      '${_hebrewMonths[(e.month - 1).clamp(0, 11)]} ${e.year}';

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

  Future<void> _startTracking() async {
    final start = widget.leaseStart ?? DateTime.now();
    final generated = (_ledger ?? RentLedger(propertyId: widget.propertyId))
        .generateMonths(
      start: DateTime(start.year, start.month),
      count: 12,
      monthlyAmount: widget.monthlyRent,
    );
    await _repo.save(generated);
    if (!mounted) return;
    setState(() => _ledger = generated);
  }

  Future<void> _addNextMonth() async {
    final current = _ledger ?? RentLedger(propertyId: widget.propertyId);
    final last = current.isNotEmpty ? current.entries.last : null;
    final next = last != null
        ? DateTime(last.year, last.month + 1)
        : DateTime.now();
    final updated = current.generateMonths(
      start: next,
      count: 1,
      monthlyAmount: widget.monthlyRent,
    );
    await _repo.save(updated);
    if (!mounted) return;
    setState(() => _ledger = updated);
  }

  Future<void> _togglePaid(int index) async {
    final current = _ledger;
    if (current == null) return;
    final updated = current.togglePaidAt(index);
    await _repo.save(updated);
    if (!mounted) return;
    setState(() => _ledger = updated);
  }

  @override
  Widget build(BuildContext context) {
    final ledger = _ledger;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          title: const Text('מעקב תשלומים'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : (ledger == null || ledger.isEmpty)
                ? _EmptyState(
                    title: widget.propertyTitle,
                    onStart: _startTracking,
                  )
                : _buildList(ledger),
        floatingActionButton:
            (!_loading && ledger != null && ledger.isNotEmpty)
                ? FloatingActionButton.extended(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textOnPrimary,
                    onPressed: _addNextMonth,
                    icon: const Icon(Icons.add),
                    label: const Text('חודש נוסף'),
                  )
                : null,
      ),
    );
  }

  Widget _buildList(RentLedger ledger) {
    final collected = ledger.collectedThisMonth();
    final debt = ledger.outstandingDebt();
    // Newest month first — most landlords care about the recent ones.
    final rows = ledger.entries.reversed.toList();
    return Column(
      children: [
        _SummaryHeader(
          title: widget.propertyTitle,
          collectedLabel: _shekel(collected),
          debtLabel: _shekel(debt),
          hasDebt: debt > 0,
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final entry = rows[i];
              // Map back to the index in the (ascending) ledger list.
              final realIndex = ledger.entries.length - 1 - i;
              return _MonthRow(
                monthLabel: _monthLabel(entry),
                amountLabel: _shekel(entry.amount),
                paid: entry.paid,
                overdue: entry.isOverdue(),
                onTap: () => _togglePaid(realIndex),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.title,
    required this.collectedLabel,
    required this.debtLabel,
    required this.hasDebt,
  });

  final String title;
  final String collectedLabel;
  final String debtLabel;
  final bool hasDebt;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textOnPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _SummaryTile(
                  label: 'נגבה החודש',
                  value: collectedLabel,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryTile(
                  label: 'חוב',
                  value: debtLabel,
                  color: hasDebt ? AppColors.coral : AppColors.success,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthRow extends StatelessWidget {
  const _MonthRow({
    required this.monthLabel,
    required this.amountLabel,
    required this.paid,
    required this.overdue,
    required this.onTap,
  });

  final String monthLabel;
  final String amountLabel;
  final bool paid;
  final bool overdue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor =
        paid ? AppColors.success : (overdue ? AppColors.coral : AppColors.warning);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      elevation: 1,
      shadowColor: AppColors.shadow,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      monthLabel,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      amountLabel,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: statusColor, width: 2),
                ),
                child: Text(
                  paid ? 'שולם ✓' : 'לא שולם',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.onStart});

  final String title;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.receipt_long,
              size: 96,
              color: AppColors.textDisabled,
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'עדיין לא עקבת אחרי תשלומים — נתחיל?',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 19,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.textOnPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: onStart,
                child: const Text(
                  'התחל מעקב (12 חודשים)',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
