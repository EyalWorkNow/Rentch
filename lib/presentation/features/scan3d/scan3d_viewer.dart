import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dating_app/data/models/scanned_room.dart';
import 'package:dating_app/presentation/features/panorama/panorama_splat_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Unified in-app 3D viewer for an apartment scan.
///
/// Two entry points:
///   • [Scan3dViewerScreen.open]      — a single scan (mesh and/or splat).
///   • [Scan3dViewerScreen.openRooms] — a whole apartment captured room-by-room
///     ([ScannedRoom] list). Shows a persistent bottom **room-picker** bar; tap
///     a room to swap into it. This is the "Option 1" lazy room-switcher: not a
///     seamless walk-through, but a fast menu to jump between rooms.
///
/// Each room renders EITHER:
///   • a **3D Gaussian-splat** (`.ply`/`.splat`/`.ksplat`) — delegated to the
///     proven [PanoramaSplatView] (embedded, chrome suppressed); OR
///   • a **textured-mesh GLB** — rendered by Google's `<model-viewer>` (BSD-3),
///     vendored under `assets/web/scan3d/`.
///
/// Room switching is handled by giving the active room's viewer a per-index
/// [Key]: changing the selected index tears down the previous viewer (closing
/// its WebView + loopback HTTP server via normal widget disposal) and builds a
/// fresh one for the new room — so only one splat/mesh is ever in memory.
class Scan3dViewerScreen extends StatefulWidget {
  const Scan3dViewerScreen({
    super.key,
    required this.rooms,
    this.initialIndex = 0,
    this.title = 'סריקה תלת-מימדית',
  }) : assert(rooms.length > 0, 'provide at least one room');

  /// The viewable rooms, in display order. For a single scan this is a
  /// one-element list synthesized by [open].
  final List<ScannedRoom> rooms;

  /// Which room to show first (clamped to range).
  final int initialIndex;

  final String title;

  /// Opens the viewer for a SINGLE scan. Supply [meshGlbUrl] and/or [splatUrl];
  /// a splat is preferred when both are present.
  static Future<void> open(
    BuildContext context, {
    String? meshGlbUrl,
    String? splatUrl,
    String title = 'סריקה תלת-מימדית',
  }) {
    final mesh = (meshGlbUrl != null && meshGlbUrl.isNotEmpty) ? meshGlbUrl : null;
    final splat = (splatUrl != null && splatUrl.isNotEmpty) ? splatUrl : null;
    if (mesh == null && splat == null) return Future.value();
    return openRooms(
      context,
      [ScannedRoom(name: title, meshGlbUrl: mesh, splatUrl: splat)],
      title: title,
    );
  }

  /// Opens the multi-room viewer. Non-viewable rooms (e.g. a RoomPlan capture
  /// with only a local USDZ path) are filtered out. No-ops if nothing is
  /// viewable.
  static Future<void> openRooms(
    BuildContext context,
    List<ScannedRoom> rooms, {
    int initialIndex = 0,
    String title = 'סריקה תלת-מימדית',
  }) {
    final viewable = rooms.where((r) => r.hasViewableAsset).toList();
    if (viewable.isEmpty) return Future.value();
    final start = initialIndex.clamp(0, viewable.length - 1);
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Scan3dViewerScreen(
          rooms: viewable,
          initialIndex: start,
          title: title,
        ),
      ),
    );
  }

  @override
  State<Scan3dViewerScreen> createState() => _Scan3dViewerScreenState();
}

class _Scan3dViewerScreenState extends State<Scan3dViewerScreen> {
  late int _index = widget.initialIndex.clamp(0, widget.rooms.length - 1);

  ScannedRoom get _room => widget.rooms[_index];
  bool get _hasPicker => widget.rooms.length > 1;

  void _select(int i) {
    if (i == _index || i < 0 || i >= widget.rooms.length) return;
    // setState with a new active index rebuilds the keyed viewer subtree, which
    // disposes the previous room's WebView + loopback server and loads the new.
    setState(() => _index = i);
  }

  /// The renderer for the current room. Keyed by index so switching rooms
  /// rebuilds it from scratch (unload old → load new).
  Widget _viewerFor(ScannedRoom room) {
    final splat = room.splatUrl?.trim() ?? '';
    if (splat.isNotEmpty) {
      // Reuse the proven splat pipeline, chrome suppressed (host owns chrome).
      return PanoramaSplatView(
        key: ValueKey('room-$_index-splat'),
        splatUrl: splat,
        title: room.name,
        showChrome: false,
      );
    }
    final mesh = room.meshGlbUrl?.trim() ?? '';
    if (mesh.isNotEmpty) {
      return _MeshView(key: ValueKey('room-$_index-mesh'), meshGlbUrl: mesh);
    }
    return const _ViewerMessage(
      'לא ניתן לטעון את המודל התלת-מימדי של חדר זה.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final roomTitle = _room.name.trim().isNotEmpty ? _room.name : widget.title;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Active room viewer (keyed → clean unload/load on switch).
            Positioned.fill(child: _viewerFor(_room)),

            // Top bar: close + current room title.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      _closeButton(),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          roomTitle,
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

            // Persistent room-picker bar (only when there's more than one room).
            if (_hasPicker)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _RoomPickerBar(
                  rooms: widget.rooms,
                  selected: _index,
                  onSelect: _select,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _closeButton() => GestureDetector(
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
}

// ════════════════════════════════════════════════════════════════════════════
// ROOM-PICKER BAR — persistent bottom chips to swap rooms
// ════════════════════════════════════════════════════════════════════════════

class _RoomPickerBar extends StatelessWidget {
  const _RoomPickerBar({
    required this.rooms,
    required this.selected,
    required this.onSelect,
  });

  final List<ScannedRoom> rooms;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < rooms.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _RoomChip(
                    label: rooms[i].name.trim().isNotEmpty
                        ? rooms[i].name
                        : 'חדר ${i + 1}',
                    selected: i == selected,
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomChip extends StatelessWidget {
  const _RoomChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// MESH VIEW — `<model-viewer>` GLB renderer in a self-hosted WebView
// ════════════════════════════════════════════════════════════════════════════
//
// Extracted so the host can compose it (or [PanoramaSplatView]) per room. Owns
// its own loopback HTTP server + WebView, and disposes both on teardown — which
// is what makes room-switching leak-free (a new [Key] → old _MeshView disposed).

class _MeshView extends StatefulWidget {
  const _MeshView({super.key, required this.meshGlbUrl});

  final String meshGlbUrl;

  @override
  State<_MeshView> createState() => _MeshViewState();
}

class _MeshViewState extends State<_MeshView> {
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
    final config = jsonEncode({'meshGlbUrl': widget.meshGlbUrl});
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
      return const _ViewerMessage(
        'לא ניתן לטעון את המודל התלת-מימדי במכשיר זה.',
      );
    }
    if (_ready && _controller != null) {
      return WebViewWidget(controller: _controller!);
    }
    return const Center(child: CircularProgressIndicator(color: Colors.white));
  }
}

/// Simple centered white message on the black viewer backdrop.
class _ViewerMessage extends StatelessWidget {
  const _ViewerMessage(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
    );
  }
}
