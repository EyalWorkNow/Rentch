import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/property_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Opens an incoming deep link straight at the apartment page — both the custom
/// `rently://property/<id>` scheme and the https Universal/App Links that back
/// shared links (WhatsApp etc.): `https://<host>/p/<id>` and the stage-prefixed
/// `https://<host>/prod/p/<id>`. Uses the app's global [navigatorKey] so it can
/// push from outside the widget tree (cold start or while running).
class DeepLinkService {
  DeepLinkService(this.navigatorKey);
  final GlobalKey<NavigatorState> navigatorKey;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  Future<void> init() async {
    try {
      final initial = await _appLinks.getInitialLink(); // opened BY the link
      if (initial != null) _handle(initial);
    } catch (_) {/* no initial link */}
    _sub = _appLinks.uriLinkStream.listen(_handle, onError: (_) {});
  }

  void dispose() => _sub?.cancel();

  // ── billing return (Path A: external-browser wallet checkout) ───────────────
  // Grow's return page deep-links back to `rently://billing/return?status=…`
  // after an Apple/Google Pay payment in the system browser. The external
  // checkout screen registers here to auto-complete when the app foregrounds.
  static final Set<void Function(bool success)> _billingListeners = {};
  static void addBillingReturnListener(void Function(bool) l) =>
      _billingListeners.add(l);
  static void removeBillingReturnListener(void Function(bool) l) =>
      _billingListeners.remove(l);

  void _handle(Uri uri) {
    if (uri.scheme == 'rently' && uri.host == 'billing') {
      final ok = uri.queryParameters['status'] == 'success';
      for (final l in _billingListeners.toList()) {
        l(ok);
      }
      return;
    }
    final id = propertyIdFrom(uri);
    if (id != null) _openProperty(id);
  }

  /// Extracts the target property id from a supported deep link, or null when
  /// the URI isn't one we route. Pure + static so it's unit-testable.
  ///
  /// Supported forms:
  ///   • `rently://property/<id>`        — custom scheme (share links)
  ///   • `https://<host>/p/<id>`         — Universal / App Link
  ///   • `https://<host>/prod/p/<id>`    — same, with the API-Gateway stage
  /// For the https forms the id is the path segment immediately after a `p`
  /// segment, so any stage/locale prefix before `p` (e.g. `/prod`) is tolerated.
  static String? propertyIdFrom(Uri uri) {
    // Custom scheme: rently://property/<id>  → host=property, first segment=id.
    if (uri.scheme == 'rently') {
      if (uri.host != 'property' || uri.pathSegments.isEmpty) return null;
      final id = uri.pathSegments.first.trim();
      return id.isEmpty ? null : id;
    }
    // Universal / App Link: https://<host>/[<stage>/]p/<id>.
    if (uri.scheme == 'https' || uri.scheme == 'http') {
      final segs = uri.pathSegments;
      final pIdx = segs.indexOf('p');
      if (pIdx == -1 || pIdx + 1 >= segs.length) return null;
      final id = segs[pIdx + 1].trim();
      return id.isEmpty ? null : id;
    }
    return null;
  }

  Future<void> _openProperty(String id) async {
    // On a cold start the navigator/provider may not exist yet — wait up to ~10s
    // for them, then resolve the listing from the loaded catalog OR fetch it by
    // id from the backend (so links to listings not in memory still open the
    // apartment), and push the detail page.
    for (var i = 0; i < 30; i++) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        try {
          // Safe: ctx is re-fetched fresh from the global key each iteration.
          // ignore: use_build_context_synchronously
          final provider = ctx.read<DatingProvider>();
          // Fast path: the listing is already in the loaded catalog (covers seed
          // listings, which exist ONLY in memory, and any already-fetched page).
          final local = provider.propertyById(id);
          if (local != null) {
            navigatorKey.currentState?.push(
              MaterialPageRoute(
                  builder: (_) => PropertyDetailScreen(property: local)),
            );
            return;
          }
          // Not in the catalog. Wait for the initial load to settle FIRST — on a
          // cold start the catalog fills ~1–2s after the link arrives, so giving
          // up now would drop valid links (the bug this replaced). Once settled,
          // fetch the listing directly from the backend by id (real shared links
          // to listings not in memory). Only when the catalog is done AND the
          // backend has nothing is the listing genuinely unknown/removed.
          if (!provider.isLoading) {
            final fetched = await provider.fetchPropertyById(id);
            if (fetched != null) {
              navigatorKey.currentState?.push(
                MaterialPageRoute(
                    builder: (_) => PropertyDetailScreen(property: fetched)),
              );
            }
            return;
          }
          // still loading → fall through and retry after the delay
        } catch (_) {
          // Provider not wired into the tree yet (very early cold start) — retry.
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    // Navigator never came up (shouldn't happen) → leave on the home screen.
  }
}
