import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

// ─── Eligibility criteria catalog (F3) ────────────────────────────────────────
// The landlord defines precise tenant-eligibility criteria, each with a hardness
// level ('must'/'important'/'prefer'). Only matching tenants see the listing.
// Keys + value shapes MUST mirror EligibilityRule in rental_models.dart.

enum _EligInput { number, stepper, boolean, multi }

class _Criterion {
  const _Criterion(
    this.key,
    this.label,
    this.input, {
    this.options = const {},
    this.unit,
    this.min = 0,
    this.max = 5,
    this.defaultNumber = 0,
  });

  final String key;
  final String label;
  final _EligInput input;
  final Map<String, String> options; // multi-select: optionKey → Hebrew label
  final String? unit;
  final int min;
  final int max;
  final int defaultNumber;
}

const _occupationOptions = <String, String>{
  'hightech': 'הייטק',
  'healthcare': 'בריאות/רפואה',
  'education': 'חינוך/הוראה',
  'finance': 'פיננסים/בנקאות',
  'law': 'משפטים',
  'engineering': 'הנדסה',
  'selfemployed': 'עצמאי/ת',
  'public': 'שירות ציבורי',
  'retail': 'מסחר/שירות',
  'academia': 'אקדמיה',
  'student': 'סטודנט/ית',
  'other': 'אחר',
};

const _householdOptions = <String, String>{
  'family': 'משפחה',
  'single': 'רווק/ה',
  'couple': 'זוג',
  'student': 'סטודנט/ית',
};

const _lifeStageOptions = <String, String>{
  'student': 'סטודנט/ית',
  'young-professional': 'צעיר/ה מקצועי/ת',
  'family': 'משפחה',
  'senior': 'גיל הזהב',
};

const _catalog = <_Criterion>[
  _Criterion('budgetMin', 'תקציב חודשי מינימלי של השוכר ≥', _EligInput.number,
      unit: '₪', defaultNumber: 5000),
  _Criterion('maxChildren', 'עד כמה ילדים', _EligInput.stepper,
      min: 0, max: 5, defaultNumber: 2),
  _Criterion('noPets', 'ללא חיית מחמד', _EligInput.boolean),
  _Criterion('hasCar', 'יש רכב', _EligInput.boolean),
  _Criterion('occupation', 'תחום עיסוק', _EligInput.multi,
      options: _occupationOptions),
  _Criterion('wfh', 'עובד/ת מרחוק', _EligInput.boolean),
  _Criterion('household', 'סוג משק בית', _EligInput.multi,
      options: _householdOptions),
  _Criterion('lifeStage', 'שלב חיים', _EligInput.multi,
      options: _lifeStageOptions),
  _Criterion('oleh', 'עולה חדש', _EligInput.boolean),
  _Criterion('minAge', 'גיל מינימלי', _EligInput.number, defaultNumber: 18),
  _Criterion('maxAge', 'גיל מקסימלי', _EligInput.number, defaultNumber: 60),
  _Criterion('accessibility', 'צורך בנגישות', _EligInput.boolean),
];

const _importanceLevels = <String>['must', 'important', 'prefer'];

String _importanceLabel(String v) {
  switch (v) {
    case 'important':
      return 'חשוב';
    case 'prefer':
      return 'עדיף';
    default:
      return 'חובה';
  }
}

String _importanceHelper(String v) {
  switch (v) {
    case 'important':
      return 'מסנן רק מי שידוע שלא מתאים';
    case 'prefer':
      return 'משפיע על הדירוג בלבד';
    default:
      return 'מי שלא עונה או לא ידוע — לא יראה את הדירה';
  }
}

/// One-line summary of the active rules, e.g. "3 קריטריונים · 1 חובה".
String eligibilitySummaryLabel(EligibilityConfig config) {
  final n = config.rules.length;
  if (n == 0) return 'לא הוגדרו קריטריונים';
  final musts = config.rules.where((r) => r.importance == 'must').length;
  final base = '$n קריטריונים';
  return musts > 0 ? '$base · $musts חובה' : base;
}

/// Opens the eligibility editor as a modal sheet, pre-filled from [initial].
/// Returns the edited rule list, or null if the landlord cancelled.
Future<List<EligibilityRule>?> showEligibilityEditor(
  BuildContext context, {
  required EligibilityConfig initial,
}) {
  return showModalBottomSheet<List<EligibilityRule>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _EligibilityEditorSheet(initial: initial),
  );
}

class _EligibilityEditorSheet extends StatefulWidget {
  const _EligibilityEditorSheet({required this.initial});
  final EligibilityConfig initial;

