import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/contract_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

/// Landlord-facing form to draft + send a rental contract for a match.
class ContractFormScreen extends StatefulWidget {
  const ContractFormScreen({super.key, required this.matchId});
  final String matchId;

  @override
  State<ContractFormScreen> createState() => _ContractFormScreenState();
}

class _ContractFormScreenState extends State<ContractFormScreen> {
  final _rentCtrl = TextEditingController();
  final _depositCtrl = TextEditingController();
  final _termsCtrl = TextEditingController();
  int _durationMonths = 12;
  DateTime _startDate = DateTime.now().add(const Duration(days: 14));
  bool _sending = false;

  static const _durations = [6, 12, 18, 24, 36];

  @override
  void dispose() {
    _rentCtrl.dispose();
    _depositCtrl.dispose();
    _termsCtrl.dispose();
    super.dispose();
  }

  int _asInt(String s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _send() async {
    final rent = _asInt(_rentCtrl.text);
    if (rent <= 0) {
      _err('יש להזין שכר דירה חודשי');
      return;
    }
    setState(() => _sending = true);
    final provider = context.read<DatingProvider>();
    final contract = await provider.createRentalContract(
      matchId: widget.matchId,
      monthlyRent: rent,
      deposit: _asInt(_depositCtrl.text),
      durationMonths: _durationMonths,
      startDate: _startDate,
      terms: _termsCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (contract == null) {
      _err('לא ניתן ליצור חוזה כרגע. נסו שוב.');
      return;
    }
    HapticFeedback.mediumImpact();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            ContractDetailScreen(contractId: contract.id, matchId: widget.matchId),
      ),
    );
  }

  void _err(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('חוזה שכירות חדש')),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: SizedBox(
          height: 54,
          child: FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(IconsaxPlusLinear.document_text, size: 18),
            label: Text(_sending ? 'שולח…' : 'שלח לחתימה'),
          ),
        ),
      ),
      // Tap anywhere (or drag the list) to dismiss the keyboard.
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _card(
            title: 'תנאי השכירות',
            icon: IconsaxPlusLinear.money_recive,
            children: [
              _numberField(_rentCtrl, 'שכר דירה חודשי (₪)',
                  IconsaxPlusLinear.money),
              const SizedBox(height: 12),
              _numberField(_depositCtrl, 'פיקדון / ערבון (₪)',
                  IconsaxPlusLinear.security),
              const SizedBox(height: 18),
              const Text('תקופת השכירות',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _durations.map((m) {
                  final sel = m == _durationMonths;
                  return GestureDetector(
                    onTap: () => setState(() => _durationMonths = m),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: sel ? AppColors.primary : AppColors.background,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: sel
                                ? AppColors.primary
                                : AppColors.borderLight),
                      ),
                      child: Text('$m חודשים',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: sel ? Colors.white : AppColors.navy)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              GestureDetector(
                onTap: _pickStartDate,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Row(
                    children: [
                      const RentlyCalendarIcon(),
                      const SizedBox(width: 12),
                      const Text('תאריך כניסה',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text(
                        '${_startDate.day}/${_startDate.month}/${_startDate.year}',
                        style: const TextStyle(
                            color: AppColors.navy,
                            fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _card(
            title: 'סעיפים נוספים',
            icon: IconsaxPlusLinear.document_text,
            children: [
              TextField(
                controller: _termsCtrl,
                maxLines: 6,
                minLines: 4,
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  hintText:
                      'לדוגמה: תשלום עד ה-10 בכל חודש, החזקת חיות מחמד באישור, אחריות על תיקונים…',
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.borderLight),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(IconsaxPlusLinear.shield_tick,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'החוזה ייחתם בחתימה דיגיטלית מאובטחת מקצה לקצה. כל צד חותם במכשירו, וכל שינוי בתנאים יבטל חתימות קודמות.',
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ],
        ),
      ),
    );
  }

  Widget _numberField(
      TextEditingController c, String label, IconData icon) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textDirection: TextDirection.rtl,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18, color: AppColors.primary),
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
      ),
    );
  }

  Widget _card(
      {required String title,
      required IconData icon,
      required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle),
                child: Icon(icon, size: 16, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Text(title,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppColors.navy)),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class RentlyCalendarIcon extends StatelessWidget {
  const RentlyCalendarIcon({super.key});
  @override
  Widget build(BuildContext context) =>
      Icon(IconsaxPlusLinear.calendar_1, size: 18, color: AppColors.primary);
}
