import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/deep_link_service.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// PATH A — external-browser checkout for web wallets (Apple Pay / Google Pay).
///
/// Those wallets can't validate inside the app's in-app WebView, so the hosted
/// Grow page is opened in the SYSTEM browser (Safari/Chrome) where Apple/Google
/// Pay work. This screen stays up while the user pays outside the app, and
/// completes when they return — either automatically (Grow's return page deep-
/// links back to `rently://billing/return?status=success`) or by tapping
/// "שילמתי — המשך". It pops `true` to let the caller run the same confirm/poll
/// used by the card flow (activation still requires a REAL verified receipt, so
/// a premature tap can't unlock anything).
class ExternalCheckoutScreen extends StatefulWidget {
  const ExternalCheckoutScreen({super.key, required this.url, this.amountLabel});

  final String url;
  final String? amountLabel;

  @override
  State<ExternalCheckoutScreen> createState() => _ExternalCheckoutScreenState();
}

class _ExternalCheckoutScreenState extends State<ExternalCheckoutScreen> {
  bool _launchFailed = false;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    // Auto-complete if Grow's return page deep-links back to the app.
    DeepLinkService.addBillingReturnListener(_onDeepLinkReturn);
    WidgetsBinding.instance.addPostFrameCallback((_) => _launch());
  }

  @override
  void dispose() {
    DeepLinkService.removeBillingReturnListener(_onDeepLinkReturn);
    super.dispose();
  }

  void _onDeepLinkReturn(bool success) {
    if (_handled || !mounted) return;
    _handled = true;
    Navigator.of(context).pop(success);
  }

  Future<void> _launch() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null) {
      if (mounted) setState(() => _launchFailed = true);
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (mounted) setState(() => _launchFailed = !ok);
    } catch (_) {
      if (mounted) setState(() => _launchFailed = true);
    }
  }

  void _done() {
    if (_handled) return;
    _handled = true;
    Navigator.of(context).pop(true); // caller confirms via the server receipt
  }

  void _cancel() {
    if (_handled) return;
    _handled = true;
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.slate900,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(IconsaxPlusLinear.close_circle),
            onPressed: _cancel,
          ),
          centerTitle: true,
          title: const Text('RENTLY PRO',
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  letterSpacing: 1.1)),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 20),
            child: Column(
              children: [
                const Spacer(),
                Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                      _launchFailed
                          ? IconsaxPlusBold.warning_2
                          : IconsaxPlusBold.export_3,
                      size: 34,
                      color: _launchFailed ? AppColors.coral : AppColors.primary),
                ),
                const SizedBox(height: 20),
                Text(
                  _launchFailed
                      ? l10n.externalCheckoutScreenEd6f8b3f
                      : l10n.externalCheckoutScreenFed753f2,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.slate900,
                      fontSize: 21,
                      fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                Text(
                  _launchFailed
                      ? l10n.externalCheckoutScreenC8dbc943
                      : l10n.externalCheckoutScreen62ff1866 +
                          l10n.externalCheckoutScreen0a561779,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.5,
                      fontWeight: FontWeight.w600),
                ),
                if (widget.amountLabel != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(widget.amountLabel!,
                        style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 15,
                            fontWeight: FontWeight.w900)),
                  ),
                ],
                const Spacer(),
                if (!_launchFailed)
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28)),
                      ),
                      onPressed: _done,
                      child: Text(l10n.externalCheckoutScreen67490ed7,
                          style: const TextStyle(
                              fontSize: 16.5, fontWeight: FontWeight.w900)),
                    ),
                  ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.slate900,
                      side: const BorderSide(color: AppColors.divider),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28)),
                    ),
                    onPressed: () => _launch(),
                    child: Text(
                        _launchFailed
                            ? l10n.externalCheckoutScreenC4455ef4
                            : l10n.externalCheckoutScreen81b0db62,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: _cancel,
                  child: Text(l10n.externalCheckoutScreenA7c55a8d,
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
