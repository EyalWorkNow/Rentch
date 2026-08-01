import 'dart:async';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:url_launcher/url_launcher.dart';
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
  bool _error = false; // page failed to load / timed out
  bool _handled = false; // guard against a double pop from url-change + request
  Timer? _watchdog; // fails the load gracefully if the page never finishes

  // If the hosted page hasn't finished loading within this window, show an error
  // instead of spinning forever. Only guards the INITIAL load — once the page is
  // up, the user can take as long as they need to fill the form.
  static const Duration _loadTimeout = Duration(seconds: 30);

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
          // Non-web schemes (bit://, tel:, mailto:, intent://, itms-apps://…)
          // can't load in a WebView — hand them to the OS (e.g. Bit opens the
          // Bit app). Prevent the WebView from trying and erroring.
          final scheme = Uri.tryParse(request.url)?.scheme.toLowerCase() ?? '';
          if (scheme.isNotEmpty && scheme != 'http' && scheme != 'https') {
            _launchExternal(request.url);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onUrlChange: (change) {
          final url = change.url;
          if (url != null && _isReturnUrl(url)) _finish(url);
        },
        onPageStarted: (_) {
          if (!mounted) return;
          setState(() {
            _loading = true;
            _error = false;
          });
          _armWatchdog();
        },
        onPageFinished: (_) {
          _watchdog?.cancel();
          if (mounted) setState(() => _loading = false);
        },
        onWebResourceError: (err) {
          // Ignore sub-resource failures (a stray beacon/asset) — only a
          // main-frame failure means the checkout page itself didn't load.
          if (err.isForMainFrame == false) return;
          _failLoad();
        },
        onHttpError: (err) {
          if (err.response?.statusCode != null &&
              err.response!.statusCode >= 400) {
            _failLoad();
          }
        },
      ))
      ..loadRequest(Uri.parse(_safeUrl(widget.url)));
    _armWatchdog();
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(_loadTimeout, () {
      if (mounted && _loading && !_handled) _failLoad();
    });
  }

  void _failLoad() {
    _watchdog?.cancel();
    if (!mounted || _handled) return;
    setState(() {
      _loading = false;
      _error = true;
    });
  }

  void _retry() {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = false;
    });
    _controller.loadRequest(Uri.parse(_safeUrl(widget.url)));
    _armWatchdog();
  }

  Future<void> _launchExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {/* app not installed / can't handle — leave the page as-is */}
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
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
                  if (_error)
                    _errorOverlay()
                  else if (_loading)
                    _loadingOverlay(),
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

  // Shown when the hosted page fails to load or times out — instead of an
  // endless spinner, the user gets a clear message with retry / go-back.
  Widget _errorOverlay() {
    return Container(
      color: Colors.white,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(IconsaxPlusBold.wifi_square,
                color: Color(0xFFEF4444), size: 30),
          ),
          const SizedBox(height: 18),
          const Text(
            'דף התשלום לא נטען',
            style: TextStyle(
                color: _navy, fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text(
            'ייתכן שיש בעיית רשת או שאמצעי התשלום אינו זמין כרגע. אפשר לנסות שוב או לחזור ולבחור אמצעי אחר.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: _slate,
                fontSize: 13.5,
                height: 1.5,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: _close,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _navy,
                  side: const BorderSide(color: AppColors.divider),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 13),
                ),
                child: const Text('חזרה',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _retry,
                style: FilledButton.styleFrom(
                  backgroundColor: _indigo,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 13),
                ),
                child: const Text('נסו שוב',
                    style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ],
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
