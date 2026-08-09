import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/notification_service.dart';
import 'package:dating_app/data/models/broker_exclusivity.dart';
import 'package:dating_app/data/repositories/broker_exclusivity_repository.dart';
import 'package:flutter/material.dart';

/// בלעדיות — exclusivity-mandate tracker.
///
/// Lists the broker's mandates, sorted soonest-ending first, and prominently
/// flags any that expire within 14 days (or have already expired) so the broker
/// renews before losing the exclusive right — and the commission. Local CRUD
/// via [BrokerExclusivityRepository]; no backend.
class BrokerExclusivityScreen extends StatefulWidget {
  const BrokerExclusivityScreen({super.key, this.repository});

  /// Injectable for tests; defaults to the SharedPreferences-backed repo.
  final BrokerExclusivityRepository? repository;

  @override
  State<BrokerExclusivityScreen> createState() =>
      _BrokerExclusivityScreenState();
}

class _BrokerExclusivityScreenState extends State<BrokerExclusivityScreen> {
  late final BrokerExclusivityRepository _repo =
      widget.repository ?? BrokerExclusivityRepository();
  final NotificationService _notifications = NotificationService.instance;

  List<BrokerExclusivity> _mandates = const [];
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
      _mandates = list;
      _loading = false;
    });
    // Re-arm reminders on every load — a reminder the OS dropped (reboot, app
    // update) is recreated here, so "don't miss a renewal" actually holds even
    // if the broker rarely opens the tool.
    for (final m in list) {
      await _scheduleReminder(m);
    }
  }

  /// Schedule a renewal nudge 7 days before the mandate ends (09:00). If that's
  /// already past but the mandate isn't expired, remind tomorrow morning.
  /// Expired → cancel. Fail-soft inside NotificationService.
  Future<void> _scheduleReminder(BrokerExclusivity m) async {
    final id = _notifications.exclusivityReminderId(m.id);
    final now = DateTime.now();
    if (m.isExpired(now)) {
      await _notifications.cancel(id);
      return;
    }
    var when = DateTime(m.endDate.year, m.endDate.month, m.endDate.day, 9)
        .subtract(const Duration(days: 7));
    if (when.isBefore(now.add(const Duration(minutes: 1)))) {
      when = DateTime(now.year, now.month, now.day + 1, 9);
    }
    final what = m.propertyTitle.trim().isEmpty
        ? 'הבלעדיות'
        : 'הבלעדיות על ${m.propertyTitle.trim()}';
    await _notifications.scheduleReminder(
      id: id,
      title: 'חידוש בלעדיות',
      body: '$what מסתיימת ב-${_date(m.endDate)}. כדאי לחדש לפני שתפוג.',
      when: when,
    );
  }

  Future<void> _openEditor([BrokerExclusivity? existing]) async {
    final result = await showModalBottomSheet<BrokerExclusivity>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExclusivityEditor(existing: existing),
    );
    if (result == null) return;
    await _repo.save(result);
    await _scheduleReminder(result);
    await _reload();
  }

  Future<void> _delete(BrokerExclusivity m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: Directionality.of(context),
        child: AlertDialog(
          title: const Text('למחוק את הבלעדיות?'),
          content: Text(m.propertyTitle.trim().isEmpty
              ? 'הרשומה תימחק לצמיתות.'
              : '"${m.propertyTitle.trim()}" תימחק לצמיתות.'),
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
    await _notifications.cancel(_notifications.exclusivityReminderId(m.id));
    await _repo.delete(m.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('בלעדיות'),
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
          label: const Text('בלעדיות חדשה',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _mandates.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'אין בלעדיות פעילה.\nהוסף בלעדיות כדי לעקוב אחר תאריך הסיום.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 18, color: AppColors.textSecondary),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    itemCount: _mandates.length,
                    itemBuilder: (_, i) => _card(_mandates[i], now),
                  ),
      ),
    );
  }

  Widget _card(BrokerExclusivity m, DateTime now) {
    final days = m.daysUntilEnd(now);
    final expired = m.isExpired(now);
    final soon = m.isExpiringSoon(now);

    String banner;
    Color bannerColor;
    if (expired) {
      banner = 'הבלעדיות פגה לפני ${-days} ימים';
      bannerColor = AppColors.error;
    } else if (soon) {
      banner = 'בלעדיות מסתיימת בעוד $days ימים';
      bannerColor = AppColors.warning;
    } else {
      banner = 'בתוקף · עוד $days ימים';
      bannerColor = AppColors.success;
    }

    final flagged = expired || soon;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: flagged ? bannerColor : AppColors.borderLight,
          width: flagged ? 1.6 : 1,
        ),
        boxShadow: const [
          BoxShadow(color: AppColors.shadow, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: bannerColor.withValues(alpha: 0.12),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              children: [
                Icon(
                  expired
                      ? Icons.error_outline
                      : soon
                          ? Icons.access_time
                          : Icons.verified_outlined,
                  color: bannerColor,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(banner,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: bannerColor)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.propertyTitle.isEmpty ? 'נכס ללא שם' : m.propertyTitle,
                    style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 6),
                _line(Icons.person_outline, m.ownerName),
                if (m.ownerPhone.trim().isNotEmpty)
                  _line(Icons.phone_outlined, m.ownerPhone),
                _line(
                  Icons.event_outlined,
                  '${_date(m.startDate)}  ←  ${_date(m.endDate)}',
                ),
                if (m.commissionPct > 0)
                  _line(Icons.percent_outlined,
                      'עמלה: ${_pct(m.commissionPct)}%'),
                if (m.notes.trim().isNotEmpty)
                  _line(Icons.notes_outlined, m.notes),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _openEditor(m),
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      label: const Text('עריכה'),
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.primaryDark),
                    ),
                    TextButton.icon(
                      onPressed: () => _delete(m),
                      icon: const Icon(Icons.delete_outline, size: 20),
                      label: const Text('מחיקה'),
                      style:
                          TextButton.styleFrom(foregroundColor: AppColors.error),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 15, color: AppColors.textPrimary)),
            ),
          ],
        ),
      );
}