  @override
  State<_EligibilityEditorSheet> createState() =>
      _EligibilityEditorSheetState();
}

class _EligibilityEditorSheetState extends State<_EligibilityEditorSheet> {
  final Set<String> _active = {};
  final Map<String, String> _importance = {};
  final Map<String, int> _steppers = {};
  final Map<String, Set<String>> _multi = {};
  final Map<String, TextEditingController> _numCtrls = {};

  @override
  void initState() {
    super.initState();
    for (final rule in widget.initial.rules) {
      final crit = _critFor(rule.key);
      if (crit == null) continue;
      _active.add(crit.key);
      _importance[crit.key] = _importanceLevels.contains(rule.importance)
          ? rule.importance
          : 'must';
      switch (crit.input) {
        case _EligInput.number:
          _numCtrls[crit.key] =
              TextEditingController(text: _numFromValue(rule.value)?.toString() ?? '');
          break;
        case _EligInput.stepper:
          _steppers[crit.key] = _numFromValue(rule.value) ?? crit.defaultNumber;
          break;
        case _EligInput.multi:
          _multi[crit.key] = _stringsFromValue(rule.value);
          break;
        case _EligInput.boolean:
          break;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _numCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  _Criterion? _critFor(String key) {
    for (final c in _catalog) {
      if (c.key == key) return c;
    }
    return null;
  }

  int? _numFromValue(dynamic v) {
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  Set<String> _stringsFromValue(dynamic v) {
    if (v is List) {
      return v.map((e) => e.toString()).where((e) => e.isNotEmpty).toSet();
    }
    return {};
  }

  void _toggle(_Criterion crit, bool on) {
    setState(() {
      if (on) {
        _active.add(crit.key);
        _importance.putIfAbsent(crit.key, () => 'must');
        switch (crit.input) {
          case _EligInput.number:
            _numCtrls.putIfAbsent(
                crit.key,
                () => TextEditingController(
                    text: crit.defaultNumber > 0
                        ? crit.defaultNumber.toString()
                        : ''));
            break;
          case _EligInput.stepper:
            _steppers.putIfAbsent(crit.key, () => crit.defaultNumber);
            break;
          case _EligInput.multi:
            _multi.putIfAbsent(crit.key, () => <String>{});
            break;
          case _EligInput.boolean:
            break;
        }
      } else {
        _active.remove(crit.key);
      }
    });
  }

  List<EligibilityRule> _buildRules() {
    final rules = <EligibilityRule>[];
    for (final crit in _catalog) {
      if (!_active.contains(crit.key)) continue;
      final importance = _importance[crit.key] ?? 'must';
      switch (crit.input) {
        case _EligInput.number:
          final n = int.tryParse(_numCtrls[crit.key]?.text.trim() ?? '');
          if (n == null) continue; // no value typed → skip
          rules.add(
              EligibilityRule(key: crit.key, value: n, importance: importance));
          break;
        case _EligInput.stepper:
          rules.add(EligibilityRule(
              key: crit.key,
              value: _steppers[crit.key] ?? crit.defaultNumber,
              importance: importance));
          break;
        case _EligInput.multi:
          final picked = (_multi[crit.key] ?? {}).toList();
          if (picked.isEmpty) continue; // empty selection → skip
          rules.add(EligibilityRule(
              key: crit.key, value: picked, importance: importance));
          break;
        case _EligInput.boolean:
          rules.add(EligibilityRule(key: crit.key, importance: importance));
          break;
      }
    }
    return rules;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
              const SizedBox(height: 14),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'הגדרת קריטריונים מדויקים',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.navy,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'הפעל/י קריטריון, קבע/י את הערך ואת רמת הקשיחות שלו.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: _catalog.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _buildCriterionTile(_catalog[i]),
                ),
              ),
              _buildSaveBar(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCriterionTile(_Criterion crit) {
    final active = _active.contains(crit.key);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: active ? Colors.white : AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? AppColors.primary : AppColors.borderLight,
          width: active ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  crit.label,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: active ? AppColors.navy : AppColors.textSecondary,
                  ),
                ),
              ),
              Switch(
                value: active,
                onChanged: (v) => _toggle(crit, v),
                activeColor: AppColors.primary,
              ),
            ],
          ),
          if (active) ...[
            const SizedBox(height: 6),
            _buildValueInput(crit),
            const SizedBox(height: 14),
            _buildImportanceSelector(crit),
          ],
        ],
      ),
    );
  }

  Widget _buildValueInput(_Criterion crit) {
    switch (crit.input) {
      case _EligInput.number:
        return Row(
          children: [
            if (crit.unit != null) ...[
              Text(
                crit.unit!,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: TextField(
                controller: _numCtrls[crit.key],
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: crit.defaultNumber > 0
                      ? crit.defaultNumber.toString()
                      : '0',
                  filled: true,
                  fillColor: AppColors.background,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.borderLight),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.borderLight),
                  ),
                ),
              ),
            ),
          ],
        );
      case _EligInput.stepper:
        final v = _steppers[crit.key] ?? crit.defaultNumber;
        return Row(
          children: [
            _StepperButton(
              icon: Icons.remove_rounded,
              enabled: v > crit.min,
              onTap: () =>
                  setState(() => _steppers[crit.key] = (v - 1).clamp(crit.min, crit.max)),
            ),
            SizedBox(
              width: 44,
              child: Text(
                '$v',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy),
              ),
            ),
            _StepperButton(
              icon: Icons.add_rounded,
              enabled: v < crit.max,
              onTap: () =>
                  setState(() => _steppers[crit.key] = (v + 1).clamp(crit.min, crit.max)),
            ),
          ],
        );
      case _EligInput.multi:
        final picked = _multi[crit.key] ?? <String>{};
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in crit.options.entries)
              _SelectChip(
                label: entry.value,
                selected: picked.contains(entry.key),
                onTap: () => setState(() {
                  final set = _multi.putIfAbsent(crit.key, () => <String>{});
                  if (set.contains(entry.key)) {
                    set.remove(entry.key);
                  } else {
                    set.add(entry.key);
                  }
                }),
              ),
          ],
        );
      case _EligInput.boolean:
        return const Text(
          'קריטריון ללא ערך — נדרש שהשוכר יעמוד בו.',
          style: TextStyle(
              fontSize: 12, color: AppColors.textSecondary, height: 1.35),
        );
    }
  }

  Widget _buildImportanceSelector(_Criterion crit) {
    final current = _importance[crit.key] ?? 'must';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'רמת קשיחות',
          style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final level in _importanceLevels) ...[
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _importance[crit.key] = level),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: current == level
                          ? AppColors.primary
                          : AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: current == level
                            ? AppColors.primary
                            : AppColors.borderLight,
                      ),
                    ),
                    child: Text(
                      _importanceLabel(level),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: current == level
                            ? Colors.white
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
              if (level != _importanceLevels.last) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _importanceHelper(current),
          style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textSecondary,
              height: 1.35),
        ),
      ],
    );
  }

  Widget _buildSaveBar(BuildContext context) {
    final count = _active.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.borderLight)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Text(
                count == 0
                    ? 'לא נבחרו קריטריונים'
                    : '$count קריטריונים פעילים',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.of(context).pop(_buildRules()),
              child: const Text(
                'שמירה',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton(
      {required this.icon, required this.enabled, required this.onTap});
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: enabled ? AppColors.primary.withValues(alpha: 0.12) : AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Icon(icon,
            size: 20,
            color: enabled ? AppColors.primary : AppColors.textDisabled),
      ),
    );
  }
}

