import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_contract.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/widgets/signature_pad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

/// Clean, built-in contract SIGNING flow — designed tenant-first but used by both
/// parties. One screen that walks you through:
///   1. review the terms,
///   2. see the parties + who has already signed,
///   3. one-tap "חתום",
/// with clear states (ממתין לחתימה / נחתם ע"י X / הושלם) and the existing
/// tamper-evident Ed25519 signing kept intact.
class ContractSignFlowScreen extends StatelessWidget {
  const ContractSignFlowScreen({
    super.key,
    required this.contractId,
    required this.matchId,
  });

  final String contractId;
  final String matchId;

  RentalContract? _find(DatingProvider p) {
    for (final c in p.contracts) {
      if (c.id == contractId) return c;
    }
    return p.contractForMatch(matchId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('חתימה על החוזה')),
      body: Consumer<DatingProvider>(
        builder: (context, provider, _) {
          final contract = _find(provider);
          if (contract == null) {
            return const _EmptyState();
          }
          final isLandlord = provider.isLandlord;
          final myRole = isLandlord ? 'landlord' : 'tenant';
          final mySig = contract.signatureForRole(myRole);
          final terminal = contract.status == ContractStatus.cancelled ||
              contract.status == ContractStatus.declined;
          final canSign = mySig == null && !terminal;

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  children: [
                    _ProgressStrip(contract: contract, myRole: myRole),
                    const SizedBox(height: 16),
                    _TermsCard(contract: contract),
                    const SizedBox(height: 14),
                    const _SectionLabel('הצדדים והחתימות'),
                    const SizedBox(height: 8),
                    _PartyRow(
                      label: 'בעל הדירה',
                      name: contract.landlordName,
                      signature: contract.landlordSignature,
                      isYou: isLandlord,
                    ),
                    const SizedBox(height: 8),
                    _PartyRow(
                      label: 'השוכר/ת',
                      name: contract.tenantName,
                      signature: contract.tenantSignature,
                      isYou: !isLandlord,
                    ),
                    const SizedBox(height: 16),
                    const _SecurityNote(),
                  ],
                ),
              ),
              _BottomBar(
                contract: contract,
                canSign: canSign,
                isLandlord: isLandlord,
                alreadySignedByMe: mySig != null,
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Progress / status strip ──────────────────────────────────────────────────

class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip({required this.contract, required this.myRole});
  final RentalContract contract;
  final String myRole;

  @override
  Widget build(BuildContext context) {
    final done = contract.isFullySigned;
    final terminal = contract.status == ContractStatus.cancelled ||
        contract.status == ContractStatus.declined;

    final (label, sub, color, icon) = _state();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 15)),
              ),
            ],
          ),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(right: 34),
              child: Text(sub,
                  style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: AppColors.textSecondary)),
            ),
          ],
          if (!terminal) ...[
            const SizedBox(height: 14),
            _Steps(
              landlordSigned: contract.isLandlordSigned,
              tenantSigned: contract.isTenantSigned,
              done: done,
            ),
          ],
        ],
      ),
    );
  }

  (String, String, Color, IconData) _state() {
    const green = AppColors.green;
    if (contract.status == ContractStatus.cancelled) {
      return ('החוזה בוטל', '', AppColors.coral, Icons.cancel_outlined);
    }
    if (contract.status == ContractStatus.declined) {
      return ('החוזה נדחה', '', AppColors.coral, Icons.cancel_outlined);
    }
    if (contract.isFullySigned) {
      return (
        'הושלם — נחתם ע״י שני הצדדים',
        'החוזה תקף וחתום דיגיטלית. ניתן לצפות בו בכל עת.',
        green,
        Icons.verified_rounded,
      );
    }
    final mySigned = contract.signatureForRole(myRole) != null;
    if (mySigned) {
      final other = myRole == 'landlord' ? 'השוכר/ת' : 'בעל הדירה';
      return (
        'חתמת — ממתין לחתימת $other',
        'נשלחה התראה לצד השני. ברגע שיחתום/תחתום, החוזה יושלם.',
        AppColors.primary,
        Icons.hourglass_bottom_rounded,
      );
    }
    if (contract.isLandlordSigned) {
      return (
        'בעל הדירה חתם · ממתין לחתימתך',
        'עברו על התנאים ולחצו "חתום" כדי להשלים את החוזה.',
        AppColors.primary,
        Icons.edit_document,
      );
    }
    return (
      'ממתין לחתימה',
      'עברו על התנאים ולחצו "חתום" כדי להתחיל.',
      AppColors.primary,
      Icons.edit_document,
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({
    required this.landlordSigned,
    required this.tenantSigned,
    required this.done,
  });
  final bool landlordSigned;
  final bool tenantSigned;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _dot(landlordSigned, 'בעל הדירה'),
        _line(landlordSigned && tenantSigned),
        _dot(tenantSigned, 'שוכר/ת'),
        _line(done),
        _dot(done, 'הושלם'),
      ],
    );
  }

  Widget _dot(bool on, String label) {
    const green = AppColors.green;
    return Column(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: on ? green : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
                color: on ? green : AppColors.borderLight, width: 1.6),
          ),
          child: on
              ? const Icon(Icons.check, size: 13, color: Colors.white)
              : null,
        ),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: on ? green : AppColors.textSecondary)),
      ],
    );
  }

  Widget _line(bool on) => Expanded(
        child: Container(
          height: 2,
          margin: const EdgeInsets.only(bottom: 18),
          color: on ? AppColors.green : AppColors.borderLight,
        ),
      );
}

