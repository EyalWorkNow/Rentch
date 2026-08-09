import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/notification_service.dart';
import 'package:dating_app/data/models/availability_slot.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/data/repositories/availability_repository.dart';
import 'package:dating_app/l10n/app_localizations.dart';
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

  List<String> _weekdayNames(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return [
      l10n.availabilityCalendarScreenDae6b270,
      l10n.availabilityCalendarScreen47f34119,
      l10n.availabilityCalendarScreenDb0c22fc,
      l10n.availabilityCalendarScreenDa1dae77,
      l10n.availabilityCalendarScreenCe94cfff,
      l10n.availabilityCalendarScreen7e718908,
      l10n.availabilityCalendarScreen4203bd7e,
    ];
  }

  List<String> _monthNames(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return [
      '',
      l10n.availabilityCalendarScreen89d6e050,
      l10n.availabilityCalendarScreenE974ea8b,
      l10n.availabilityCalendarScreenC0394ea3,
      l10n.availabilityCalendarScreenA1ac81be,
      l10n.availabilityCalendarScreen5fa88202,
      l10n.availabilityCalendarScreen4dee19aa,
      l10n.availabilityCalendarScreenCf58b8a7,
      l10n.availabilityCalendarScreen3551b598,
      l10n.availabilityCalendarScreenD7106337,
      l10n.availabilityCalendarScreen45ded998,
      l10n.availabilityCalendarScreen712a2e4f,
      l10n.availabilityCalendarScreen1774bb5f,
    ];
  }

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
      helpText: AppLocalizations.of(context)!.availabilityCalendarScreen782f10b5,
      cancelText: AppLocalizations.of(context)!.availabilityCalendarScreenA7c55a8d,
      confirmText: AppLocalizations.of(context)!.availabilityCalendarScreenF21acb6a,
      builder: (ctx, child) => Directionality(
        textDirection: Directionality.of(context),
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
  // Canonical (untranslated) tokens — persisted on-device and used for color
  // matching. Display text is resolved separately via [tagLabel] so the stored
  // value stays stable across languages.
  static const tagPresets = ['דחוף', 'בלעדי', 'טלפוני', 'גמיש'];

  static String tagLabel(BuildContext context, String tag) {
    final l10n = AppLocalizations.of(context)!;
    switch (tag) {
      case 'דחוף':
        return l10n.availabilityCalendarScreen0162a6e4;
      case 'בלעדי':
        return l10n.availabilityCalendarScreenEab14817;
      case 'טלפוני':
        return l10n.availabilityCalendarScreenEa57c7ab;
      case 'גמיש':
        return l10n.availabilityCalendarScreen9057aef3;
      default:
        return tag;
    }
  }

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
    final l10n = AppLocalizations.of(context)!;
    if (added == 0) {
      _toast(skipped > 0
          ? l10n.availabilityCalendarScreen88e6b612
          : l10n.availabilityCalendarScreenB30a89dd);
    } else if (added == 1) {
      _toast(l10n.availabilityCalendarScreen2baedd1e);
    } else {
      _toast(l10n.availabilityCalendarScreen6ef11812(added) +
          (skipped > 0
              ? ' · ${l10n.availabilityCalendarScreenSkippedSuffix(skipped)}'
              : ''));
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
    final l10n = AppLocalizations.of(context)!;
    // Booked = a real viewing. Guard against an accidental one-tap wipe, and
    // cancel its 1h-before reminder so it can't fire for a cancelled viewing.
    if (!s.isOpen) {
      final who = s.bookedByName.trim().isEmpty
          ? l10n.availabilityCalendarScreen9ad15d69
          : s.bookedByName.trim();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: Directionality.of(context),
          child: AlertDialog(
            title: Text(l10n.availabilityCalendarScreenCdf3b5e1,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
            content: Text(
              l10n.availabilityCalendarScreenAf15dd19(who, _time(s.start)),
              style: const TextStyle(fontSize: 16, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.availabilityCalendarScreen10a2352b,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.availabilityCalendarScreen32e0e58c,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
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
    _toast(s.isOpen
        ? l10n.availabilityCalendarScreen6b138e97
        : l10n.availabilityCalendarScreen8fee2105);
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      _toast(AppLocalizations.of(context)!.availabilityCalendarScreen6b96632d);
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
    final l10n = AppLocalizations.of(context)!;

    return Directionality(
      textDirection: Directionality.of(context),
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
          title: Text(l10n.availabilityCalendarScreenD1b5aeb8,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: AppColors.navy, fontFamily: 'sf hebrew rounded')),
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
                    Flexible(
                      child: Text(
                        '${_monthNames(context)[_stripStart.month]} ${_stripStart.year}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                        ),
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
          label: Text(l10n.availabilityCalendarScreen914d0f2b,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
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
                        hintText: l10n.availabilityCalendarScreen1dcc1ebd,
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
                textDirection: Directionality.of(context),
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
                      seg(AppLocalizations.of(context)!.availabilityCalendarScreen459ead47,
                          IconsaxPlusLinear.calendar_1, false),
                      seg(AppLocalizations.of(context)!.availabilityCalendarScreen53703118,
                          IconsaxPlusLinear.task_square, true),
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

            final String dayName = _weekdayNames(context)[d.weekday % 7];
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
              Text(
                AppLocalizations.of(context)!.availabilityCalendarScreen81849937,
                style: const TextStyle(
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
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Icon(IconsaxPlusBold.calendar_add,
              size: 60, color: AppColors.slate300),
          const SizedBox(height: 14),
          Text(l10n.availabilityCalendarScreenA59492de,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.slate600)),
          const SizedBox(height: 6),
          Text(l10n.availabilityCalendarScreenC5f10ba9,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.slate500)),
          const SizedBox(height: 20),
          // Quick presets — one tap adds a 30-minute window.
          Row(
            children: [
              _quickChip(l10n.availabilityCalendarScreenD741ca0e, '10:00', 10),
              const SizedBox(width: 10),
              _quickChip(l10n.availabilityCalendarScreen300ea530, '14:00', 14),
              const SizedBox(width: 10),
              _quickChip(l10n.availabilityCalendarScreen33c5e69b, '18:00', 18),
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
              Text(AppLocalizations.of(context)!.availabilityCalendarScreen57660599,
                  style: const TextStyle(
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
    final l10n = AppLocalizations.of(context)!;
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
                        booked
                            ? (who.isEmpty
                                ? l10n.availabilityCalendarScreen94eb6af0
                                : who)
                            : l10n.availabilityCalendarScreen4958be48,
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
                      ? (propLabel.isNotEmpty
                          ? propLabel
                          : l10n.availabilityCalendarScreenC24d48d2)
                      : (propLabel.isNotEmpty
                          ? l10n.availabilityCalendarScreen50c4a059(propLabel)
                          : l10n.availabilityCalendarScreenC90c40a2),
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
                      _avatar(
                          who.isEmpty
                              ? l10n.availabilityCalendarScreenF604bef9
                              : who,
                          Colors.blue),
                      const SizedBox(width: 4),
                      _avatar(l10n.availabilityCalendarScreen7bbfbc12, Colors.amber),
                      const SizedBox(width: 4),
                      _avatar(l10n.availabilityCalendarScreen9c2118be, Colors.teal),
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
                    child: Row(
                      children: [
                        const Icon(IconsaxPlusLinear.clock, size: 12, color: AppColors.slate500),
                        const SizedBox(width: 4),
                        Text(
                          l10n.availabilityCalendarScreenD16264b7,
                          style: const TextStyle(color: AppColors.slate500, fontSize: 11, fontWeight: FontWeight.w700),
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
                        tooltip: l10n.availabilityCalendarScreenD5bc848b,
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
                      tooltip: booked
                          ? l10n.availabilityCalendarScreen32e0e58c
                          : l10n.availabilityCalendarScreen7d165b83,
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
      helpText: AppLocalizations.of(context)!.availabilityCalendarScreen9eba4851,
    );
    if (t != null) setState(() => _time = t);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Directionality.of(context),
      child: DraggableScrollableSheet(
        initialChildSize: 0.78,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollCtrl) {
          final l10n = AppLocalizations.of(context)!;
          return Container(
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
                    Text(AppLocalizations.of(context)!.availabilityCalendarScreenF29f462e,
                        style: const TextStyle(
                            fontSize: 21, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                  children: [
                    _label(l10n.availabilityCalendarScreen96d116f2),
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
                            Text(l10n.availabilityCalendarScreenE94abfe2,
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary)),
                          ],
                        ),
                      ),
                    ),
                    _label(l10n.availabilityCalendarScreenFc655797),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final m in const [30, 45, 60, 90, 120])
                          _choice(
                            label: m < 60
                                ? l10n.availabilityCalendarScreenD5c2c3b6(m)
                                : l10n.availabilityCalendarScreenF2ee1c96(
                                    m % 60 == 0 ? '${m ~/ 60}' : '${m ~/ 60}.5'),
                            selected: _duration == m,
                            onTap: () => setState(() => _duration = m),
                          ),
                      ],
                    ),
                    if (widget.properties.isNotEmpty) ...[
                      _label(l10n.availabilityCalendarScreenE3a2d38d),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _choice(
                            label: l10n.availabilityCalendarScreen2d69e44a,
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
                    _label(l10n.availabilityCalendarScreenRepeatLabel),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _choice(
                            label: l10n.availabilityCalendarScreen7d46f18c,
                            selected: _repeat == 'today',
                            onTap: () => setState(() => _repeat = 'today')),
                        _choice(
                            label: l10n.availabilityCalendarScreen3563f3df,
                            selected: _repeat == 'week',
                            onTap: () => setState(() => _repeat = 'week')),
                        _choice(
                            label: l10n.availabilityCalendarScreen155f0dee,
                            selected: _repeat == 'weekdays',
                            onTap: () => setState(() => _repeat = 'weekdays')),
                        _choice(
                            label: l10n.availabilityCalendarScreen404b7e24,
                            selected: _repeat == 'weekend',
                            onTap: () => setState(() => _repeat = 'weekend')),
                      ],
                    ),
                    _label(l10n.availabilityCalendarScreen017014f8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final t in _AvailabilityCalendarScreenState.tagPresets)
                          _choice(
                            label: _AvailabilityCalendarScreenState.tagLabel(
                                context, t),
                            color: _AvailabilityCalendarScreenState.tagColor(t),
                            selected: _tag == t,
                            onTap: () => setState(() => _tag = _tag == t ? '' : t),
                          ),
                      ],
                    ),
                    _label(l10n.availabilityCalendarScreen82b33733),
                    TextField(
                      controller: _noteCtrl,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 16, color: AppColors.navy),
                      decoration: InputDecoration(
                        hintText: l10n.availabilityCalendarScreenF4c3f886,
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
                      child: Text(l10n.availabilityCalendarScreenEcfe64b2,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w900)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
        },
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
