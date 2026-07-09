import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/property_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Opens an incoming `rently://property/<id>` deep link straight at the apartment
/// page — for shared links (WhatsApp etc.) that route through the /p/:id web page,
/// which redirects into the app. Uses the app's global [navigatorKey] so it can
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
    if (uri.scheme != 'rently') return;
    // rently://property/<id>  → host=property, first path segment=id
    if (uri.host != 'property' || uri.pathSegments.isEmpty) return;
    final id = uri.pathSegments.first;
    if (id.isNotEmpty) _openProperty(id);
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