// ─── Terms card ───────────────────────────────────────────────────────────────

class _TermsCard extends StatelessWidget {
  const _TermsCard({required this.contract});
  final RentalContract contract;

  String _d(DateTime x) => '${x.day}/${x.month}/${x.year}';

  @override
  Widget build(BuildContext context) {
    final c = contract;
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
          Text(c.propertyTitle.isNotEmpty ? c.propertyTitle : 'נכס להשכרה',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy)),
          const SizedBox(height: 14),
          _row('שכר דירה חודשי', '₪${c.monthlyRent}'),
          _row('פיקדון', c.deposit > 0 ? '₪${c.deposit}' : '—'),
          _row('תקופה', '${c.durationMonths} חודשים'),
          _row('כניסה', _d(c.startDate)),
          _row('סיום', _d(c.endDate)),
          if (c.additionalTerms.trim().isNotEmpty) ...[
            const Divider(height: 24, color: AppColors.borderLight),
            const Text('נוסח החוזה',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Text(c.additionalTerms,
                style: const TextStyle(
                    fontSize: 12.5, height: 1.55, color: AppColors.navy)),
          ],
        ],
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            Text(v,
                style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 14,
                    fontWeight: FontWeight.w800)),
          ],
        ),
      );
}

// ─── Party row ────────────────────────────────────────────────────────────────

class _PartyRow extends StatelessWidget {
  const _PartyRow({
    required this.label,
    required this.name,
    required this.signature,
    required this.isYou,
  });

  final String label;
  final String name;
  final ContractSignature? signature;
  final bool isYou;

  @override
  Widget build(BuildContext context) {
    final sig = signature;
    final signed = sig != null;
    const green = AppColors.green;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: signed ? green.withValues(alpha: 0.4) : AppColors.borderLight),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: signed
                ? green.withValues(alpha: 0.12)
                : AppColors.primary.withValues(alpha: 0.1),
            child: Icon(
              signed ? Icons.verified_rounded : IconsaxPlusLinear.user,
              size: 18,
              color: signed ? green : AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary)),
                    if (isYou)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('זה אתה',
                            style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                color: AppColors.primary)),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(name.isNotEmpty ? name : '—',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: AppColors.navy)),
                const SizedBox(height: 4),
                Text(
                  signed
                      ? _signedLine(sig)
                      : 'ממתין לחתימה',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: signed ? green : AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (signed && sig.signatureImageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                sig.signatureImageUrl,
                width: 78,
                height: 42,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }

  String _signedLine(ContractSignature sig) {
    final when = sig.signedAt;
    if (when == null) return 'נחתם';
    return 'נחתם · ${when.day}/${when.month}/${when.year}';
  }
}

