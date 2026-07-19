import 'package:dating_app/data/models/availability_slot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AvailabilitySlot slot({
    DateTime? start,
    int duration = 30,
    String tag = '',
    String propertyId = '',
    String note = '',
  }) =>
      AvailabilitySlot(
        id: 'x',
        start: start ?? DateTime(2026, 7, 20, 17, 0),
        durationMinutes: duration,
        tag: tag,
        propertyId: propertyId,
        note: note,
      );

  test('tag / propertyId / note survive a JSON round-trip', () {
    final s = slot(tag: 'דחוף', propertyId: 'p1', note: 'קומה 3');
    final back = AvailabilitySlot.fromJson(s.toJson());
    expect(back.tag, 'דחוף');
    expect(back.propertyId, 'p1');
    expect(back.note, 'קומה 3');
    expect(back.durationMinutes, 30);
  });

  test('empty optional fields are omitted from JSON', () {
    final json = slot().toJson();
    expect(json.containsKey('tag'), isFalse);
    expect(json.containsKey('propertyId'), isFalse);
    expect(json.containsKey('note'), isFalse);
  });

  test('unknown tag defaults to empty on decode', () {
    final back = AvailabilitySlot.fromJson({
      'id': 'x',
      'start': DateTime(2026, 7, 20, 17, 0).toIso8601String(),
      'durationMinutes': 45,
    });
    expect(back.tag, '');
    expect(back.durationMinutes, 45);
  });

  test('clashesWith detects overlap and allows back-to-back', () {
    final a = AvailabilitySlot(
        id: 'a', start: DateTime(2026, 7, 20, 17, 0), durationMinutes: 60);
    final overlap = AvailabilitySlot(
        id: 'b', start: DateTime(2026, 7, 20, 17, 30), durationMinutes: 30);
    final adjacent = AvailabilitySlot(
        id: 'c', start: DateTime(2026, 7, 20, 18, 0), durationMinutes: 30);
    expect(a.clashesWith(overlap), isTrue);
    expect(a.clashesWith(adjacent), isFalse); // touching, not overlapping
    expect(a.clashesWith(a), isFalse); // same id never clashes with itself
  });
}