class _SelectChip extends StatelessWidget {
  const _SelectChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.borderLight,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? Icons.check_rounded : Icons.add_rounded,
              size: 15,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The entry-point card shown on the last step of the add/edit property flow:
/// a master switch (binds [EligibilityConfig.enabled]) + a button that opens the
/// editor, plus a compact summary of the active rules and an honesty hint.
class EligibilityEntryCard extends StatelessWidget {
  const EligibilityEntryCard({
    super.key,
    required this.config,
    required this.onEnabledChanged,
    required this.onEdit,
  });

  final EligibilityConfig config;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Icon(IconsaxPlusLinear.filter_search,
                      color: AppColors.primary, size: 20),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'סינון שוכרים לפי קריטריונים',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'הצג את הדירה רק לשוכרים שעונים על הקריטריונים',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                    height: 1.35,
                  ),
                ),
              ),
              Switch(
                value: config.enabled,
                onChanged: onEnabledChanged,
                activeColor: AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'קריטריונים מעבר לתקציב/עיסוק מסתמכים על מידע שהשוכר עדיין '
            'לא בהכרח מילא — ולכן חסימה קשיחה ("חובה") עלולה לצמצם מאוד את '
            'מספר הרואים.',
            style: TextStyle(
              fontSize: 11.5,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onEdit,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(IconsaxPlusLinear.setting_4, size: 18),
              label: const Text(
                'הגדרת קריטריונים מדויקים',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(IconsaxPlusLinear.tick_circle,
                  size: 15, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                eligibilitySummaryLabel(config),
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
