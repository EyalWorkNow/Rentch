import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

// ─── Eligibility criteria catalog (F3) ────────────────────────────────────────
// The landlord defines precise tenant-eligibility criteria, each with a hardness
// level ('must'/'important'/'prefer'). Only matching tenants see the listing.
// Keys + value shapes MUST mirror EligibilityRule in rental_models.dart.

enum _EligInput { number, stepper, boolean, multi, single }

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

Map<String, String> _occupationOptions(AppLocalizations l10n) => {
      'hightech': l10n.eligibilityEditorSheet40d56dee,
      'healthcare': l10n.eligibilityEditorSheet6dfb51f1,
      'education': l10n.eligibilityEditorSheet19981c32,
      'finance': l10n.eligibilityEditorSheetEbfcd4cb,
      'law': l10n.eligibilityEditorSheet4f8aded7,
      'engineering': l10n.eligibilityEditorSheet453fe1ed,
      'selfemployed': l10n.eligibilityEditorSheetE1cad55a,
      'public': l10n.eligibilityEditorSheetCb481f30,
      'retail': l10n.eligibilityEditorSheet2834587d,
      'academia': l10n.eligibilityEditorSheet2157ec10,
      'student': l10n.eligibilityEditorSheet42ed7e8d,
      'other': l10n.eligibilityEditorSheetCdf4bce0,
    };

Map<String, String> _householdOptions(AppLocalizations l10n) => {
      'family': l10n.eligibilityEditorSheet926c043f,
      'single': l10n.eligibilityEditorSheetB8d9266b,
      'couple': l10n.eligibilityEditorSheet4df994d0,
      'student': l10n.eligibilityEditorSheet42ed7e8d,
    };

Map<String, String> _lifeStageOptions(AppLocalizations l10n) => {
      'student': l10n.eligibilityEditorSheet42ed7e8d,
      'young-professional': l10n.eligibilityEditorSheetD663155d,
      'family': l10n.eligibilityEditorSheet926c043f,
      'senior': l10n.eligibilityEditorSheet0aa42aa1,
    };

Map<String, String> _moveInOptions(AppLocalizations l10n) => {
      'immediate': l10n.eligibilityEditorSheetD02986c3,
      'month': l10n.eligibilityEditorSheetE9e8cbe3,
      'quarter': l10n.eligibilityEditorSheetDe0def2d,
    };

List<_Criterion> _catalog(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  return <_Criterion>[
    _Criterion('budgetMin', l10n.eligibilityEditorSheetB4d5170f,
        _EligInput.number, unit: '₪', defaultNumber: 5000),
    _Criterion('maxChildren', l10n.eligibilityEditorSheet976f97ac,
        _EligInput.stepper, min: 0, max: 5, defaultNumber: 2),
    _Criterion('noPets', l10n.eligibilityEditorSheetE70cb0b4, _EligInput.boolean),
    _Criterion('hasCar', l10n.eligibilityEditorSheetCb3c47ce, _EligInput.boolean),
    _Criterion('occupation', l10n.eligibilityEditorSheet15039c05, _EligInput.multi,
        options: _occupationOptions(l10n)),
    _Criterion('wfh', l10n.eligibilityEditorSheetF5203dea, _EligInput.boolean),
    _Criterion('household', l10n.eligibilityEditorSheet2b9fb355, _EligInput.multi,
        options: _householdOptions(l10n)),
    _Criterion('lifeStage', l10n.eligibilityEditorSheetD308ff19, _EligInput.multi,
        options: _lifeStageOptions(l10n)),
    _Criterion('oleh', l10n.eligibilityEditorSheet5f3306da, _EligInput.boolean),
    _Criterion('minAge', l10n.eligibilityEditorSheet8f9615bb, _EligInput.number,
        defaultNumber: 18),
    _Criterion('maxAge', l10n.eligibilityEditorSheetD5777fde, _EligInput.number,
        defaultNumber: 60),
    _Criterion(
        'accessibility', l10n.eligibilityEditorSheetD83eff6a, _EligInput.boolean),
    _Criterion('minRooms', l10n.eligibilityEditorSheetC3912164, _EligInput.number,
        defaultNumber: 3),
    _Criterion('moveInWithin', l10n.eligibilityEditorSheet29d40b0e,
        _EligInput.single, options: _moveInOptions(l10n)),
  ];
}

