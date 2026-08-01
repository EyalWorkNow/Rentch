import 'package:dating_app/presentation/features/billing/checkout_webview_screen.dart';
import 'package:dating_app/presentation/features/billing/external_checkout_screen.dart';
import 'package:dating_app/presentation/features/billing/payment_method_selector.dart';
import 'package:flutter/material.dart';

/// Opens the hosted Grow checkout in the right container for the chosen method
/// and returns whether the user completed it (`true`) — the caller then confirms
/// via the server receipt.
///
/// - Card / Bit render inside the in-app WebView ([CheckoutWebViewScreen]).
/// - Apple Pay / Google Pay (web wallets) can't validate in a WebView, so they
///   open in the SYSTEM browser ([ExternalCheckoutScreen], Path A).
Future<bool?> openHostedCheckout(
  BuildContext context, {
  required String url,
  required int group,
  String? amountLabel,
}) {
  final page = isWalletGroup(group)
      ? ExternalCheckoutScreen(url: url, amountLabel: amountLabel)
      : CheckoutWebViewScreen(url: url, amountLabel: amountLabel);
  return Navigator.of(context).push<bool>(MaterialPageRoute(
    settings: const RouteSettings(name: 'CheckoutScreen'),
    builder: (_) => page,
  ));
}
