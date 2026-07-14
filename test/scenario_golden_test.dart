// Golden regression guard derived from rently_scenarios_v4_1100.json (1100
// per-apartment scenarios → 276 distinct profiles). Each scenario's
// `expected_display.must_NOT_appear` is 100% consistent per profile across all
// 22 apartments (pure profile-driven suppression), so it is an apartment-
// independent contract: for a given persona these layers must NEVER be
// surfaced (a secular single sees no synagogues; a childless profile sees no
// kindergartens/schools). This test asserts the SHIPPED display spec
// (assets/data/search_scenarios.json) honours all 276 rules, so a future edit
// to the spec that starts leaking a suppressed layer fails here.
//
// The compact golden (key → must_NOT layers) lives in test/scenario_golden.json,
// extracted from the source v4 file; see the generator note in the session log.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final golden =
      jsonDecode(File('test/scenario_golden.json').readAsStringSync())
          as Map<String, dynamic>;
  final spec = jsonDecode(
          File('assets/data/search_scenarios.json').readAsStringSync())
      as Map<String, dynamic>;
  final base = ((spec['base'] as List?) ?? const []).map((e) => '$e').toSet();
  final map = spec['map'] as Map<String, dynamic>;
  final mustNot = golden['must_not'] as Map<String, dynamic>;

  test('spec surfaces no layer that v4 marks must_NOT_appear (276 profiles)',
      () {
    final violations = <String>[];
    mustNot.forEach((key, notList) {
      final entry = map[key] as Map<String, dynamic>?;
      if (entry == null) {
        violations.add('$key: MISSING FROM SPEC');
        return;
      }
      final surfaced = <String>{
        ...((entry['c'] as List?) ?? const []).map((e) => '$e'),
        ...((entry['s'] as List?) ?? const []).map((e) => '$e'),
        ...base,
      };
      final banned = ((notList as List?) ?? const []).map((e) => '$e').toSet();
      final leaked = surfaced.intersection(banned);
      if (leaked.isNotEmpty) violations.add('$key: leaked ${leaked.toList()}');
    });
    expect(violations, isEmpty,
        reason: 'spec surfaces v4-forbidden layers:\n${violations.join('\n')}');
  });

  test('golden covers the expected 276 profiles', () {
    expect(mustNot.length, 276);
    // every golden profile must exist in the shipped spec (superset check)
    final missing = mustNot.keys.where((k) => !map.containsKey(k)).toList();
    expect(missing, isEmpty, reason: 'golden profiles absent from spec: $missing');
  });
}
