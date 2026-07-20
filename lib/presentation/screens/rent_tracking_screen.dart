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
    final bool isBroker = AppColors.isBrokerAccent;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.navy,
          elevation: 0,
          title: const Text('מעקב תשלומים'),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(color: AppColors.divider, height: 1, thickness: 1),
          ),
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
                    backgroundColor: isBroker ? Colors.black : AppColors.primary,
                    foregroundColor: Colors.white,
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
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 14),
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
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.slate50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.slate200, width: 1),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
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
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      shadowColor: AppColors.shadow.withValues(alpha: 0.08),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.slate200, width: 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      amountLabel,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: statusColor.withValues(alpha: 0.35), width: 1.2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (paid) ...[
                      Icon(Icons.check_circle_rounded, color: statusColor, size: 16),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      paid ? 'שולם' : 'לא שולם',
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
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
    final bool isBroker = AppColors.isBrokerAccent;
    final primaryColor = isBroker ? Colors.black : AppColors.primary;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppColors.slate50,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.slate200,
                  width: 1.2,
                ),
              ),
              child: const Icon(
                Icons.receipt_long_outlined,
                size: 60,
                color: AppColors.slate400,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'עדיין לא עקבת אחרי תשלומים — נתחיל?',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                onPressed: onStart,
                child: const Text(
                  'התחל מעקב (12 חודשים)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
