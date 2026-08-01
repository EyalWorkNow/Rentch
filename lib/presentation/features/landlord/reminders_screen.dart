import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/notification_service.dart';
import 'package:dating_app/data/models/rental_contract.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
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
    if (result == null) return;

    await _notifications.scheduleReminder(
      id: result.id,
      title: 'תזכורת',
      body: result.text,
      when: result.when,
    );
    if (mounted) setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('התזכורת נשמרה')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.cloud,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          surfaceTintColor: AppColors.background,
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'תזכורות',
            style: TextStyle(
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
          label: const Text(
            'תזכורת חדשה',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
        body: Consumer<DatingProvider>(
          builder: (context, provider, _) {
            final leases = _landlordLeases(provider);
            return ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                _intro(),
                const SizedBox(height: 20),
                _sectionTitle('סיום חוזה'),
                const SizedBox(height: 8),
                if (_scheduling)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (leases.isEmpty)
                  _emptyCard('אין חוזים חתומים כרגע. כשתחתום על חוזה, '
                      'נזכיר לך חודש ושבוע לפני שהוא מסתיים.')
                else
                  ...leases.map(_leaseCard),
                const SizedBox(height: 28),
                _sectionTitle('תזכורות שלי'),
                const SizedBox(height: 8),
                _ManualRemindersList(notifications: _notifications),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _intro() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primaryLight2,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Text(
        'כאן לא שוכחים. נזכיר לך מתי חוזה עומד להסתיים ומתי לגבות שכר דירה.',
        style: TextStyle(
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

  Widget _leaseCard(RentalContract c) {
    final days = c.endDate.difference(DateTime.now()).inDays;
    final title = c.propertyTitle.trim().isEmpty ? 'הדירה' : c.propertyTitle.trim();
    final String when;
    if (days < 0) {
      when = 'החוזה כבר הסתיים';
    } else if (days == 0) {
      when = 'החוזה מסתיים היום';
    } else if (days == 1) {
      when = 'מסתיים מחר';
    } else {
      when = 'מסתיים בעוד $days ימים';
    }
    return _card(
      icon: Icons.event_available_outlined,
      title: 'החוזה בדירה "$title"',
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
    await widget.notifications.cancel(row.id);
    await widget.notifications.scheduleReminder(
      id: result.id,
      title: 'תזכורת',
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
      const SnackBar(content: Text('התזכורת הועברה לארכיון')),
    );
  }

  static const String _archiveKey = 'reminders_archive_v1';

  @override
  Widget build(BuildContext context) {
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
            child: const Text(
              'אין תזכורות אישיות. אפשר להוסיף, למשל: "לגבות שכר ב-10 בחודש".',
              style: TextStyle(
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
                      tooltip: 'פעולות',
                      onSelected: (v) {
                        if (v == 'edit') _edit(r);
                        if (v == 'archive') _archive(r);
                        if (v == 'delete') _delete(r.id);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(children: [
                            Icon(Icons.edit_outlined, size: 20),
                            SizedBox(width: 10),
                            Text('עריכה'),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'archive',
                          child: Row(children: [
                            Icon(Icons.archive_outlined, size: 20),
                            SizedBox(width: 10),
                            Text('העברה לארכיון'),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(children: [
                            Icon(Icons.delete_outline,
                                size: 20, color: AppColors.coral),
                            SizedBox(width: 10),
                            Text('מחיקה',
                                style: TextStyle(color: AppColors.coral)),
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
    text: widget.initialText ?? 'לגבות שכר דירה',
  );
  late DateTime _when = widget.initialWhen ?? _defaultWhen();

  /// Default to the 10th of next month at 9:00 — the common rent-due cadence.
  static DateTime _defaultWhen() {
    final now = DateTime.now();
    final base = DateTime(now.year, now.month, 10, 9);
    return base.isAfter(now) ? base : DateTime(now.year, now.month + 1, 10, 9);
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
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Directionality(
      textDirection: TextDirection.rtl,
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
            const Text(
              'תזכורת חדשה',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'מה להזכיר לך?',
              style: TextStyle(
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
                hintText: 'למשל: לגבות שכר ב-10 בחודש',
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
                        'מתי: ${_fmt(_when)}',
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
                child: const Text(
                  'שמירת תזכורת',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
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
