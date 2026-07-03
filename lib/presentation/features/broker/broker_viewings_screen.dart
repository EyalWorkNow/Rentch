import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/notification_service.dart';
import 'package:dating_app/data/models/broker_viewing.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/data/repositories/broker_viewing_repository.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// תיאום צפיות + תזכורות — a broker's viewing scheduler.
///
/// Upcoming scheduled viewings are shown soonest-first; past/closed ones sit in
/// a collapsed history below. The screen does two jobs brokers actually lose
/// money on: it FLAGS any two scheduled viewings whose times overlap (a red
/// "התנגשות בלו"ז" badge on each clashing card), and it schedules a local
/// reminder ~1 hour before each viewing via [NotificationService] (fail-soft —
/// if the API or permission isn't there, the in-app list is still the source of
/// truth). Local-only via [BrokerViewingRepository]; provider read READ-ONLY for
/// the property picker.
class BrokerViewingsScreen extends StatefulWidget {
  const BrokerViewingsScreen({super.key});

  @override
  State<BrokerViewingsScreen> createState() => _BrokerViewingsScreenState();
}

class _BrokerViewingsScreenState extends State<BrokerViewingsScreen> {
  final BrokerViewingRepository _repo = BrokerViewingRepository();
  final NotificationService _notifications = NotificationService.instance;

  /// Reserved notification id-space so viewing reminders never collide with the
  /// landlord lease/saved-search ranges in [NotificationService].
  static const int _reminderIdBase = 3000000;

