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

  void _handle(Uri uri) {
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
    // On a cold start the catalog may still be loading — wait up to ~10s for the
    // provider + the target listing, then push the detail page.
    for (var i = 0; i < 20; i++) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        // Safe: ctx is re-fetched fresh from the global key each iteration.
        // ignore: use_build_context_synchronously
        final provider = ctx.read<DatingProvider>();
        if (!provider.isLoading) {
          final p = provider.propertyById(id);
          if (p != null) {
            navigatorKey.currentState?.push(
              MaterialPageRoute(
                  builder: (_) => PropertyDetailScreen(property: p)),
            );
            return;
          }
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    // Not found (unknown/removed listing) → leave the user on the home screen.
  }
}
