import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Walkable 3D-Gaussian-Splat viewer (Phase 2 MVP, per
/// RENTLY_SPATIAL_ARCHITECTURE.md §4.2). Renders a `.spz`/`.ply` splat produced
/// by [LumaSplatService] inside a self-hosted MIT splat viewer
/// (mkkellogg/GaussianSplats3D) running in a WebView.
///
/// Navigation is **teleport-waypoint** (Matterport-style): the user steps
/// between a few preset camera poses with smooth transitions — there is NO
/// collision system and NO free-fly, so the camera never wanders into capture
/// voids or through walls (the doc's "Tier-0/1 navigation").
///
/// Architecture mirrors [PanoramaWebTourView]: a tiny on-device loopback HTTP
/// server serves the bundled HTML + viewer JS (assets/web/splat/), so there are
/// no CORS/mixed-content issues. The (remote, HTTPS) splat asset itself is
/// passed to the viewer by URL and streamed by the WebView directly.
class PanoramaSplatView extends StatefulWidget {
  const PanoramaSplatView({
    super.key,
    required this.splatUrl,
    this.title = 'סיור תלת-מימד',
    this.waypoints = const [],
    this.showChrome = true,
  });

  /// HTTPS URL of the reconstructed splat (`.spz` preferred, `.ply` ok).
  final String splatUrl;
  final String title;

  /// When false, hides this view's own top bar (close/title) and the teleport
  /// waypoint controls — used when embedded inside a host that owns the chrome
  /// (e.g. the multi-room [Scan3dViewerScreen] room-switcher).
  /// ponytail: embedded mode drops in-room teleport nav; drag/orbit still works.
  /// Add per-room waypoints back when a room actually needs preset poses.
  final bool showChrome;

  /// Optional preset camera poses to teleport between. When empty, the viewer
  /// uses a sensible default orbit set so the scene is still navigable.
  final List<SplatWaypoint> waypoints;

  static Future<void> open(
    BuildContext context,
    String splatUrl, {
    String title = 'סיור תלת-מימד',
    List<SplatWaypoint> waypoints = const [],
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PanoramaSplatView(
          splatUrl: splatUrl,
          title: title,
          waypoints: waypoints,
        ),
      ),
    );
  }

  @override
  State<PanoramaSplatView> createState() => _PanoramaSplatViewState();
}

class _PanoramaSplatViewState extends State<PanoramaSplatView> {
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
      // Bundled viewer assets: HTML shell + vendored MIT GaussianSplats3D bundle
      // + its three.js peer (both ESM, wired via an import map in the HTML).
      final html = await _loadAsset('assets/web/splat/index.html');
      final viewerJs = await _loadAsset('assets/web/splat/gaussian-splats-3d.js');
      final threeJs = await _loadAsset('assets/web/splat/three.module.js');

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        try {
          final path = req.uri.path;
          if (path == '/' || path == '/index.html') {
            _send(req, 'text/html; charset=utf-8', _injectConfig(html));
          } else if (path == '/gaussian-splats-3d.js') {
            _send(req, 'application/javascript', viewerJs);
          } else if (path == '/three.module.js') {
            _send(req, 'application/javascript', threeJs);
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

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.black)
        ..setNavigationDelegate(NavigationDelegate(
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? true) {
              if (mounted) setState(() => _failed = true);
            }
          },
        ))
        ..setOnConsoleMessage(
            (m) => debugPrint('SPLAT-JS: ${m.message}'))
        ..loadRequest(Uri.parse('http://127.0.0.1:${server.port}/'));

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

  Future<Uint8List> _loadAsset(String key) async =>
      (await rootBundle.load(key)).buffer.asUint8List();

  /// The HTML reads `window.RENTLY_SPLAT` for its config; we inject it just
  /// before the closing `</head>` so the bundled viewer needs no edits.
  List<int> _injectConfig(Uint8List htmlBytes) {
    final html = utf8.decode(htmlBytes);
    final config = jsonEncode({
      'splatUrl': widget.splatUrl,
      'waypoints': _effectiveWaypoints.map((w) => w.toJson()).toList(),
      // Android's System-WebView WebGL is far slower/variable than iOS WKWebView,
      // so render at a lower pixel ratio there (fewer fragments = smoother walk);
      // iOS keeps the sharper cap.
      'dprCap': Platform.isAndroid ? 1.2 : 1.5,
    });
    final injected = html.replaceFirst(
      '</head>',
      '<script>window.RENTLY_SPLAT=$config;</script></head>',
    );
    return utf8.encode(injected);
  }

  List<SplatWaypoint> get _effectiveWaypoints =>
      widget.waypoints.isNotEmpty ? widget.waypoints : SplatWaypoint.defaults;

  static void _send(HttpRequest req, String contentType, List<int> body) {
    req.response.headers.set(HttpHeaders.contentTypeHeader, contentType);
    req.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    req.response.contentLength = body.length;
    req.response.add(body);
    req.response.close();
  }

  void _step(int delta) {
    _controller?.runJavaScript('window.rentlyStep && window.rentlyStep($delta);');
  }

  @override
  void dispose() {
    _server?.close(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'לא ניתן לטעון את הסיור התלת-מימדי במכשיר זה.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
              _closeButton(),
            ],
          ),
        ),
      );
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

          // top bar: close + title
          if (widget.showChrome)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      _closeButton(inline: true),
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
                            shadows: [
                              Shadow(color: Colors.black54, blurRadius: 6)
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // teleport-waypoint controls (forward / back between preset poses)
          if (_ready && widget.showChrome)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _navButton(
                        icon: IconsaxPlusLinear.arrow_right_3,
                        label: 'אחורה',
                        onTap: () => _step(-1),
                      ),
                      const SizedBox(width: 16),
                      _navButton(
                        icon: IconsaxPlusLinear.arrow_left_2,
                        label: 'קדימה',
                        onTap: () => _step(1),
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

  Widget _closeButton({bool inline = false}) {
    final btn = GestureDetector(
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
    );
    if (inline) return btn;
    return Positioned(top: 8, right: 12, child: SafeArea(child: btn));
  }

  Widget _navButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A preset camera pose the viewer can teleport to. Position + look-at target
/// in the splat's world space (metres). Kept tiny and JSON-serialisable so it
/// crosses into the WebView verbatim.
@immutable
class SplatWaypoint {
  const SplatWaypoint({
    required this.label,
    required this.position,
    required this.target,
  });

  /// e.g. "סלון", "מטבח".
  final String label;

  /// Camera position [x, y, z].
  final List<double> position;

  /// Look-at point [x, y, z].
  final List<double> target;

  Map<String, dynamic> toJson() => {
        'label': label,
        'position': position,
        'target': target,
      };

  /// A small default orbit used when no authored waypoints exist, so the scene
  /// is still navigable. Real waypoints come from the capture's pose track.
  static const List<SplatWaypoint> defaults = [
    SplatWaypoint(
      label: 'כניסה',
      position: [0, 1.5, 3],
      target: [0, 1.2, 0],
    ),
    SplatWaypoint(
      label: 'מרכז',
      position: [0, 1.5, 0.5],
      target: [0, 1.2, -2],
    ),
    SplatWaypoint(
      label: 'פנים',
      position: [1.5, 1.5, -2],
      target: [0, 1.2, -3],
    ),
  ];
}