  List<BrokerViewing> _viewings = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    assert(BrokerViewing.debugSelfCheck());
    _load();
  }

  Future<void> _load() async {
    final viewings = await _repo.loadAll();
    if (!mounted) return;
    setState(() {
      _viewings = viewings;
      _loading = false;
    });
  }

  Future<void> _save(BrokerViewing viewing) async {
    final next = await _repo.save(viewing);
    if (!mounted) return;
    setState(() => _viewings = next);
    _scheduleReminder(viewing);
  }

  Future<void> _delete(String id) async {
    final next = await _repo.delete(id);
    if (!mounted) return;
    setState(() => _viewings = next);
    await _notifications.cancel(_reminderIdBase + _viewingKey(id));
  }

  /// Schedule a one-hour-before nudge. Fail-soft inside NotificationService; we
  /// only schedule for still-scheduled, future viewings.
  Future<void> _scheduleReminder(BrokerViewing v) async {
    final id = _reminderIdBase + _viewingKey(v.id);
    if (v.status != ViewingStatus.scheduled) {
      await _notifications.cancel(id);
      return;
    }
    final who = v.clientName.trim().isEmpty ? 'הלקוח' : v.clientName.trim();
    final where = v.propertyTitle.trim().isEmpty ? '' : ' — ${v.propertyTitle.trim()}';
    await _notifications.scheduleReminder(
      id: id,
      title: 'צפייה בעוד שעה',
      body: 'צפייה עם $who בשעה ${_timeLabel(v.dateTime)}$where',
      when: v.dateTime.subtract(const Duration(hours: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final clashingIds = _clashingIds(_viewings);

    final upcoming = _viewings
        .where((v) => v.status == ViewingStatus.scheduled)
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    final history = _viewings
        .where((v) => v.status != ViewingStatus.scheduled)
        .toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

    final hasClash = clashingIds.isNotEmpty;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6FB),
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: const Text(
            'תיאום צפיות',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          onPressed: _openSchedule,
          icon: const Icon(Icons.add),
          label: const Text(
            'צפייה חדשה',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _viewings.isEmpty
                ? _emptyState()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      if (hasClash) _clashBanner(clashingIds.length),
                      _sectionHeader('צפיות קרובות', upcoming.length),
                      if (upcoming.isEmpty)
                        _hint('אין צפיות מתוכננות')
                      else
                        for (final v in upcoming)
                          _viewingCard(v, clashingIds.contains(v.id), now),
                      if (history.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _sectionHeader('היסטוריה', history.length),
                        for (final v in history)
                          _viewingCard(v, false, now),
                      ],
                    ],
                  ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_available_outlined,
                size: 72, color: AppColors.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            const Text('אין עדיין צפיות',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'תאמו צפייה ותקבלו תזכורת שעה לפני',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _clashBanner(int count) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.coral, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.coral, size: 26),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'יש $count צפיות שמתנגשות בלו"ז — בדקו את הסימון האדום',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.coral,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Text('($count)',
              style: const TextStyle(
                  fontSize: 17, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _hint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Text(text,
          style: const TextStyle(
              fontSize: 16, color: AppColors.textSecondary)),
    );
  }

  Widget _viewingCard(BrokerViewing v, bool clashes, DateTime now) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: clashes
            ? const BorderSide(color: AppColors.coral, width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openViewingActions(v),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _dateTimeLabel(v.dateTime),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  _statusChip(v.status),
                ],
              ),
              if (clashes) ...[
                const SizedBox(height: 6),
                Row(
                  children: const [
                    Icon(Icons.warning_amber_rounded,
                        size: 18, color: AppColors.coral),
                    SizedBox(width: 4),
                    Text('התנגשות בלו"ז',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppColors.coral)),
                  ],
                ),
              ],
              if (v.clientName.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.person_outline,
                        size: 17, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(v.clientName,
                        style: const TextStyle(fontSize: 16)),
                  ],
                ),
              ],
              if (v.propertyTitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.home_outlined,
                        size: 17, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(v.propertyTitle,
                          style: const TextStyle(
                              fontSize: 15,
                              color: AppColors.textSecondary)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(ViewingStatus status) {
    Color color;
    switch (status) {
      case ViewingStatus.scheduled:
        color = AppColors.primary;
        break;
      case ViewingStatus.completed:
        color = AppColors.success;
        break;
      case ViewingStatus.noShow:
        color = AppColors.coral;
        break;
      case ViewingStatus.cancelled:
        color = AppColors.textSecondary;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(status.hebrew,
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: color)),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _openViewingActions(BrokerViewing v) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _dateTimeLabel(v.dateTime),
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _actionTile(sheetContext, Icons.check_circle_outline,
                      'סמן: התקיימה', AppColors.success, () {
                    _save(v.copyWith(status: ViewingStatus.completed));
                  }),
                  _actionTile(sheetContext, Icons.person_off_outlined,
                      'סמן: לא הגיע', AppColors.coral, () {
                    _save(v.copyWith(status: ViewingStatus.noShow));
                  }),
                  _actionTile(sheetContext, Icons.cancel_outlined,
                      'סמן: בוטלה', AppColors.textSecondary, () {
                    _save(v.copyWith(status: ViewingStatus.cancelled));
                  }),
                  if (v.status != ViewingStatus.scheduled)
                    _actionTile(sheetContext, Icons.event_repeat,
                        'החזר לתכנון', AppColors.primary, () {
                      _save(v.copyWith(status: ViewingStatus.scheduled));
                    }),
                  const Divider(),
                  _actionTile(sheetContext, Icons.delete_outline,
                      'מחיקה', AppColors.coral, () {
                    _delete(v.id);
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _actionTile(BuildContext sheetContext, IconData icon, String label,
      Color color, VoidCallback onTap) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(fontSize: 17, color: color)),
      onTap: () {
        Navigator.pop(sheetContext);
        onTap();
      },
    );
  }

  Future<void> _openSchedule() async {
    final myProperties = context.read<DatingProvider>().myProperties;
    final viewing = await showModalBottomSheet<BrokerViewing>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ScheduleViewingSheet(properties: myProperties),
    );
    if (viewing != null) await _save(viewing);
  }

  // ── Clash detection ─────────────────────────────────────────────────────────

  /// Ids of every viewing that overlaps at least one other scheduled viewing.
  /// O(n²) is fine — a broker has a handful of slots, not thousands.
  static Set<String> _clashingIds(List<BrokerViewing> viewings) {
    final clashing = <String>{};
    for (var i = 0; i < viewings.length; i++) {
      for (var j = i + 1; j < viewings.length; j++) {
        if (viewings[i].clashesWith(viewings[j])) {
          clashing.add(viewings[i].id);
          clashing.add(viewings[j].id);
        }
      }
    }
    return clashing;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  int _viewingKey(String id) {
    var h = 0;
    for (final unit in id.codeUnits) {
      h = (h * 31 + unit) & 0xFFFFF;
    }
    return h;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _timeLabel(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';
  static String _dateTimeLabel(DateTime d) =>
      '${_two(d.day)}/${_two(d.month)}/${d.year}  ${_timeLabel(d)}';
}

/// Bottom sheet collecting a new viewing. Returns a [BrokerViewing] on save.
class _ScheduleViewingSheet extends StatefulWidget {
  const _ScheduleViewingSheet({required this.properties});

  final List<RentalProperty> properties;

  @override
  State<_ScheduleViewingSheet> createState() => _ScheduleViewingSheetState();
}

class _ScheduleViewingSheetState extends State<_ScheduleViewingSheet> {
  final _client = TextEditingController();
  final _phone = TextEditingController();
  RentalProperty? _property;
  DateTime? _dateTime;

  @override
  void dispose() {
    _client.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _dateTime ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
          _dateTime ?? now.add(const Duration(hours: 1))),
    );
    if (time == null) return;
    setState(() {
      _dateTime =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  void _submit() {
    final client = _client.text.trim();
    if (_dateTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('יש לבחור תאריך ושעה')),
      );
      return;
    }
    if (client.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('יש להזין שם לקוח')),
      );
      return;
    }
    Navigator.pop(
      context,
      BrokerViewing(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        dateTime: _dateTime!,
        propertyId: _property?.id ?? '',
        propertyTitle: _property == null ? '' : _propertyLabel(_property!),
        clientName: client,
        phone: _phone.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(
                child: Text('צפייה חדשה',
                    style: TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 20),
              const Text('נכס:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              DropdownButtonFormField<RentalProperty?>(
                initialValue: _property,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                  ),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                hint: const Text('בחר נכס (לא חובה)'),
                items: [
                  const DropdownMenuItem<RentalProperty?>(
                    value: null,
                    child: Text('ללא נכס'),
                  ),
                  for (final p in widget.properties)
                    DropdownMenuItem<RentalProperty?>(
                      value: p,
                      child: Text(_propertyLabel(p),
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (p) => setState(() => _property = p),
              ),
              const SizedBox(height: 16),
              _field(_client, 'שם הלקוח *', TextInputType.name),
              const SizedBox(height: 12),
              _field(_phone, 'טלפון', TextInputType.phone),
              const SizedBox(height: 16),
              InkWell(
                onTap: _pickDateTime,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.borderLight),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.event, color: AppColors.primary),
                      const SizedBox(width: 12),
                      Text(
                        _dateTime == null
                            ? 'בחר תאריך ושעה *'
                            : _dateTimeLabel(_dateTime!),
                        style: const TextStyle(fontSize: 17),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _submit,
                  child: const Text('שמירה',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
      TextEditingController c, String label, TextInputType type) {
    return TextField(
      controller: c,
      keyboardType: type,
      style: const TextStyle(fontSize: 17),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 16),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _dateTimeLabel(DateTime d) =>
      '${_two(d.day)}/${_two(d.month)}/${d.year}  ${_two(d.hour)}:${_two(d.minute)}';

  static String _propertyLabel(RentalProperty p) {
    final street = p.street.trim();
    final city = p.city.trim();
    if (street.isNotEmpty && city.isNotEmpty) return '$street, $city';
    if (street.isNotEmpty) return street;
    if (city.isNotEmpty) return city;
    return p.propertyType;
  }
}
