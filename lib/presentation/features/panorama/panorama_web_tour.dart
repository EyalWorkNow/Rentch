import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dating_app/data/models/panorama_tour.dart';
import 'package:dating_app/presentation/features/panorama/panorama_experience_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Google-Street-View-style multi-node tour, powered by Pannellum (MIT) inside a
/// WebView. Pannellum handles the sphere render, look-around, gyro, compass, and
/// the scene-to-scene fade transition with heading continuity — a battle-tested
/// viewer instead of a hand-rolled one.
///
/// Everything is served from a tiny on-device HTTP server (HTML + the bundled
/// Pannellum lib + the panorama images), so there are no CORS/mixed-content
/// issues and it works offline. If anything fails to set up, it falls back to the
/// native [PanoramaExperienceView] so the user always sees a tour.
class PanoramaWebTourView extends StatefulWidget {
  const PanoramaWebTourView({
    super.key,
    required this.tour,
    this.title = 'סיור 360°',
  });

  final PropertyPanoramaTour tour;
  final String title;

  static Future<void> open(
    BuildContext context,
    PropertyPanoramaTour tour, {
    String title = 'סיור 360°',
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PanoramaWebTourView(tour: tour, title: title),
      ),
    );
  }

  @override
  State<PanoramaWebTourView> createState() => _PanoramaWebTourViewState();
}

class _PanoramaWebTourViewState extends State<PanoramaWebTourView> {
  HttpServer? _server;
  WebViewController? _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      // 1. bundled Pannellum lib
      final js = (await rootBundle.load('assets/web/pannellum/pannellum.js'))
          .buffer
          .asUint8List();
      final css = (await rootBundle.load('assets/web/pannellum/pannellum.css'))
          .buffer
          .asUint8List();

      // 2. panorama images (network → download, local → read) into memory
      final images = <String, Uint8List>{};
      for (final n in widget.tour.nodes) {
        final bytes = await _loadImage(n);
        if (bytes != null) images[n.id] = bytes;
      }
      if (images.isEmpty) throw StateError('no panorama images');

      // 3. the tour HTML
      final html = _buildHtml(widget.tour, images.keys.toSet());

