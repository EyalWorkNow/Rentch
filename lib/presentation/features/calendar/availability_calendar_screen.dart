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
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
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
        child: Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.primary, // Header background & active circle
              onPrimary: Colors.white, // Header text & active text
              surface: Colors.white, // Dialog background
              onSurface: AppColors.navy, // Default text color
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary, // Action buttons color
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            datePickerTheme: DatePickerThemeData(
              backgroundColor: Colors.white,
              headerBackgroundColor: AppColors.primary,
              headerForegroundColor: Colors.white,
              dayForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                return AppColors.navy;
              }),
              dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return AppColors.primary;
                }
                return Colors.transparent;
              }),
            ),
          ),
          child: child!,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedDay = DateTime(picked.year, picked.month, picked.day);
      _stripStart = _selectedDay; // re-anchor the strip on the chosen day
      _agenda = false;
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
        return AppColors.primaryDark;
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
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DatingProvider>();
    final bool isBroker = AppColors.isBrokerAccent;
    final primaryColor = isBroker ? Colors.black : AppColors.primary;
    
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Theme(
        data: Theme.of(context).copyWith(
          textTheme: Theme.of(context).textTheme.apply(fontFamily: 'sf hebrew rounded'),
        ),
        child: Scaffold(
          backgroundColor: AppColors.cloud,
        appBar: AppBar(
          backgroundColor: AppColors.cloud,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              margin: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
              ),
              child: const Icon(Icons.arrow_forward, color: AppColors.navy, size: 20),
            ),
          ),
          centerTitle: true,
          title: const Text('היומן שלי',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: AppColors.navy, fontFamily: 'sf hebrew rounded')),
          actions: [
            GestureDetector(
              onTap: _pickAnyDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                margin: const EdgeInsets.only(left: 16, top: 10, bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: AppColors.slate300, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(IconsaxPlusLinear.calendar, size: 16, color: AppColors.navy),
                    const SizedBox(width: 6),
                    Text(
                      '${_monthsHeb[_stripStart.month]} ${_stripStart.year}',
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down, size: 18, color: AppColors.navy),
                  ],
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openNewSlotSheet,
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          icon: const Icon(IconsaxPlusLinear.add, size: 24),
          label: const Text('הוסף זמן פנוי',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _viewToggle(),
                  // Search Bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                      decoration: InputDecoration(
                        hintText: 'חפשו צפיות וחלונות...',
                        hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
                        suffixIcon: const Icon(IconsaxPlusLinear.search_normal, color: AppColors.textSecondary, size: 20),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(100),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(100),
                          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                  if (!_agenda) ...[
                    _weekStrip(provider),
                    const SizedBox(height: 8),
                    Expanded(child: _dayView(provider)),
                  ] else
                    Expanded(child: _agendaView(provider)),
                ],
              ),
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
            // Visual order (RTL): [יום, כל הקרובים].
            final thumbRight = pad + (_agenda ? segW : 0);

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
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3), width: 1.5),
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Stack(
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      right: thumbRight,
                      width: segW,
                      top: pad,
                      bottom: pad,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          color: AppColors.primary,
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



  Widget _weekStrip(DatingProvider provider) {
    final anchor = _stripStart;
    final days = List.generate(
        14, (i) => DateTime(anchor.year, anchor.month, anchor.day + i));
    return Container(
      color: AppColors.cloud,
      child: SizedBox(
        height: 116,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: days.length,
          itemBuilder: (_, i) {
            final d = days[i];
            final selected = _sameDay(d, _selectedDay);
            final onDay = _slotsOn(d);
            final booked = onDay.where((s) => !s.isOpen).length;
            final open = onDay.where((s) => s.isOpen).length;

            final String dayName = _heb[d.weekday % 7];
            final String shortDayName = dayName.length > 2 ? dayName.substring(0, 2) : dayName;

            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _selectedDay = d);
              },
              child: Container(
                width: 62,
                margin: const EdgeInsets.symmetric(horizontal: 5),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.slate200.withValues(alpha: 0.5),
                    width: selected ? 2.0 : 1.2,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      shortDayName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: selected ? AppColors.primary : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? AppColors.primary : AppColors.slate50,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${d.day}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: selected ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Marker reflects BOTH booked (coral) and open (primary) so
                    // a fully-booked day never looks empty and reads differently
                    // from a day with only open windows.
                    if (booked > 0 || open > 0)
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected
                              ? Colors.white
                              : (booked > 0
                                  ? AppColors.coral
                                  : AppColors.primary),
                        ),
                      )
                    else
                      const SizedBox(height: 5),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }



  Widget _dayView(DatingProvider provider) {
    var slots = _slotsOn(_selectedDay);
    if (_searchQuery.isNotEmpty) {
      slots = slots.where((s) {
        final prop = _propertyLabel(provider, s.propertyId).toLowerCase();
        final name = s.bookedByName.toLowerCase();
        final tag = s.tag.toLowerCase();
        final note = s.note.toLowerCase();
        return prop.contains(_searchQuery) ||
            name.contains(_searchQuery) ||
            tag.contains(_searchQuery) ||
            note.contains(_searchQuery);
      }).toList();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Row(
            children: [
              const Text(
                'צפיות וחלונות להיום',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.danger, // Rose red count badge
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '${slots.length < 10 ? '0' : ''}${slots.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (slots.isEmpty)
          Expanded(child: _emptyDay())
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
              itemCount: slots.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (_, i) => _timelineRow(provider, slots[i]),
            ),
          ),
      ],
    );
  }

  Widget _timelineRow(DatingProvider provider, AvailabilitySlot s) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 55,
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              _time(s.start),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _slotCard(provider, s),
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
    var upcoming = _slots.where((s) => s.end.isAfter(DateTime.now())).toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    if (_searchQuery.isNotEmpty) {
      upcoming = upcoming.where((s) {
        final prop = _propertyLabel(provider, s.propertyId).toLowerCase();
        final name = s.bookedByName.toLowerCase();
        final tag = s.tag.toLowerCase();
        final note = s.note.toLowerCase();
        return prop.contains(_searchQuery) ||
            name.contains(_searchQuery) ||
            tag.contains(_searchQuery) ||
            note.contains(_searchQuery);
      }).toList();
    }

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
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
      itemCount: upcoming.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (_, i) => _timelineRow(provider, upcoming[i]),
    );
  }

  Widget _slotCard(DatingProvider provider, AvailabilitySlot s) {
    final booked = !s.isOpen;
    final bool isBroker = AppColors.isBrokerAccent;
    final primaryColor = isBroker ? Colors.black : AppColors.primary;
    
    final propLabel = _propertyLabel(provider, s.propertyId);
    final who = s.bookedByName.trim();

    final cardBgColor = booked ? primaryColor : Colors.white;
    final textTitleColor = booked ? Colors.white : AppColors.textPrimary;
    final textSubtitleColor = booked ? Colors.white.withValues(alpha: 0.8) : AppColors.textSecondary;
    final border = booked ? null : Border.all(color: AppColors.slate200, width: 1.2);

    return Container(
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(20),
        border: border,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow.withValues(alpha: booked ? 0.15 : 0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        booked ? (who.isEmpty ? 'צפייה מאושרת' : who) : 'חלון צפייה פנוי',
                        style: TextStyle(
                          color: textTitleColor,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_time(s.start)} - ${_time(s.end)}',
                      style: TextStyle(
                        color: textSubtitleColor,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  booked
                      ? (propLabel.isNotEmpty ? propLabel : 'פניית צפייה מתואמת')
                      : (propLabel.isNotEmpty ? 'פנוי לצפייה ב$propLabel' : 'שוכרים יכולים לתאם מועד לצפייה'),
                  style: TextStyle(
                    color: textSubtitleColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (booked)
                  Row(
                    children: [
                      _avatar(who.isEmpty ? 'ש' : who, Colors.blue),
                      const SizedBox(width: 4),
                      _avatar('סוכן', Colors.amber),
                      const SizedBox(width: 4),
                      _avatar('לקוח', Colors.teal),
                    ],
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.slate50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.slate200, width: 0.8),
                    ),
                    child: const Row(
                      children: [
                        Icon(IconsaxPlusLinear.clock, size: 12, color: AppColors.slate500),
                        SizedBox(width: 4),
                        Text(
                          'זמין להזמנה',
                          style: TextStyle(color: AppColors.slate500, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    if (s.note.trim().isNotEmpty)
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          IconsaxPlusLinear.note_1,
                          color: booked ? Colors.white70 : AppColors.slate500,
                          size: 20,
                        ),
                        tooltip: s.note,
                        onPressed: () => _toast(s.note),
                      ),
                    const SizedBox(width: 8),
                    if (booked && s.bookedByPhone.trim().isNotEmpty)
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          IconsaxPlusLinear.call,
                          color: booked ? Colors.white : AppColors.success,
                          size: 20,
                        ),
                        tooltip: 'חיוג',
                        onPressed: () => _call(s.bookedByPhone.trim()),
                      ),
                    const SizedBox(width: 8),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        booked ? IconsaxPlusLinear.close_circle : IconsaxPlusLinear.trash,
                        color: booked ? Colors.white : AppColors.coral,
                        size: 22,
                      ),
                      tooltip: booked ? 'בטל צפייה' : 'הסר חלון',
                      onPressed: () => _confirmRemove(s),
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

  Widget _avatar(String name, Color fallbackBg) {
    final initials = name.trim().split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join();
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.25),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        initials.isEmpty ? 'U' : initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
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
  _NewSlotSheet({required this.day, required this.properties});

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