const _importanceLevels = <String>['must', 'important', 'prefer'];

String _importanceLabel(BuildContext context, String v) {
  final l10n = AppLocalizations.of(context)!;
  switch (v) {
    case 'important':
      return l10n.eligibilityEditorSheetC476594d;
    case 'prefer':
      return l10n.eligibilityEditorSheet0d3d4125;
    default:
      return l10n.eligibilityEditorSheet116f6cc8;
  }
}

String _importanceHelper(BuildContext context, String v) {
  final l10n = AppLocalizations.of(context)!;
  switch (v) {
    case 'important':
      return l10n.eligibilityEditorSheetA1caeddf;
    case 'prefer':
      return l10n.eligibilityEditorSheet44ca4acb;
    default:
      return l10n.eligibilityEditorSheet03b2388e;
  }
}

/// One-line summary of the active rules, e.g. "3 criteria · 1 required".
String eligibilitySummaryLabel(BuildContext context, EligibilityConfig config) {
  final l10n = AppLocalizations.of(context)!;
  final n = config.rules.length;
  if (n == 0) return l10n.eligibilityEditorSheet9786995c;
  final musts = config.rules.where((r) => r.importance == 'must').length;
  return musts > 0
      ? l10n.eligibilityEditorSheetE4f4cb81(n, musts)
      : l10n.eligibilityEditorSheetFf6c3b61(n);
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
  _EligibilityEditorSheet({required this.initial});
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
  final Map<String, String> _single = {};
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
        case _EligInput.single:
          final token = _stringFromValue(rule.value);
          if (token != null && crit.options.containsKey(token)) {
            _single[crit.key] = token;
          }
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
    for (final c in _catalog(context)) {
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

  String? _stringFromValue(dynamic v) {
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
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
          case _EligInput.single:
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
    for (final crit in _catalog(context)) {
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
        case _EligInput.single:
          final token = _single[crit.key];
          if (token == null || token.isEmpty) continue; // no choice → skip
          rules.add(EligibilityRule(
              key: crit.key, value: token, importance: importance));
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
    final l10n = AppLocalizations.of(context)!;
    final catalog = _catalog(context);
    return Directionality(
      textDirection: Directionality.of(context),
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.eligibilityEditorSheet2d483b2c,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.eligibilityEditorSheetD3b88de7,
                      style: const TextStyle(
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
                  itemCount: catalog.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _buildCriterionTile(catalog[i]),
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
      case _EligInput.single:
        final selected = _single[crit.key];
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in crit.options.entries)
              _SelectChip(
                label: entry.value,
                selected: selected == entry.key,
                onTap: () => setState(() {
                  if (_single[crit.key] == entry.key) {
                    _single.remove(crit.key);
                  } else {
                    _single[crit.key] = entry.key;
                  }
                }),
              ),
          ],
        );
      case _EligInput.boolean:
        return Text(
          AppLocalizations.of(context)!.eligibilityEditorSheetBb9a4c12,
          style: const TextStyle(
              fontSize: 12, color: AppColors.textSecondary, height: 1.35),
        );
    }
  }

  Widget _buildImportanceSelector(_Criterion crit) {
    final l10n = AppLocalizations.of(context)!;
    final current = _importance[crit.key] ?? 'must';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.eligibilityEditorSheet20d4985f,
          style: const TextStyle(
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
                      _importanceLabel(context, level),
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
          _importanceHelper(context, current),
          style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textSecondary,
              height: 1.35),
        ),
      ],
    );
  }

  Widget _buildSaveBar(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
                    ? l10n.eligibilityEditorSheet7c3236c7
                    : l10n.eligibilityEditorSheet7d5e1b03(count),
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
              child: Text(
                l10n.eligibilityEditorSheetE6932339,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  _StepperButton(
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
  _SelectChip(
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
  EligibilityEntryCard({
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
    final l10n = AppLocalizations.of(context)!;
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
              Expanded(
                child: Text(
                  l10n.eligibilityEditorSheet10ef20bd,
                  style: const TextStyle(
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
              Expanded(
                child: Text(
                  l10n.eligibilityEditorSheetCdb2baa7,
                  style: const TextStyle(
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
          Text(
            l10n.eligibilityEditorSheet7f538947,
            style: const TextStyle(
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
              label: Text(
                l10n.eligibilityEditorSheet2d483b2c,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
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
                eligibilitySummaryLabel(context, config),
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
