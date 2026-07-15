import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/availability_slot.dart';
import 'package:dating_app/data/repositories/availability_repository.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

/// היומן — the landlord's / agent's availability calendar (Phase 1).
///
/// The owner marks FREE viewing windows here. A 14-day strip picks the day;
/// each day shows its slots (open/booked) and an "add free time" action. Slots
/// are stored on-device ([AvailabilityRepository]). Phase 2 adds voice/text
/// control via Erik; Phase 3 two-way-syncs with Google Calendar. From the chat,
/// the landlord will send these open slots for a tenant to book.
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
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);
    _load();
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

  List<AvailabilitySlot> get _daySlots {
    final list =
        _slots.where((s) => _sameDay(s.start, _selectedDay)).toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    return list;
  }

  String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _addSlot() async {
    // Time + duration for a new FREE window on the selected day.
    final t = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 17, minute: 0),
      helpText: 'שעת התחלה של החלון הפנוי',
    );
    if (t == null || !mounted) return;
    final duration = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('משך החלון',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            for (final m in const [30, 45, 60, 90, 120])
              ListTile(
                title: Text(m < 60 ? '$m דקות' : '${m ~/ 60} שעות'
                    '${m % 60 == 0 ? '' : ' ו-${m % 60} דק׳'}'),
                onTap: () => Navigator.of(ctx).pop(m),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (duration == null || !mounted) return;

    final start = DateTime(_selectedDay.year, _selectedDay.month,
        _selectedDay.day, t.hour, t.minute);
    final slot = AvailabilitySlot(
      id: 'slot_${DateTime.now().microsecondsSinceEpoch}',
      start: start,
      durationMinutes: duration,
    );
    // Refuse to add a window that overlaps an existing one.
    if (_slots.any((s) => s.clashesWith(slot))) {
      _toast('החלון חופף לחלון פנוי קיים');
      return;
    }
    final next = await _repo.save(slot);
    if (!mounted) return;
    setState(() => _slots = next);
    _toast('נוסף חלון פנוי ${_time(start)} ✅');
  }

  Future<void> _removeSlot(AvailabilitySlot s) async {
    final next = await _repo.delete(s.id);
    if (!mounted) return;
    setState(() => _slots = next);
    _toast('החלון הוסר');
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(milliseconds: 2600),
      content: Text(m),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F7FB),
        appBar: AppBar(
          title: const Text('היומן שלי',
              style: TextStyle(fontWeight: FontWeight.w900)),
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: const Color(0xFF072946),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addSlot,
          backgroundColor: AppColors.primary,
          icon: const Icon(IconsaxPlusLinear.add),
          label: const Text('הוסף זמן פנוי'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _weekStrip(),
                  const SizedBox(height: 4),
                  Expanded(child: _dayView()),
                ],
              ),
      ),
    );
  }

  Widget _weekStrip() {
    final today = DateTime.now();
    final days = List.generate(14, (i) {
      final d = DateTime(today.year, today.month, today.day + i);
      return d;
    });
    return SizedBox(
      height: 92,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        itemCount: days.length,
        itemBuilder: (_, i) {
          final d = days[i];
          final selected = _sameDay(d, _selectedDay);
          final count =
              _slots.where((s) => _sameDay(s.start, d) && s.isOpen).length;
          return GestureDetector(
            onTap: () => setState(() => _selectedDay = d),
            child: Container(
              width: 58,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : const Color(0xFFE3E6EF)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_heb[d.weekday % 7],
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color:
                              selected ? Colors.white : const Color(0xFF6B7280))),
                  const SizedBox(height: 4),
                  Text('${d.day}',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color:
                              selected ? Colors.white : const Color(0xFF072946))),
                  const SizedBox(height: 3),
                  Container(
                    width: 18,
                    height: 4,
                    decoration: BoxDecoration(
                      color: count == 0
                          ? Colors.transparent
                          : (selected ? Colors.white : AppColors.primary),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _dayView() {
    final slots = _daySlots;
    final header = '${_heb[_selectedDay.weekday % 7]}, '
        '${_selectedDay.day} ${_monthsHeb[_selectedDay.month]}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Text(header,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF072946))),
        ),
        if (slots.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🗓️', style: TextStyle(fontSize: 44)),
                  const SizedBox(height: 12),
                  const Text('אין עדיין זמנים פנויים ביום הזה',
                      style: TextStyle(color: Color(0xFF6B7280))),
                  const SizedBox(height: 4),
                  Text('הקישו «הוסף זמן פנוי» למטה',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              itemCount: slots.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _slotCard(slots[i]),
            ),
          ),
      ],
    );
  }

  Widget _slotCard(AvailabilitySlot s) {
    final booked = !s.isOpen;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3E6EF)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: booked
                ? AppColors.coral.withValues(alpha: 0.12)
                : AppColors.success.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(booked ? IconsaxPlusLinear.user_tick : IconsaxPlusLinear.clock,
              color: booked ? AppColors.coral : AppColors.success),
        ),
        title: Text('${_time(s.start)} – ${_time(s.end)}',
            style: const TextStyle(
                fontWeight: FontWeight.w800, color: Color(0xFF072946))),
        subtitle: Text(
          booked
              ? 'נתפס${s.bookedByName.isNotEmpty ? ' · ${s.bookedByName}' : ''}'
              : 'פנוי לצפייה',
          style: TextStyle(
              color: booked ? AppColors.coral : const Color(0xFF6B7280),
              fontWeight: FontWeight.w600),
        ),
        trailing: IconButton(
          icon: const Icon(IconsaxPlusLinear.trash, color: AppColors.coral),
          tooltip: 'הסר',
          onPressed: () => _removeSlot(s),
        ),
      ),
    );
  }
}
