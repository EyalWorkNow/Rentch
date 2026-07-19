import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/notification_service.dart';
import 'package:dating_app/data/models/availability_slot.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/data/repositories/availability_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// היומן — the landlord's / agent's availability calendar.
///
/// The owner marks FREE viewing windows here. A 14-day strip picks the day (or
/// an "all upcoming" agenda view shows everything at once); each slot can be
/// tagged to a specific apartment, given a colored label + note, and added in
/// bulk with a repeat rule (whole week / weekdays / weekend). Booked viewings
/// arrive automatically from the chat and are tagged to their property.
///
/// The whole screen is tuned for older users: large type (≥16), tall tap
/// targets (≥56), high-contrast status colors, and text alongside every color.
/// Slots persist on-device ([AvailabilityRepository]).
class AvailabilityCalendarScreen extends StatefulWidget {
  const AvailabilityCalendarScreen({super.key});

  @override
  State<AvailabilityCalendarScreen> createState() =>
      _AvailabilityCalendarScreenState();
}

class _AvailabilityCalendarScreenState
    extends State<AvailabilityCalendarScreen> {
  final _repo = AvailabilityRepository();
  List<AvailabilitySlot> _slots = const [];
  bool _loading = true;
  bool _agenda = false; // false = single-day view, true = "all upcoming"
  late DateTime _selectedDay;
  late DateTime _stripStart; // first day shown in the 14-day strip (movable)

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);
    _stripStart = _selectedDay;
    _load();
  }

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  Future<void> _load() async {
    final all = await _repo.loadAll();
    if (!mounted) return;
    setState(() {
      _slots = all;
      _loading = false;
    });
  }

  static const _heb = ['ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת'];
  static const _monthsHeb = [
    '',
    'ינואר', 'פברואר', 'מרץ', 'אפריל', 'מאי', 'יוני',
    'יולי', 'אוגוסט', 'ספטמבר', 'אוקטובר', 'נובמבר', 'דצמבר',
  ];

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<AvailabilitySlot> _slotsOn(DateTime day) =>
      (_slots.where((s) => _sameDay(s.start, day)).toList())
        ..sort((a, b) => a.start.compareTo(b.start));

  String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _dayHeader(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = DateTime(d.year, d.month, d.day).difference(today).inDays;
    final prefix = diff == 0
        ? 'היום · '
        : diff == 1
            ? 'מחר · '
            : '';
    return '$prefix${_heb[d.weekday % 7]}, ${d.day} ${_monthsHeb[d.month]}';
  }

  // Full free date selection — any day / month / year within the next year.
  Future<void> _pickAnyDate() async {
    final today = _today;
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay.isBefore(today) ? today : _selectedDay,
      firstDate: today,
      lastDate: DateTime(today.year + 1, today.month, today.day),
      helpText: 'בחירת תאריך',
      cancelText: 'ביטול',
      confirmText: 'אישור',
      builder: (ctx, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedDay = DateTime(picked.year, picked.month, picked.day);
      _stripStart = _selectedDay; // re-anchor the strip on the chosen day
      _agenda = false;
    });
  }

  void _shiftWeek(int deltaDays) {
    setState(() {
      final s = _stripStart;
      var next = DateTime(s.year, s.month, s.day + deltaDays);
      if (next.isBefore(_today)) next = _today; // never scroll into the past
      _stripStart = next;
    });
  }

  void _jumpToday() {
    setState(() {
      _selectedDay = _today;
      _stripStart = _today;
    });
  }

  // A short apartment label for a property id ('' → general availability).
  String _propertyLabel(DatingProvider provider, String propertyId) {
    if (propertyId.isEmpty) return '';
    final p = provider.propertyById(propertyId);
    if (p == null) return '';
    final street = p.streetNumber > 0 ? '${p.street} ${p.streetNumber}' : p.street;
    return street.trim().isNotEmpty ? street.trim() : p.city;
  }

  // ── Tags ───────────────────────────────────────────────────────────────────
  static const tagPresets = ['דחוף', 'בלעדי', 'טלפוני', 'גמיש'];

  static Color tagColor(String tag) {
    switch (tag) {
      case 'דחוף':
        return AppColors.coral;
      case 'בלעדי':
        return AppColors.indigoDeep;
      case 'טלפוני':
        return AppColors.amberDark;
      case 'גמיש':
        return AppColors.tealDark;
      default:
        return AppColors.slate500;
    }
  }

  // ── Add ──────────────────────────────────────────────────────────────────

  Future<void> _openNewSlotSheet() async {
    final provider = context.read<DatingProvider>();
    final cfg = await showModalBottomSheet<_NewSlotConfig>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _NewSlotSheet(
        day: _selectedDay,
        properties: provider.myProperties,
      ),
    );
    if (cfg == null || !mounted) return;
    await _generateSlots(cfg);
  }

  // One-tap add for a common window on the selected day.
  Future<void> _quickAdd(int hour) async {
    final start = DateTime(_selectedDay.year, _selectedDay.month,
        _selectedDay.day, hour, 0);
    await _generateSlots(_NewSlotConfig(
      time: TimeOfDay(hour: hour, minute: 0),
      durationMinutes: 30,
    ), baseDay: _selectedDay, silentStart: start);
  }

  /// Expands a config into one-or-many slots (repeat rule), skipping any that
  /// clash with an existing window, and persists them.
  Future<void> _generateSlots(_NewSlotConfig cfg,
      {DateTime? baseDay, DateTime? silentStart}) async {
    final days = _repeatDays(cfg.repeat, baseDay ?? _selectedDay);
    var added = 0;
    var skipped = 0;
    var next = _slots;
    for (final day in days) {
      final start = DateTime(
          day.year, day.month, day.day, cfg.time.hour, cfg.time.minute);
      // Don't create windows in the past.
      if (start.isBefore(DateTime.now().subtract(const Duration(minutes: 1)))) {
        continue;
      }
      final slot = AvailabilitySlot(
        id: 'slot_${DateTime.now().microsecondsSinceEpoch}_$added',
        start: start,
        durationMinutes: cfg.durationMinutes,
        propertyId: cfg.propertyId,
        note: cfg.note,
        tag: cfg.tag,
      );
      if (next.any((s) => s.clashesWith(slot))) {
        skipped++;
        continue;
      }
      next = await _repo.save(slot);
      added++;
    }
    if (!mounted) return;
    setState(() => _slots = next);
    if (added == 0) {
      _toast(skipped > 0 ? 'כל החלונות כבר קיימים ביומן' : 'לא נוסף חלון');
    } else if (added == 1) {
      _toast('נוסף חלון פנוי ✅');
    } else {
      _toast('נוספו $added חלונות פנויים ✅'
          '${skipped > 0 ? ' · $skipped דילגו (חופפים)' : ''}');
    }
  }

  // Israeli work-week semantics for the repeat rule.
  List<DateTime> _repeatDays(String repeat, DateTime base) {
    switch (repeat) {
      case 'week': // the next 7 days from base
        return List.generate(
            7, (i) => DateTime(base.year, base.month, base.day + i));
      case 'weekdays': // Sun–Thu within the next 14 days
        return List.generate(
                14, (i) => DateTime(base.year, base.month, base.day + i))
            .where((d) => d.weekday != DateTime.friday &&
                d.weekday != DateTime.saturday)
            .toList();
      case 'weekend': // Fri–Sat within the next 14 days
        return List.generate(
                14, (i) => DateTime(base.year, base.month, base.day + i))
            .where((d) => d.weekday == DateTime.friday ||
                d.weekday == DateTime.saturday)
            .toList();
      case 'today':
      default:
        return [base];
    }
  }

  // ── Remove ─────────────────────────────────────────────────────────────────

  Future<void> _confirmRemove(AvailabilitySlot s) async {
    // Booked = a real viewing. Guard against an accidental one-tap wipe, and
    // cancel its 1h-before reminder so it can't fire for a cancelled viewing.
    if (!s.isOpen) {
      final who = s.bookedByName.trim().isEmpty ? 'השוכר/ת' : s.bookedByName.trim();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('לבטל צפייה מאושרת?',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
            content: Text(
              'צפייה עם $who בשעה ${_time(s.start)} תוסר מהיומן והתזכורת תבוטל.',
              style: const TextStyle(fontSize: 16, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('חזרה',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('בטל צפייה',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      );
      if (ok != true || !mounted) return;
      await NotificationService.instance
          .cancel(NotificationService.instance.viewingReminderId(s.id));
    }
    final next = await _repo.delete(s.id);
    if (!mounted) return;
    setState(() => _slots = next);
    _toast(s.isOpen ? 'החלון הוסר' : 'הצפייה בוטלה');
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      _toast('לא ניתן לחייג');
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(milliseconds: 2800),
      content: Text(m, style: const TextStyle(fontSize: 15)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    // Watch so a chat-booked viewing (processViewingConfirms) refreshes the
    // property labels + strip markers live.
    final provider = context.watch<DatingProvider>();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.cloud,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: AppColors.navy,
          titleSpacing: 16,
          title: Row(
            children: [
              Icon(IconsaxPlusBold.calendar_1, color: AppColors.primary, size: 26),
              const SizedBox(width: 10),
              const Text('היומן שלי',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 21)),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openNewSlotSheet,
          backgroundColor: AppColors.primary,
          icon: const Icon(IconsaxPlusLinear.add, size: 24),
          label: const Text('הוסף זמן פנוי',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _viewToggle(),
                  if (!_agenda) ...[
                    _dateNavBar(),
                    _weekStrip(provider),
                    const SizedBox(height: 2),
                    Expanded(child: _dayView(provider)),
                  ] else
                    Expanded(child: _agendaView(provider)),
                ],
              ),
      ),
    );
  }

  // Glass pill with a sliding gradient thumb — same visual language as the
  // apartment-search (discover) tab selector.
  Widget _viewToggle() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: SizedBox(
        height: 52,
        child: LayoutBuilder(
          builder: (context, c) {
            const pad = 5.0;
            final w = c.maxWidth;
            final inner = (w - pad * 2).clamp(0.0, double.infinity);
            final segW = inner / 2;
            // Visual order (LTR): [יום, כל הקרובים]. Thumb right when agenda.
            final thumbLeft = pad + (_agenda ? segW : 0);

            Widget seg(String label, IconData icon, bool agenda) {
              final selected = _agenda == agenda;
              return SizedBox(
                width: segW,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _agenda = agenda);
                  },
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedScale(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutBack,
                            scale: selected ? 1.12 : 1,
                            child: Icon(icon,
                                size: 19,
                                color: selected
                                    ? Colors.white
                                    : AppColors.textSecondary),
                          ),
                          const SizedBox(width: 8),
                          Text(label,
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(
                                  fontSize: 16,
                                  height: 1,
                                  fontWeight: selected
                                      ? FontWeight.w900
                                      : FontWeight.w800,
                                  color: selected
                                      ? Colors.white
                                      : AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }

            return DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.96),
                    AppColors.slate50,
                    AppColors.slate100,
                  ],
                ),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.8), width: 1.4),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.navy.withValues(alpha: 0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Stack(
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      left: thumbLeft,
                      width: segW,
                      top: pad,
                      bottom: pad,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.tealBrand,
                              AppColors.primary,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(children: [
                      seg('יום', IconsaxPlusLinear.calendar_1, false),
                      seg('כל הקרובים', IconsaxPlusLinear.task_square, true),
                    ]),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // Month label + free date picker + week navigation, above the strip.
  Widget _dateNavBar() {
    final atToday = _sameDay(_stripStart, _today);
    Widget arrow(IconData icon, VoidCallback? onTap) => GestureDetector(
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap();
                },
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: onTap == null ? AppColors.slate50 : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.slate200, width: 1.5),
            ),
            child: Icon(icon,
                size: 20,
                color: onTap == null ? AppColors.slate300 : AppColors.navy),
          ),
        );

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
      child: Row(
        children: [
          // ◀ previous week (disabled when already at today)
          arrow(IconsaxPlusLinear.arrow_right_3, atToday ? null : () => _shiftWeek(-7)),
          const SizedBox(width: 8),
          // Month · Year — tap for full free date selection
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                _pickAnyDate();
              },
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.slate50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.slate200, width: 1.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(IconsaxPlusLinear.calendar_search,
                        size: 20, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                        '${_monthsHeb[_stripStart.month]} ${_stripStart.year}',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: AppColors.navy)),
                    const SizedBox(width: 4),
                    Icon(IconsaxPlusLinear.arrow_down_1,
                        size: 16, color: AppColors.slate500),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // ▶ next week
          arrow(IconsaxPlusLinear.arrow_left_2, () => _shiftWeek(7)),
          if (!atToday) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _jumpToday,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: Text('היום',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _weekStrip(DatingProvider provider) {
    final anchor = _stripStart;
    final days = List.generate(
        14, (i) => DateTime(anchor.year, anchor.month, anchor.day + i));
    return Container(
      color: Colors.white,
      child: SizedBox(
        height: 112,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          itemCount: days.length,
          itemBuilder: (_, i) {
            final d = days[i];
            final selected = _sameDay(d, _selectedDay);
            final onDay = _slotsOn(d);
            final booked = onDay.where((s) => !s.isOpen).length;
            final open = onDay.where((s) => s.isOpen).length;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _selectedDay = d);
              },
              child: Container(
                width: 66,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: selected ? AppColors.primary : AppColors.slate200,
                      width: 1.5),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_heb[d.weekday % 7],
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color:
                                selected ? Colors.white : AppColors.slate500)),
                    const SizedBox(height: 5),
                    Text('${d.day}',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: selected ? Colors.white : AppColors.navy)),
                    const SizedBox(height: 6),
                    // Marker reflects BOTH booked (coral) and open (primary) so
                    // a fully-booked day never looks empty.
                    _stripMarker(selected: selected, booked: booked, open: open),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _stripMarker(
      {required bool selected, required int booked, required int open}) {
    if (booked == 0 && open == 0) {
      return const SizedBox(height: 8);
    }
    Widget dot(Color c) => Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
              color: selected ? Colors.white : c, shape: BoxShape.circle),
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (booked > 0) dot(AppColors.coral),
        if (open > 0) dot(AppColors.primary),
      ],
    );
  }

  Widget _dayView(DatingProvider provider) {
    final slots = _slotsOn(_selectedDay);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Text(_dayHeader(_selectedDay),
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy)),
        ),
        if (slots.isEmpty)
          Expanded(child: _emptyDay())
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
              itemCount: slots.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _slotCard(provider, slots[i]),
            ),
          ),
      ],
    );
  }

  Widget _emptyDay() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Icon(IconsaxPlusBold.calendar_add,
              size: 60, color: AppColors.slate300),
          const SizedBox(height: 14),
          const Text('אין עדיין זמנים פנויים ביום הזה',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.slate600)),
          const SizedBox(height: 6),
          Text('הוסיפו חלון מהיר, או «הוסף זמן פנוי» למטה',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.slate500)),
          const SizedBox(height: 20),
          // Quick presets — one tap adds a 30-minute window.
          Row(
            children: [
              _quickChip('בוקר', '10:00', 10),
              const SizedBox(width: 10),
              _quickChip('צהריים', '14:00', 14),
              const SizedBox(width: 10),
              _quickChip('ערב', '18:00', 18),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickChip(String label, String time, int hour) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          _quickAdd(hour);
        },
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.slate200, width: 1.5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy)),
              const SizedBox(height: 3),
              Text(time,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _agendaView(DatingProvider provider) {
    final upcoming = _slots.where((s) => s.end.isAfter(DateTime.now())).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    if (upcoming.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(IconsaxPlusBold.calendar_add,
                  size: 60, color: AppColors.slate300),
              const SizedBox(height: 14),
              const Text('אין צפיות או חלונות קרובים',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.slate600)),
            ],
          ),
        ),
      );
    }
    // Group by calendar day with a sticky-ish header per day.
    final items = <Widget>[];
    DateTime? lastDay;
    for (final s in upcoming) {
      final day = DateTime(s.start.year, s.start.month, s.start.day);
      if (lastDay == null || !_sameDay(day, lastDay)) {
        items.add(Padding(
          padding: EdgeInsets.fromLTRB(20, items.isEmpty ? 12 : 22, 20, 8),
          child: Text(_dayHeader(day),
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy)),
        ));
        lastDay = day;
      }
      items.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: _slotCard(provider, s),
      ));
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 110),
      children: items,
    );
  }

  Widget _slotCard(DatingProvider provider, AvailabilitySlot s) {
    final booked = !s.isOpen;
    final accent = booked ? AppColors.coral : AppColors.success;
    final propLabel = _propertyLabel(provider, s.propertyId);
    final who = s.bookedByName.trim();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.slate200, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Row(
              children: [
                // Status pill — icon + color band.
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                      booked
                          ? IconsaxPlusBold.user_tick
                          : IconsaxPlusBold.clock,
                      color: accent,
                      size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${_time(s.start)} – ${_time(s.end)}',
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: AppColors.navy)),
                      const SizedBox(height: 3),
                      Text(booked ? 'צפייה מאושרת' : 'פנוי לצפייה',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: accent)),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                      booked
                          ? IconsaxPlusLinear.close_circle
                          : IconsaxPlusLinear.trash,
                      color: AppColors.coral,
                      size: 24),
                  tooltip: booked ? 'בטל צפייה' : 'הסר חלון',
                  onPressed: () => _confirmRemove(s),
                ),
              ],
            ),
          ),
          // Chips row: property + tag (only when present).
          if (propLabel.isNotEmpty || s.tag.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (propLabel.isNotEmpty)
                    _chip(IconsaxPlusBold.home_2, propLabel, AppColors.navy),
                  if (s.tag.isNotEmpty)
                    _chip(IconsaxPlusBold.tag, s.tag, tagColor(s.tag)),
                ],
              ),
            ),
          if (s.note.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(s.note.trim(),
                  style: const TextStyle(
                      fontSize: 15,
                      height: 1.35,
                      color: AppColors.slate600)),
            ),
          // Booked person + quick call.
          if (booked && (who.isNotEmpty || s.bookedByPhone.trim().isNotEmpty))
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.slate100, width: 1.5)),
              ),
              child: Row(
                children: [
                  Icon(IconsaxPlusLinear.user, size: 20, color: AppColors.slate500),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(who.isEmpty ? 'שוכר/ת' : who,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.navy)),
                  ),
                  if (s.bookedByPhone.trim().isNotEmpty)
                    GestureDetector(
                      onTap: () => _call(s.bookedByPhone.trim()),
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: const [
                            Icon(IconsaxPlusBold.call, color: Colors.white, size: 20),
                            SizedBox(width: 7),
                            Text('חיוג',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

// ── New-slot sheet ───────────────────────────────────────────────────────────

/// Result of the add-slot sheet.
class _NewSlotConfig {
  _NewSlotConfig({
    required this.time,
    required this.durationMinutes,
    this.propertyId = '',
    this.repeat = 'today',
    this.tag = '',
    this.note = '',
  });

  final TimeOfDay time;
  final int durationMinutes;
  final String propertyId;
  final String repeat; // today | week | weekdays | weekend
  final String tag;
  final String note;
}

class _NewSlotSheet extends StatefulWidget {
  const _NewSlotSheet({required this.day, required this.properties});

  final DateTime day;
  final List<RentalProperty> properties;

  @override
  State<_NewSlotSheet> createState() => _NewSlotSheetState();
}

class _NewSlotSheetState extends State<_NewSlotSheet> {
  TimeOfDay _time = const TimeOfDay(hour: 17, minute: 0);
  int _duration = 30;
  String _propertyId = '';
  String _repeat = 'today';
  String _tag = '';
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _propShort(RentalProperty p) {
    final street = p.streetNumber > 0 ? '${p.street} ${p.streetNumber}' : p.street;
    return street.trim().isNotEmpty ? street.trim() : p.city;
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _time,
      helpText: 'שעת התחלה של החלון הפנוי',
    );
    if (t != null) setState(() => _time = t);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DraggableScrollableSheet(
        initialChildSize: 0.78,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.slate300,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Icon(IconsaxPlusBold.calendar_add,
                        color: AppColors.primary, size: 26),
                    const SizedBox(width: 10),
                    const Text('חלון פנוי חדש',
                        style:
                            TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                  children: [
                    _label('שעת התחלה'),
                    GestureDetector(
                      onTap: _pickTime,
                      child: Container(
                        height: 60,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        decoration: BoxDecoration(
                          color: AppColors.slate50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.slate200, width: 1.5),
                        ),
                        child: Row(
                          children: [
                            Icon(IconsaxPlusLinear.clock,
                                color: AppColors.primary, size: 24),
                            const SizedBox(width: 12),
                            Text(_fmtTime(_time),
                                style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.navy)),
                            const Spacer(),
                            Text('שינוי',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary)),
                          ],
                        ),
                      ),
                    ),
                    _label('משך'),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final m in const [30, 45, 60, 90, 120])
                          _choice(
                            label: m < 60
                                ? '$m דק׳'
                                : '${m ~/ 60}${m % 60 == 0 ? '' : '.5'} שעות',
                            selected: _duration == m,
                            onTap: () => setState(() => _duration = m),
                          ),
                      ],
                    ),
                    if (widget.properties.isNotEmpty) ...[
                      _label('דירה (רשות)'),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _choice(
                            label: 'כל הדירות',
                            icon: IconsaxPlusLinear.category,
                            selected: _propertyId.isEmpty,
                            onTap: () => setState(() => _propertyId = ''),
                          ),
                          for (final p in widget.properties)
                            _choice(
                              label: _propShort(p),
                              icon: IconsaxPlusLinear.home_2,
                              selected: _propertyId == p.id,
                              onTap: () => setState(() => _propertyId = p.id),
                            ),
                        ],
                      ),
                    ],
                    _label('חזרה'),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _choice(
                            label: 'רק היום',
                            selected: _repeat == 'today',
                            onTap: () => setState(() => _repeat = 'today')),
                        _choice(
                            label: 'כל השבוע',
                            selected: _repeat == 'week',
                            onTap: () => setState(() => _repeat = 'week')),
                        _choice(
                            label: 'ימי חול (א׳–ה׳)',
                            selected: _repeat == 'weekdays',
                            onTap: () => setState(() => _repeat = 'weekdays')),
                        _choice(
                            label: 'סופ״ש (ו׳–ש׳)',
                            selected: _repeat == 'weekend',
                            onTap: () => setState(() => _repeat = 'weekend')),
                      ],
                    ),
                    _label('תווית (רשות)'),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final t in _AvailabilityCalendarScreenState.tagPresets)
                          _choice(
                            label: t,
                            color: _AvailabilityCalendarScreenState.tagColor(t),
                            selected: _tag == t,
                            onTap: () => setState(() => _tag = _tag == t ? '' : t),
                          ),
                      ],
                    ),
                    _label('הערה (רשות)'),
                    TextField(
                      controller: _noteCtrl,
                      textDirection: TextDirection.rtl,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 16, color: AppColors.navy),
                      decoration: InputDecoration(
                        hintText: 'לדוגמה: קומה 3, קוד בניין 1234',
                        hintStyle: TextStyle(
                            fontSize: 15, color: AppColors.slate400),
                        filled: true,
                        fillColor: AppColors.slate50,
                        contentPadding: const EdgeInsets.all(14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: AppColors.slate200),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              BorderSide(color: AppColors.slate200, width: 1.5),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              BorderSide(color: AppColors.primary, width: 1.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: SizedBox(
                    height: 56,
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        Navigator.pop(
                          context,
                          _NewSlotConfig(
                            time: _time,
                            durationMinutes: _duration,
                            propertyId: _propertyId,
                            repeat: _repeat,
                            tag: _tag,
                            note: _noteCtrl.text.trim(),
                          ),
                        );
                      },
                      child: const Text('הוסף ליומן',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w900)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 20, 2, 10),
        child: Text(text,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppColors.navy)),
      );

  Widget _choice({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
    Color? color,
  }) {
    final c = color ?? AppColors.primary;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? c : AppColors.slate50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? c : AppColors.slate200, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 20, color: selected ? Colors.white : AppColors.slate500),
              const SizedBox(width: 8),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : AppColors.navy)),
          ],
        ),
      ),
    );
  }
}