// ─── Bottom action bar ────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.contract,
    required this.canSign,
    required this.isLandlord,
    required this.alreadySignedByMe,
  });

  final RentalContract contract;
  final bool canSign;
  final bool isLandlord;
  final bool alreadySignedByMe;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: SizedBox(
        height: 54,
        width: double.infinity,
        child: canSign
            ? FilledButton.icon(
                onPressed: () => _openSignSheet(context),
                icon: const Icon(IconsaxPlusLinear.edit, size: 18),
                label: Text('חתום כ${isLandlord ? 'בעל הדירה' : 'שוכר/ת'}'),
              )
            : OutlinedButton.icon(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(
                  alreadySignedByMe
                      ? Icons.check_circle_rounded
                      : Icons.arrow_forward_rounded,
                  size: 18,
                ),
                label: Text(
                  alreadySignedByMe
                      ? (contract.isFullySigned
                          ? 'החוזה הושלם'
                          : 'חתמת · ממתין לצד השני')
                      : 'חזרה',
                ),
              ),
      ),
    );
  }

  Future<void> _openSignSheet(BuildContext context) async {
    final provider = context.read<DatingProvider>();
    final controller = SignaturePadController();
    final signed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _SignSheet(
        controller: controller,
        provider: provider,
        contract: contract,
        asOwner: isLandlord,
      ),
    );
    controller.dispose();
    if (signed == true && context.mounted) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('החתימה נשמרה בהצלחה ✍️')),
      );
    }
  }
}

// ─── Signing bottom sheet ─────────────────────────────────────────────────────

class _SignSheet extends StatefulWidget {
  const _SignSheet({
    required this.controller,
    required this.provider,
    required this.contract,
    required this.asOwner,
  });

  final SignaturePadController controller;
  final DatingProvider provider;
  final RentalContract contract;
  final bool asOwner;

  @override
  State<_SignSheet> createState() => _SignSheetState();
}

class _SignSheetState extends State<_SignSheet> {
  bool _busy = false;

  Future<void> _confirm() async {
    if (widget.controller.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('יש לחתום במסגרת לפני האישור')),
      );
      return;
    }
    setState(() => _busy = true);
    final png = await widget.controller.exportPng();
    await widget.provider.signRentalContract(
      widget.contract,
      asOwner: widget.asOwner,
      signatureImage: png,
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.borderLight,
                      borderRadius: BorderRadius.circular(999)),
                ),
              ),
              const SizedBox(height: 16),
              const Text('חתימה דיגיטלית',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.navy)),
              const SizedBox(height: 4),
              const Text('חתמו עם האצבע במסגרת למטה',
                  textAlign: TextAlign.right,
                  style:
                      TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 14),
              SignaturePad(controller: widget.controller),
              const SizedBox(height: 10),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: widget.controller.clear,
                    icon: const Icon(IconsaxPlusLinear.refresh, size: 16),
                    label: const Text('נקה'),
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _confirm,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(IconsaxPlusLinear.tick_circle, size: 18),
                  label: Text(_busy ? 'חותם…' : 'אשר חתימה'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Small pieces ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: AppColors.navy)),
      );
}

class _SecurityNote extends StatelessWidget {
  const _SecurityNote();
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(IconsaxPlusLinear.shield_tick,
              size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'חתימה דיגיטלית מאובטחת (Ed25519). המפתח הפרטי נשמר במכשירך בלבד; '
              'כל שינוי בתנאים מבטל חתימות שכבר נחתמו.',
              style: TextStyle(
                  fontSize: 11.5, height: 1.5, color: AppColors.textSecondary),
            ),
          ),
        ],
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(IconsaxPlusLinear.document,
                size: 48, color: AppColors.textDisabled),
            const SizedBox(height: 14),
            const Text('החוזה לא נמצא',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy)),
            const SizedBox(height: 6),
            const Text(
              'נסו לרענן את הצ׳אט. אם בעל הדירה עדיין לא שלח חוזה — הוא יופיע כאן ברגע שיישלח.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, height: 1.5, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
