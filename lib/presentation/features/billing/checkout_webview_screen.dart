import 'package:dating_app/core/constants/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Hosted-payment-page WebView. Loads the checkout [url] returned by
/// `POST /billing/checkout`; when the page navigates back to our return hook
/// (`/hooks/return`), the navigation is PREVENTED and the screen pops with a
/// bool result: true when the return url carries `status=success`, false
/// otherwise. The caller then refreshes + polls the subscription.
///
/// The card form itself is Grow/Meshulam's hosted page (their domain — we can't
/// restyle it). Everything AROUND it — the branded header, the secure-payment
/// trust strip, the loading state and the footer — is ours, so the in-app
/// payment moment still feels like RENTLY.
class CheckoutWebViewScreen extends StatefulWidget {
  const CheckoutWebViewScreen({super.key, required this.url, this.amountLabel});

  final String url;

  /// Optional amount shown in the secure header, e.g. "₪35 / חודש" or "₪50".
  final String? amountLabel;

  @override
  State<CheckoutWebViewScreen> createState() => _CheckoutWebViewScreenState();
}

class _CheckoutWebViewScreenState extends State<CheckoutWebViewScreen> {
  // Design tokens — the Light iOS indigo/navy system shared with PaywallScreen
  // and SubscriptionScreen.
  static const _indigo = Color(0xFF4F46E5);
  static const _navy = Color(0xFF0F172A);
  static const _slate = Color(0xFF64748B);
  static const _indigoBg = Color(0xFFEEF2FF);

  late final WebViewController _controller;
  bool _loading = true;
  bool _handled = false; // guard against a double pop from url-change + request

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          if (_isReturnUrl(request.url)) {
            _finish(request.url);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onUrlChange: (change) {
          final url = change.url;
          if (url != null && _isReturnUrl(url)) _finish(url);
        },
        onPageStarted: (_) {
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
      ))
      ..loadRequest(Uri.parse(_safeUrl(widget.url)));
  }

  // Guard against a malformed checkout URL from the backend (Uri.parse throws;
  // Uri.tryParse doesn't). A bad URL just shows a blank page instead of crashing.
  static String _safeUrl(String url) =>
      Uri.tryParse(url) != null ? url : 'about:blank';

  // Match the return hook on the parsed PATH only (not anywhere in the URL, so a
  // '/hooks/return' substring inside a query param or third-party domain can't
  // be mistaken for our redirect).
  bool _isReturnUrl(String url) {
    final path = Uri.tryParse(url)?.path ?? '';
    return path.endsWith('/hooks/return');
  }

  void _finish(String url) {
    if (_handled || !mounted) return;
    _handled = true;
    final status = Uri.tryParse(url)?.queryParameters['status'];
    Navigator.of(context).pop(status == 'success');
  }

  void _close() {
    // Share the same double-pop guard as _finish so a close tap racing the
    // return-URL redirect can't pop an extra (unrelated) screen.
    if (_handled || !mounted) return;
    _handled = true;
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: _navy,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(IconsaxPlusLinear.close_circle),
            onPressed: _close,
          ),
          centerTitle: true,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'RENTLY',
                style: TextStyle(
                  color: _navy,
                  fontWeight: FontWeight.w900,
                  fontSize: 19,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                decoration: BoxDecoration(
                  color: _indigoBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _indigo.withOpacity(0.35),
                    width: 1.2,
                  ),
                ),
                child: const Text(
                  'PRO',
                  style: TextStyle(
                    color: Color(0xFF4338CA),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(color: AppColors.divider, height: 1, thickness: 1),
          ),
        ),
        body: Column(
          children: [
            _secureHeader(),
            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  if (_loading) _loadingOverlay(),
                ],
              ),
            ),
            _trustFooter(),
          ],
        ),
      ),
    );
  }

  // Branded "secure payment" strip above the hosted form.
  Widget _secureHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: const Color(0xFFFBFCFF),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _indigoBg,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(IconsaxPlusBold.shield_tick,
                color: _indigo, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'תשלום מאובטח',
                  style: TextStyle(
                    color: _navy,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'הסליקה מתבצעת בעמוד המאובטח של Grow',
                  style: TextStyle(
                    color: _slate,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (widget.amountLabel != null) ...[
            const SizedBox(width: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _indigo,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                widget.amountLabel!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Full-bleed branded loading state (replaces the bare spinner) so the moment
  // before Grow's page paints still looks intentional.
  Widget _loadingOverlay() {
    return Container(
      color: Colors.white,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              valueColor: AlwaysStoppedAnimation(_indigo),
            ),
          ),
          SizedBox(height: 16),
          Text(
            'טוען דף תשלום מאובטח…',
            style: TextStyle(
              color: _slate,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // Trust footer: encryption reassurance + accepted methods.
  Widget _trustFooter() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, 10 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Color(0xFFFBFCFF),
        border: Border(top: BorderSide(color: AppColors.divider, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(IconsaxPlusLinear.lock_1, size: 13, color: _slate),
              SizedBox(width: 6),
              Text(
                'מוצפן SSL · פרטי הכרטיס לא נשמרים באפליקציה',
                style: TextStyle(
                  color: _slate,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          const Text(
            'Visa · Mastercard · אמריקן אקספרס · Bit',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
