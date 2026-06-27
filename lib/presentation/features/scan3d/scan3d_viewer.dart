import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dating_app/presentation/features/panorama/panorama_splat_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Unified in-app 3D viewer for an apartment scan. It renders, full-screen in a
/// WebView, EITHER:
///
///   • a **3D Gaussian-splat** (`.ply`/`.splat`/`.ksplat`) — when [splatUrl] is
///     given. This delegates to the existing [PanoramaSplatView]
///     (PlayCanvas/SuperSplat-style GaussianSplats3D viewer), so splats and the
///     mesh share one entry point but reuse the proven splat pipeline; OR
///
///   • a **textured-mesh GLB** — when only [meshGlbUrl] is given. The mesh is
///     rendered with orbit controls by Google's `<model-viewer>` web component
///     (BSD-3), vendored locally under `assets/web/scan3d/` so the viewer code
///     never hits the network at runtime (only the GLB asset itself streams).
///
/// Architecture mirrors [PanoramaSplatView] / [PanoramaPsvTourView]: a tiny
/// on-device loopback HTTP server serves the bundled HTML + viewer JS, so there
/// are no CORS / mixed-content issues. The (remote, HTTPS) GLB is handed to the
/// viewer by URL and streamed by the WebView directly.
///
/// When BOTH urls are supplied the splat wins (it is the richer walk-through);
/// pass only [meshGlbUrl] to force the mesh viewer.
class Scan3dViewerScreen extends StatefulWidget {
  const Scan3dViewerScreen({
    super.key,
    this.meshGlbUrl,
    this.splatUrl,
    this.title = 'סריקה תלת-מימדית',
  }) : assert(meshGlbUrl != null || splatUrl != null,
            'provide meshGlbUrl, splatUrl, or both');

  /// HTTPS URL of a textured-mesh GLB (`.glb`/`.gltf`).
  final String? meshGlbUrl;

  /// HTTPS URL of a Gaussian-splat (`.ply`/`.splat`/`.ksplat`).
  final String? splatUrl;

  final String title;

  /// Opens the unified viewer full-screen. Supply [meshGlbUrl] and/or
  /// [splatUrl]; if a [splatUrl] is given it is preferred.
  static Future<void> open(
    BuildContext context, {
    String? meshGlbUrl,
    String? splatUrl,
    String title = 'סריקה תלת-מימדית',
  }) {
    final splat = (splatUrl != null && splatUrl.isNotEmpty) ? splatUrl : null;
    final mesh = (meshGlbUrl != null && meshGlbUrl.isNotEmpty) ? meshGlbUrl : null;

    // Splat takes precedence → reuse the existing, proven splat viewer.
    if (splat != null) {
      return PanoramaSplatView.open(context, splat, title: title);
    }
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Scan3dViewerScreen(meshGlbUrl: mesh, title: title),
      ),
    );
  }

  @override
  State<Scan3dViewerScreen> createState() => _Scan3dViewerScreenState();
}

class _Scan3dViewerScreenState extends State<Scan3dViewerScreen> {
  HttpServer? _server;
  WebViewController? _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // Defensive: if a splatUrl somehow reaches the widget directly (not via
    // open()), the mesh path still needs a GLB. Otherwise we render the mesh.
    if ((widget.splatUrl != null && widget.splatUrl!.isNotEmpty) &&
        (widget.meshGlbUrl == null || widget.meshGlbUrl!.isEmpty)) {
      // Replace ourselves with the splat viewer post-frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => PanoramaSplatView(
            splatUrl: widget.splatUrl!,
            title: widget.title,
          ),
        ));
      });
      return;
    }
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final html = await _loadAsset('assets/web/scan3d/index.html');
      final mvJs = await _loadAsset('assets/web/scan3d/model-viewer.min.js');

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        try {
          final path = req.uri.path;
          if (path == '/' || path == '/index.html') {
            _send(req, 'text/html; charset=utf-8', _injectConfig(html));
          } else if (path == '/model-viewer.min.js') {
            _send(req, 'application/javascript', mvJs);
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

  /// The HTML reads `window.RENTLY_SCAN3D` for its config; we inject it just
  /// before the closing `</head>` so the vendored viewer needs no edits.
  List<int> _injectConfig(Uint8List htmlBytes) {
    final html = utf8.decode(htmlBytes);
    final config = jsonEncode({'meshGlbUrl': widget.meshGlbUrl ?? ''});
    final injected = html.replaceFirst(
      '</head>',
      '<script>window.RENTLY_SCAN3D=$config;</script></head>',
    );
    return utf8.encode(injected);
  }

  static void _send(HttpRequest req, String contentType, List<int> body) {
    req.response.headers.set(HttpHeaders.contentTypeHeader, contentType);
    req.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    req.response.contentLength = body.length;
    req.response.add(body);
    req.response.close();
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
                    'לא ניתן לטעון את המודל התלת-מימדי במכשיר זה.',
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

  Widget _closeButton({bool inline = false}) {
    final btn = GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: const Icon(IconsaxPlusLinear.arrow_right_3,
            color: Colors.white, size: 24),
      ),
    );
    if (inline) return btn;
    return Positioned(top: 8, right: 12, child: SafeArea(child: btn));
  }
}
