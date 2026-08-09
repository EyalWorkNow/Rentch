import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/notification_service.dart';
import 'package:dating_app/data/models/rental_contract.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

/// Gentle, large-text reminders hub for landlords (older audience).
///
/// Two kinds of reminder live here:
///   • Lease-expiry nudges, derived automatically from the landlord's signed
///     contracts (~30 / ~7 days before each lease ends), and
///   • Manual reminders the landlord adds, e.g. "הזכר לי לגבות שכר ב-10 בחודש".
///
/// Scheduling goes through [NotificationService] (fail-soft), so nothing on this
/// screen can throw an alarm/permission error into the UI.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  final NotificationService _notifications = NotificationService.instance;
  bool _scheduling = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    await _notifications.requestPermissions();
    await _scheduleLeaseRemindersFromContracts();
    if (mounted) setState(() => _scheduling = false);
  }

  /// Reads the landlord's signed contracts (READ-ONLY) and schedules a
  /// lease-expiry reminder for each. Re-scheduling is idempotent: the same
  /// contract maps to the same notification ids inside [NotificationService].
  Future<void> _scheduleLeaseRemindersFromContracts() async {
    final provider = context.read<DatingProvider>();
    for (final c in _landlordLeases(provider)) {
      await _notifications.scheduleLeaseExpiry(
        propertyTitle: c.propertyTitle,
        endDate: c.endDate,
        contractId: c.id,
      );
    }
  }

  /// Signed leases where this landlord is a party, sorted by soonest end date.
  List<RentalContract> _landlordLeases(DatingProvider provider) {
    final myId = provider.tenantProfile?.id.trim() ?? '';
    final leases = provider.contracts.where((c) {
      final isMine = myId.isEmpty || c.landlordUserId == myId;
      return isMine && c.isLandlordSigned;
    }).toList()
      ..sort((a, b) => a.endDate.compareTo(b.endDate));
    return leases;
  }

  Future<void> _addManualReminder() async {
    final result = await showModalBottomSheet<_ManualReminder>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddReminderSheet(),
    );
    if (result == null || !mounted) return;
    final l10n = AppLocalizations.of(context)!;

    await _notifications.scheduleReminder(
      id: result.id,
      title: l10n.remindersScreen409fc735,
      body: result.text,
      when: result.when,
    );
    if (mounted) setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.remindersScreenF6789864)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        backgroundColor: AppColors.cloud,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          surfaceTintColor: AppColors.background,
          elevation: 0,
          centerTitle: true,
          title: Text(
            l10n.remindersScreenCa25d18a,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addManualReminder,
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          icon: const Icon(Icons.add, size: 26),
          label: Text(
            l10n.remindersScreen1d935aa3,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
        body: Consumer<DatingProvider>(
          builder: (context, provider, _) {
            final leases = _landlordLeases(provider);
            return ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                _intro(l10n),
                const SizedBox(height: 20),
                _sectionTitle(l10n.remindersScreen9d1d367d),
                const SizedBox(height: 8),
                if (_scheduling)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (leases.isEmpty)
                  _emptyCard(l10n.remindersScreen3e064b53 +
                      l10n.remindersScreen4c157f3a)
                else
                  ...leases.map((c) => _leaseCard(l10n, c)),
                const SizedBox(height: 28),
                _sectionTitle(l10n.remindersScreen3c8688c4),
                const SizedBox(height: 8),
                _ManualRemindersList(notifications: _notifications),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _intro(AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primaryLight2,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        l10n.remindersScreen4ae2e566,
        style: const TextStyle(
          fontSize: 18,
          height: 1.5,
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
      ),
    );
  }

  Widget _leaseCard(AppLocalizations l10n, RentalContract c) {
    final days = c.endDate.difference(DateTime.now()).inDays;
    final title = c.propertyTitle.trim().isEmpty
        ? l10n.remindersScreen3b042ffd
        : c.propertyTitle.trim();
    final String when;
    if (days < 0) {
      when = l10n.remindersScreenBf84b357;
    } else if (days == 0) {
      when = l10n.remindersScreen9d434107;
    } else if (days == 1) {
      when = l10n.remindersScreen4d2730e7;
    } else {
      when = l10n.remindersScreenC67b1a11(days);
    }
    return _card(
      icon: Icons.event_available_outlined,
      title: l10n.remindersScreenD66ef141(title),
      subtitle: '$when (${_fmtDate(c.endDate)})',
    );
  }

  Widget _emptyCard(String text) {
    return _card(
      icon: Icons.check_circle_outline,
      title: text,
      subtitle: null,
    );
  }

  Widget _card({required IconData icon, required String title, String? subtitle}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: const [
          BoxShadow(color: AppColors.shadow, blurRadius: 14, offset: Offset(0, 6)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.primaryLight2,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppColors.primaryDark, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

/// The landlord's manually-added reminders, read from the OS pending queue so the
/// list survives app restarts.
class _ManualRemindersList extends StatefulWidget {
  _ManualRemindersList({required this.notifications});
  final NotificationService notifications;

  @override
  State<_ManualRemindersList> createState() => _ManualRemindersListState();
}

class _ManualRemindersListState extends State<_ManualRemindersList> {
  late Future<List<_PendingRow>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    // NOTE: fallback only, kept as a plain literal — this runs from initState
    // (before AppLocalizations.of(context) is safe to call) and is normally
    // unreachable since every reminder this app schedules sets a title/body.
    _future = widget.notifications.pending().then((all) => all
        .where((p) => p.id < NotificationService.leaseIdBase)
        .map((p) => _PendingRow(id: p.id, text: p.body ?? p.title ?? 'תזכורת'))
        .toList());
  }

  Future<void> _delete(int id) async {
    await widget.notifications.cancel(id);
    if (!mounted) return; // guard: user may have popped mid-await
    setState(_reload);
  }

  // Re-open the sheet pre-filled, then reschedule (cancel old → schedule new).
  Future<void> _edit(_PendingRow row) async {
    final result = await showModalBottomSheet<_ManualReminder>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddReminderSheet(initialText: row.text),
    );
    if (result == null || !mounted) return;
    final l10n = AppLocalizations.of(context)!;
    await widget.notifications.cancel(row.id);
    await widget.notifications.scheduleReminder(
      id: result.id,
      title: l10n.remindersScreen409fc735,
      body: result.text,
      when: result.when,
    );
    if (!mounted) return;
    setState(_reload);
  }

  // Archive = cancel the scheduled alert but KEEP the text in a local archive
  // (SharedPreferences), so it's not lost and can be restored/reviewed.
  Future<void> _archive(_PendingRow row) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_archiveKey) ?? <String>[];
    list.add(row.text);
    await prefs.setStringList(_archiveKey, list);
    await widget.notifications.cancel(row.id);
    if (!mounted) return;
    setState(_reload);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text(AppLocalizations.of(context)!.remindersScreenD0680cb9)),
    );
  }

  static const String _archiveKey = 'reminders_archive_v1';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<List<_PendingRow>>(
      future: _future,
      builder: (context, snap) {
        final rows = snap.data ?? const <_PendingRow>[];
        if (rows.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Text(
              l10n.remindersScreen0ee389c1,
              style: const TextStyle(
                fontSize: 16,
                height: 1.5,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          );
        }
        return Column(
          children: [
            for (final r in rows)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Row(
                  children: [
                    Icon(Icons.notifications_active_outlined,
                        color: AppColors.primaryDark, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        r.text,
                        style: const TextStyle(
                          fontSize: 17,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert,
                          color: AppColors.textSecondary),
                      tooltip: l10n.remindersScreenC6e2f375,
                      onSelected: (v) {
                        if (v == 'edit') _edit(r);
                        if (v == 'archive') _archive(r);
                        if (v == 'delete') _delete(r.id);
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(children: [
                            const Icon(Icons.edit_outlined, size: 20),
                            const SizedBox(width: 10),
                            Text(l10n.remindersScreen39fe2593),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'archive',
                          child: Row(children: [
                            const Icon(Icons.archive_outlined, size: 20),
                            const SizedBox(width: 10),
                            Text(l10n.remindersScreenEd0727e5),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(children: [
                            const Icon(Icons.delete_outline,
                                size: 20, color: AppColors.coral),
                            const SizedBox(width: 10),
                            Text(l10n.remindersScreen7c8173fa,
                                style:
                                    const TextStyle(color: AppColors.coral)),
                          ]),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PendingRow {
  const _PendingRow({required this.id, required this.text});
  final int id;
  final String text;
}

/// Bottom sheet that captures a manual reminder: free text + a date/time.
class _AddReminderSheet extends StatefulWidget {
  _AddReminderSheet({this.initialText, this.initialWhen});
  final String? initialText;
  final DateTime? initialWhen;

  @override
  State<_AddReminderSheet> createState() => _AddReminderSheetState();
}

class _AddReminderSheetState extends State<_AddReminderSheet> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initialText ?? '',
  );
  late DateTime _when = widget.initialWhen ?? _defaultWhen();
  bool _defaultTextSet = false;

  /// Default to the 10th of next month at 9:00 — the common rent-due cadence.
  static DateTime _defaultWhen() {
    final now = DateTime.now();
    final base = DateTime(now.year, now.month, 10, 9);
    return base.isAfter(now) ? base : DateTime(now.year, now.month + 1, 10, 9);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Fill the localized default suggestion once, only for a brand-new
    // (non-edit) reminder — can't do this at field-init time since it needs
    // BuildContext, which isn't ready until after initState.
    if (!_defaultTextSet && widget.initialText == null) {
      _defaultTextSet = true;
      _text.text = AppLocalizations.of(context)!.remindersScreen6ee55398;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: now,
      lastDate: DateTime(now.year + 3),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _when.hour, minute: _when.minute),
    );
    if (!mounted) return;
    setState(() {
      _when = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? 9,
        time?.minute ?? 0,
      );
    });
  }

  void _save() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    // Unique-enough id below leaseIdBase so it never collides with lease ids.
    final id = DateTime.now().millisecondsSinceEpoch.remainder(900000);
    Navigator.of(context).pop(_ManualReminder(id: id, text: text, when: _when));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Directionality(
      textDirection: Directionality.of(context),
      child: Container(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.remindersScreen1d935aa3,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              l10n.remindersScreen8dcb89b4,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _text,
              style: const TextStyle(fontSize: 18, color: AppColors.textPrimary),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.cloud,
                hintText: l10n.remindersScreen634d3915,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.cloud,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        color: AppColors.primaryDark),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n.remindersScreenFa3782fd(_fmt(_when)),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_left, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.textOnPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  l10n.remindersScreen276878c2,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} $hh:$mm';
  }
}

class _ManualReminder {
  const _ManualReminder({required this.id, required this.text, required this.when});
  final int id;
  final String text;
  final DateTime when;
}
