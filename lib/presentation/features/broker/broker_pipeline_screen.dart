import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/broker_lead.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/data/repositories/broker_lead_repository.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// פייפליין לידים — a broker's lead board.
///
/// Leads are grouped into vertical [LeadStage] sections (Hebrew headers + a
/// count each), so a broker can see at a glance where everyone stands. Anything
/// with an OVERDUE follow-up is hoisted into a red banner at the very top —
/// that's the whole point: nothing slips. Tapping a lead opens an actions sheet
/// to move stage, set/clear a follow-up date, or delete. Local-only via
/// [BrokerLeadRepository]; the provider is read READ-ONLY for the listing picker.
class BrokerPipelineScreen extends StatefulWidget {
  const BrokerPipelineScreen({super.key});

  @override
  State<BrokerPipelineScreen> createState() => _BrokerPipelineScreenState();
}

class _BrokerPipelineScreenState extends State<BrokerPipelineScreen> {
  final BrokerLeadRepository _repo = BrokerLeadRepository();
  List<BrokerLead> _leads = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final leads = await _repo.loadAll();
    if (!mounted) return;
    setState(() {
      _leads = leads;
      _loading = false;
    });
  }

  Future<void> _save(BrokerLead lead) async {
    final next = await _repo.save(lead);
    if (!mounted) return;
    setState(() => _leads = next);
  }

  Future<void> _delete(String id) async {
    final next = await _repo.delete(id);
    if (!mounted) return;
    setState(() => _leads = next);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final overdue = _leads.where((l) => l.isOverdue(now)).toList()
      ..sort((a, b) => a.nextFollowUp!.compareTo(b.nextFollowUp!));

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6FB),
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: const Text(
            'פייפליין לידים',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          onPressed: _openAddLead,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text(
            'ליד חדש',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _leads.isEmpty
                ? _emptyState()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      if (overdue.isNotEmpty) _overdueBanner(overdue),
                      for (final stage in LeadStage.values)
                        _stageSection(stage),
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
            Icon(Icons.groups_outlined,
                size: 72, color: AppColors.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            const Text(
              'אין עדיין לידים',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'הוסיפו לקוח מתעניין כדי לעקוב אחריו עד לסגירה',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _overdueBanner(List<BrokerLead> overdue) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.coral, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: AppColors.coral, size: 26),
              const SizedBox(width: 8),
              Text(
                'פולואפ באיחור (${overdue.length})',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: AppColors.coral,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final lead in overdue)
            InkWell(
              onTap: () => _openLeadActions(lead),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        lead.clientName,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      _dateLabel(lead.nextFollowUp!),
                      style: const TextStyle(
                          fontSize: 15,
                          color: AppColors.coral,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _stageSection(LeadStage stage) {
    final inStage = _leads.where((l) => l.stage == stage).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (inStage.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _stageColor(stage),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                stage.hebrew,
                style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Text(
                '(${inStage.length})',
                style: const TextStyle(
                    fontSize: 17, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        for (final lead in inStage) _leadCard(lead),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _leadCard(BrokerLead lead) {
    final now = DateTime.now();
    final overdue = lead.isOverdue(now);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openLeadActions(lead),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      lead.clientName,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (lead.source.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight2,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        lead.source,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryDark),
                      ),
                    ),
                ],
              ),
              if (lead.propertyTitle.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.home_outlined,
                        size: 17, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        lead.propertyTitle,
                        style: const TextStyle(
                            fontSize: 15, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
              if (lead.phone.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.phone_outlined,
                        size: 17, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(lead.phone,
                        style: const TextStyle(
                            fontSize: 15, color: AppColors.textSecondary)),
                  ],
                ),
              ],
              if (lead.nextFollowUp != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.event_outlined,
                        size: 17,
                        color: overdue ? AppColors.coral : AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      'פולואפ: ${_dateLabel(lead.nextFollowUp!)}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: overdue ? AppColors.coral : AppColors.primary,
                      ),
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

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _openLeadActions(BrokerLead lead) async {
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
                    lead.clientName,
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  const Text('העברה לשלב:',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final stage in LeadStage.values)
                        ChoiceChip(
                          label: Text(stage.hebrew,
                              style: const TextStyle(fontSize: 15)),
                          selected: stage == lead.stage,
                          selectedColor: AppColors.primaryLight2,
                          onSelected: (_) {
                            Navigator.pop(sheetContext);
                            _save(lead.copyWith(stage: stage));
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.event, color: AppColors.primary),
                    title: const Text('קביעת פולואפ',
                        style: TextStyle(fontSize: 17)),
                    subtitle: lead.nextFollowUp == null
                        ? null
                        : Text(_dateLabel(lead.nextFollowUp!)),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await _pickFollowUp(lead);
                    },
                  ),
                  if (lead.nextFollowUp != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_busy,
                          color: AppColors.textSecondary),
                      title: const Text('הסרת פולואפ',
                          style: TextStyle(fontSize: 17)),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _save(lead.copyWith(clearFollowUp: true));
                      },
                    ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.delete_outline,
                        color: AppColors.coral),
                    title: const Text('מחיקת ליד',
                        style: TextStyle(
                            fontSize: 17, color: AppColors.coral)),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _delete(lead.id);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickFollowUp(BrokerLead lead) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: lead.nextFollowUp ?? now.add(const Duration(days: 1)),
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null) return;
    await _save(lead.copyWith(nextFollowUp: date));
  }

  Future<void> _openAddLead() async {
    final myProperties = context.read<DatingProvider>().myProperties;
    final lead = await showModalBottomSheet<BrokerLead>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddLeadSheet(properties: myProperties),
    );
    if (lead != null) await _save(lead);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static String _dateLabel(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  static Color _stageColor(LeadStage stage) {
    switch (stage) {
      case LeadStage.newLead:
        return AppColors.primary;
      case LeadStage.contacted:
        return const Color(0xFF4A6CF7);
      case LeadStage.viewing:
        return AppColors.warning;
      case LeadStage.negotiation:
        return const Color(0xFFE67E22);
      case LeadStage.closedWon:
        return AppColors.success;
      case LeadStage.closedLost:
        return AppColors.textSecondary;
    }
  }
}

/// Bottom sheet that collects a new lead. Returns a [BrokerLead] on save.
class _AddLeadSheet extends StatefulWidget {
  const _AddLeadSheet({required this.properties});

  final List<RentalProperty> properties;

  @override
  State<_AddLeadSheet> createState() => _AddLeadSheetState();
}

class _AddLeadSheetState extends State<_AddLeadSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _notes = TextEditingController();
  String _source = 'yad2';
  RentalProperty? _property;

  static const _sources = ['yad2', 'whatsapp', 'טלפון', 'הגיע למשרד', 'אחר'];

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('יש להזין שם לקוח')),
      );
      return;
    }
    Navigator.pop(
      context,
      BrokerLead(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        clientName: name,
        phone: _phone.text.trim(),
        propertyId: _property?.id ?? '',
        propertyTitle: _property == null ? '' : _propertyLabel(_property!),
        source: _source,
        notes: _notes.text.trim(),
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
                child: Text('ליד חדש',
                    style: TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 20),
              _field(_name, 'שם הלקוח *', TextInputType.name),
              const SizedBox(height: 12),
              _field(_phone, 'טלפון', TextInputType.phone),
              const SizedBox(height: 16),
              const Text('מקור הליד:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in _sources)
                    ChoiceChip(
                      label: Text(s, style: const TextStyle(fontSize: 15)),
                      selected: _source == s,
                      selectedColor: AppColors.primaryLight2,
                      onSelected: (_) => setState(() => _source = s),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('נכס מקושר:',
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
              const SizedBox(height: 12),
              _field(_notes, 'הערות', TextInputType.multiline, maxLines: 2),
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
    TextEditingController c,
    String label,
    TextInputType type, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: c,
      keyboardType: type,
      maxLines: maxLines,
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

  static String _propertyLabel(RentalProperty p) {
    final street = p.street.trim();
    final city = p.city.trim();
    if (street.isNotEmpty && city.isNotEmpty) return '$street, $city';
    if (street.isNotEmpty) return street;
    if (city.isNotEmpty) return city;
    return p.propertyType;
  }
}