      // 4. local HTTP server (loopback, random port)
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final path = req.uri.path;
        try {
          if (path == '/' || path == '/index.html') {
            _send(req, 'text/html; charset=utf-8', utf8.encode(html));
          } else if (path == '/pannellum.js') {
            _send(req, 'application/javascript', js);
          } else if (path == '/pannellum.css') {
            _send(req, 'text/css', css);
          } else if (path.startsWith('/img/')) {
            final id = Uri.decodeComponent(path.substring(5));
            final bytes = images[id];
            if (bytes != null) {
              _send(req, 'image/jpeg', bytes);
            } else {
              req.response.statusCode = 404;
              await req.response.close();
            }
          } else {
            req.response.statusCode = 404;
            await req.response.close();
          }
        } catch (_) {
          try {
            req.response.statusCode = 500;
            await req.response.close();
          } catch (_) {}
        }
      });
      _server = server;

      final url = 'http://127.0.0.1:${server.port}/';
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.black)
        ..loadRequest(Uri.parse(url));

      if (!mounted) {
        await server.close(force: true);
        return;
      }
      setState(() {
        _controller = controller;
        _ready = true;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<Uint8List?> _loadImage(PanoramaNode n) async {
    try {
      if (n.isLocal) {
        final p =
            n.imageUrl.startsWith('file://') ? n.imageUrl.substring(7) : n.imageUrl;
        return await File(p).readAsBytes();
      }
      final res =
          await http.get(Uri.parse(n.imageUrl)).timeout(const Duration(seconds: 25));
      if (res.statusCode >= 200 && res.statusCode < 300) return res.bodyBytes;
    } catch (_) {}
    return null;
  }

  static void _send(HttpRequest req, String contentType, List<int> body) {
    req.response.headers.set(HttpHeaders.contentTypeHeader, contentType);
    req.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    req.response.add(body);
    req.response.close();
  }

  String _buildHtml(PropertyPanoramaTour tour, Set<String> available) {
    final config = pannellumTourConfig(
      tour,
      imageUrlFor: (id) => '/img/${Uri.encodeComponent(id)}',
      available: available,
    );
    final json = jsonEncode(config);

    // Custom arrow styling for the link hotspots (Street-View feel).
    return '''<!DOCTYPE html>
<html lang="he" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<link rel="stylesheet" href="/pannellum.css">
<script src="/pannellum.js"></script>
<style>
  html,body{margin:0;height:100%;background:#000;overflow:hidden}
  #pano{width:100%;height:100%}
  .sv-arrow{
    width:54px;height:54px;border-radius:50%;
    background:rgba(255,255,255,0.92);
    box-shadow:0 3px 10px rgba(0,0,0,.45);
    cursor:pointer;transition:transform .15s;
    background-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='30' height='30' viewBox='0 0 24 24' fill='none' stroke='%2300A6A6' stroke-width='3' stroke-linecap='round' stroke-linejoin='round'><polyline points='5 12 12 5 19 12'/><line x1='12' y1='19' x2='12' y2='5'/></svg>");
    background-repeat:no-repeat;background-position:center;
  }
  .sv-arrow:hover{transform:scale(1.12)}
  .pnlm-compass{bottom:auto;top:14px;left:14px}
</style>
</head>
<body>
<div id="pano"></div>
<script>
  try {
    pannellum.viewer('pano', $json);
  } catch (e) { document.body.innerHTML = '<div style="color:#fff;padding:24px">'+e+'</div>'; }
</script>
</body>
</html>''';
  }

  @override
  void dispose() {
    _server?.close(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // graceful fallback to the native viewer if the web tour couldn't start
    if (_failed) {
      return PanoramaExperienceView(tour: widget.tour, title: widget.title);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_ready && _controller != null)
            WebViewWidget(controller: _controller!)
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          // close + title
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(IconsaxPlusLinear.arrow_right_3,
                            color: Colors.white, size: 20),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── pure, testable tour-config builder ───────────────────────────────────────

/// Heading continuity: when walking from [fromId] into [target], arrive facing
/// away from the link that points back (i.e. facing "forward"). Returns yaw in
/// degrees (-180..180), or 0 when geometry is unknown.
double pannellumArrivalYaw(PropertyPanoramaTour tour, PanoramaNode target,
    String fromId) {
  for (final h in target.hotspots) {
    if (h.targetNodeId == fromId) {
      var y = (h.longitude + 180) % 360;
      if (y > 180) y -= 360;
      return y;
    }
  }
  return 0;
}

/// Builds the Pannellum tour config (multi-scene, link hotspots, heading
/// continuity) from a [PropertyPanoramaTour]. [imageUrlFor] maps a node id to
/// the URL the viewer should load the panorama from. [available] optionally
/// restricts to the nodes whose images actually loaded.
Map<String, dynamic> pannellumTourConfig(
  PropertyPanoramaTour tour, {
  required String Function(String nodeId) imageUrlFor,
  Set<String>? available,
}) {
  bool ok(String id) => available == null || available.contains(id);

  final scenes = <String, dynamic>{};
  for (final n in tour.nodes) {
    if (!ok(n.id)) continue;
    final hotSpots = <Map<String, dynamic>>[];
    for (final h in n.hotspots) {
      final target = tour.nodeById(h.targetNodeId);
      if (target == null || !ok(target.id)) continue;
      hotSpots.add({
        'pitch': h.latitude,
        'yaw': h.longitude,
        'type': 'scene',
        'text': h.label.isNotEmpty ? h.label : target.label,
        'sceneId': target.id,
        'targetYaw': pannellumArrivalYaw(tour, target, n.id),
        'cssClass': 'sv-arrow',
      });
    }
    scenes[n.id] = {
      'title': n.label,
      'type': 'equirectangular',
      'panorama': imageUrlFor(n.id),
      'hotSpots': hotSpots,
    };
  }

  final first = tour.nodes.firstWhere((n) => ok(n.id),
      orElse: () => tour.nodes.first);
  return {
    'default': {
      'firstScene': first.id,
      'sceneFadeDuration': 1000,
      'autoLoad': true,
      'compass': true,
      'showZoomCtrl': true,
      'keyboardZoom': false,
      'mouseZoom': true,
      'hfov': 100,
    },
    'scenes': scenes,
  };
}