class _ExclusivityEditor extends StatefulWidget {
  _ExclusivityEditor({this.existing});

  final BrokerExclusivity? existing;

  @override
  State<_ExclusivityEditor> createState() => _ExclusivityEditorState();
}

class _ExclusivityEditorState extends State<_ExclusivityEditor> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.propertyTitle ?? '');
  late final TextEditingController _owner =
      TextEditingController(text: widget.existing?.ownerName ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.existing?.ownerPhone ?? '');
  late final TextEditingController _commission = TextEditingController(
      text: (widget.existing?.commissionPct ?? 0) == 0
          ? ''
          : _pct(widget.existing!.commissionPct));
  late final TextEditingController _notes =
      TextEditingController(text: widget.existing?.notes ?? '');

  late DateTime _start = widget.existing?.startDate ?? DateTime.now();
  late DateTime _end = widget.existing?.endDate ??
      DateTime.now().add(const Duration(days: 90));

  @override
  void dispose() {
    _title.dispose();
    _owner.dispose();
    _phone.dispose();
    _commission.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isStart) async {
    final initial = isStart ? _start : _end;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  void _submit() {
    final base = widget.existing;
    final id =
        base?.id ?? 'excl_${DateTime.now().microsecondsSinceEpoch}';
    final mandate = BrokerExclusivity(
      id: id,
      propertyTitle: _title.text.trim(),
      ownerName: _owner.text.trim(),
      ownerPhone: _phone.text.trim(),
      startDate: _start,
      endDate: _end,
      commissionPct: double.tryParse(_commission.text.trim()) ?? 0,
      notes: _notes.text.trim(),
    );
    Navigator.of(context).pop(mandate);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Directionality(
      textDirection: Directionality.of(context),
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
                widget.existing == null ? 'בלעדיות חדשה' : 'עריכת בלעדיות',
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 16),
              _field(_title, 'כתובת / שם הנכס'),
              _field(_owner, 'שם בעל הנכס'),
              _field(_phone, 'טלפון בעל הנכס',
                  keyboardType: TextInputType.phone),
              _field(_commission, 'אחוז עמלה (%)',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true)),
              Row(
                children: [
                  Expanded(child: _dateTile('תחילת בלעדיות', _start, true)),
                  const SizedBox(width: 12),
                  Expanded(child: _dateTile('סיום בלעדיות', _end, false)),
                ],
              ),
              const SizedBox(height: 12),
              _field(_notes, 'הערות', maxLines: 2),
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
      {TextInputType? keyboardType, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: keyboardType,
        maxLines: maxLines,
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

  Widget _dateTile(String label, DateTime value, bool isStart) {
    return InkWell(
      onTap: () => _pickDate(isStart),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.primaryLight2,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(_date(value),
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _pct(double v) => v % 1 == 0 ? v.toInt().toString() : v.toString();
