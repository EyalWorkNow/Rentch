import 'package:dating_app/data/models/persona_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime(2026, 1, 1);

  test('first observation stores value + version bumps', () {
    final p = PersonaProfile.empty()
        .observe('city', 'תל אביב', PersonaSource.declared, now: t0);
    expect(p.value('city'), 'תל אביב');
    expect(p.version, 1);
  });

  test('validation rejects implausible values', () {
    final p = PersonaProfile.empty()
        .observe('maxBudget', 50, PersonaSource.declared, now: t0) // < 1000
        .observe('religiosity', 'jedi', PersonaSource.declared, now: t0);
    expect(p.value('maxBudget'), isNull);
    expect(p.value('religiosity'), isNull);
    expect(p.version, 0); // nothing stored
  });

  test('repeated agreement raises confidence; dedup guards spam', () {
    var p = PersonaProfile.empty()
        .observe('religiosity', 'religious', PersonaSource.inferred, now: t0);
    final c0 = p.confidence('religiosity');
    // Same value a day later → confidence rises, evidence++.
    p = p.observe('religiosity', 'religious', PersonaSource.inferred,
        now: t0.add(const Duration(days: 1)));
    expect(p.confidence('religiosity'), greaterThan(c0));
    expect(p.facts['religiosity']!.evidence, 2);
    // Immediate duplicate (same source, within window) → no evidence bump.
    final c1 = p.confidence('religiosity');
    p = p.observe('religiosity', 'religious', PersonaSource.inferred,
        now: t0.add(const Duration(days: 1, seconds: 10)));
    expect(p.confidence('religiosity'), c1);
    expect(p.facts['religiosity']!.evidence, 2);
  });

  test('declared overrides an existing inferred value (conflict)', () {
    var p = PersonaProfile.empty()
        .observe('religiosity', 'secular', PersonaSource.inferred, now: t0);
    p = p.observe('religiosity', 'religious', PersonaSource.declared, now: t0);
    expect(p.value('religiosity'), 'religious');
    expect(p.facts['religiosity']!.source, PersonaSource.declared);
  });

  test('weak conflicting signal cannot overturn a strong recent one', () {
    var p = PersonaProfile.empty()
        .observe('city', 'תל אביב', PersonaSource.declared, now: t0);
    // Inferred, lower strength + lower base than fresh declared → incumbent wins.
    p = p.observe('city', 'חיפה', PersonaSource.inferred, now: t0);
    expect(p.value('city'), 'תל אביב');
  });

  test('recency decay fades stale facts below threshold', () {
    final p = PersonaProfile.empty()
        .observe('city', 'חיפה', PersonaSource.inferred, now: t0);
    // ~2 years later, inferred base (0.55) decays well under 0.5.
    final late = t0.add(const Duration(days: 730));
    expect(p.value('city', now: late), isNull);
    expect(p.value('city', now: t0), 'חיפה'); // fresh still counts
  });

  test('round-trips through json', () {
    final p = PersonaProfile.empty()
        .observe('city', 'תל אביב', PersonaSource.declared, now: t0)
        .observe('maxBudget', 6000, PersonaSource.declared, now: t0);
    final back = PersonaProfile.fromJson(p.toJson());
    expect(back.version, p.version);
    expect(back.value('city'), 'תל אביב');
    expect(back.value('maxBudget'), 6000);
  });
}
