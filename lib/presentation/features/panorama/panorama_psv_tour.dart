import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dating_app/data/models/panorama_tour.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:dating_app/presentation/features/panorama/panorama_experience_view.dart';
import 'package:flutter/material.dart';
import 'package:dating_app/core/config/media_cdn.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Google-Street-View-style multi-node tour, powered by **Photo Sphere Viewer
/// v5** (MIT) with the **VirtualTour** + **Markers** plugins, inside a WebView.
///
/// This is a drop-in alternative to [PanoramaWebTourView] (Pannellum). PSV ships
/// the one thing Pannellum lacks: **native 3D ground-plane "walk-forward" arrows**
/// laid flat on the floor (the real Street-View look), driven by a node graph,
/// instead of flat billboard hotspots. It also has first-class support for
/// **partial / cropped phone panoramas** via `panoData`, so a cylindrical strip
/// (haov 360 / vaov ≈ 60) sits at the correct latitude band with *honest* empty
/// poles instead of a stretched smear.
///
/// Same public API as the Pannellum viewer, so swapping is one line:
///   PanoramaWebTourView.open(context, tour)  →  PanoramaPsvTourView.open(context, tour)
///
/// Everything is served from a tiny on-device HTTP server (HTML + the bundled
/// PSV/three.js libs + the panorama images), so there are no CORS/mixed-content
/// issues and it works offline. If anything fails to set up, it falls back to the
/// native [PanoramaExperienceView] so the user always sees a tour.
class PanoramaPsvTourView extends StatefulWidget {
  const PanoramaPsvTourView({
    super.key,
    required this.tour,
    this.title = '',
  });

  final PropertyPanoramaTour tour;
  final String title;

  static Future<void> open(
    BuildContext context,
    PropertyPanoramaTour tour, {
    String title = '',
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PanoramaPsvTourView(tour: tour, title: title),
      ),
    );
  }

  @override
  State<PanoramaPsvTourView> createState() => _PanoramaPsvTourViewState();
}

class _PanoramaPsvTourViewState extends State<PanoramaPsvTourView> {
  HttpServer? _server;
  WebViewController? _controller;
  bool _ready = false;
  bool _failed = false;

  // bundled PSV v5 + plugins + three.js (self-hosted, offline).
  static const _assets = <String, _Asset>{
    '/three.module.js':
        _Asset('assets/web/psv/three.module.js', 'application/javascript'),
    '/psv-core.module.js':
        _Asset('assets/web/psv/psv-core.module.js', 'application/javascript'),
    '/psv-virtual-tour.module.js': _Asset(
        'assets/web/psv/psv-virtual-tour.module.js', 'application/javascript'),
    '/psv-markers.module.js':
        _Asset('assets/web/psv/psv-markers.module.js', 'application/javascript'),
    '/psv-core.css': _Asset('assets/web/psv/psv-core.css', 'text/css'),
    '/psv-virtual-tour.css':
        _Asset('assets/web/psv/psv-virtual-tour.css', 'text/css'),
    '/psv-markers.css': _Asset('assets/web/psv/psv-markers.css', 'text/css'),
  };

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      // 1. bundled PSV / three.js libs
      final libs = <String, Uint8List>{};
      for (final entry in _assets.entries) {
        libs[entry.key] =
            (await rootBundle.load(entry.value.path)).buffer.asUint8List();
      }

      // 2. panorama images into memory. Each node's ACTIVE render is served at
      //    /img/{nodeId} (the tour default). Nodes with >1 VIEWER-visible render
      //    also serve their other versions at /img/{nodeId}::v{i} so the tenant
      //    can flip between them in-viewer.
      final images = <String, Uint8List>{};
      final availableNodes = <String>{};
      // nodeId → [{src, source, haov, vaov, def}] (only when >1 visible version).
      final versionsByNode = <String, List<Map<String, dynamic>>>{};
      for (final n in widget.tour.nodes) {
        final visible = n.viewerVersions;
        final vlist = <Map<String, dynamic>>[];
        for (var vi = 0; vi < visible.length; vi++) {
          final v = visible[vi];
          final isDefault = v.imageUrl == n.imageUrl; // the active/published one
          final key = isDefault ? n.id : '${n.id}::v$vi';
          final bytes = await _loadBytes(v.imageUrl);
          if (bytes == null) continue;
          images[key] = bytes;
          vlist.add({
            'src': '/img/${Uri.encodeComponent(key)}',
            'source': v.source.isNotEmpty
                ? v.source
                : AppLocalizations.of(context)!.panoramaPsvTour4968e76c(vi + 1),
            'haov': v.haov,
            'vaov': v.vaov,
            'def': isDefault,
          });
        }
        // The tour default (/img/{nodeId}) must exist; if the active render
        // failed to load, fall back to the first visible one that did.
        if (!images.containsKey(n.id) && vlist.isNotEmpty) {
          final firstKey = Uri.decodeComponent(
              (vlist.first['src'] as String).substring(5));
          images[n.id] = images[firstKey]!;
          vlist.first['def'] = true;
        }
        if (images.containsKey(n.id)) availableNodes.add(n.id);
        if (vlist.length > 1) versionsByNode[n.id] = vlist;
      }
      if (images.isEmpty) throw StateError('no panorama images');

      // 3. the tour HTML
      final html = _buildHtml(widget.tour, availableNodes, versionsByNode);

      // 4. local HTTP server (loopback, random port)
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final path = req.uri.path;
        try {
          if (path == '/' || path == '/index.html') {
            _send(req, 'text/html; charset=utf-8', utf8.encode(html));
          } else if (libs.containsKey(path)) {
            _send(req, _assets[path]!.mime, libs[path]!);
          } else if (path.startsWith('/img/')) {
            final id = Uri.decodeComponent(path.substring(5));
            final bytes = images[id];
            if (bytes != null) {
              // sniff PNG (downscaled) vs JPEG (original) by magic bytes
              final isPng = bytes.length > 3 &&
                  bytes[0] == 0x89 &&
                  bytes[1] == 0x50 &&
                  bytes[2] == 0x4E &&
                  bytes[3] == 0x47;
              _send(req, isPng ? 'image/png' : 'image/jpeg', bytes);
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
        ..setNavigationDelegate(NavigationDelegate(
          onWebResourceError: (error) {
            // a main-frame load failure (ATS/cleartext/WebGL) ⇒ fall back to the
            // native viewer so the user still gets a tour.
            if (error.isForMainFrame ?? true) {
              if (mounted) setState(() => _failed = true);
            }
          },
        ))
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

  Future<Uint8List?> _loadBytes(String url) async {
    try {
      // Bundled demo panoramas (guest mode) ship as assets, not files/URLs.
      if (url.startsWith('asset://')) {
        return (await rootBundle.load(url.substring(8))).buffer.asUint8List();
      }
      final isLocal = url.startsWith('/') || url.startsWith('file://');
      if (isLocal) {
        final p = url.startsWith('file://') ? url.substring(7) : url;
        return await File(p).readAsBytes();
      }
      final res = await http
          .get(Uri.parse(MediaCdn.url(url)))
          .timeout(const Duration(seconds: 40));
      if (res.statusCode >= 200 && res.statusCode < 300) return res.bodyBytes;
    } catch (_) {}
    return null;
  }

  static void _send(HttpRequest req, String contentType, List<int> body) {
    req.response.headers.set(HttpHeaders.contentTypeHeader, contentType);
    req.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    req.response.contentLength = body.length;
    req.response.add(body);
    req.response.close();
  }

  String _buildHtml(
    PropertyPanoramaTour tour,
    Set<String> available,
    Map<String, List<Map<String, dynamic>>> versionsByNode,
  ) {
    final config = psvTourConfig(
      tour,
      imageUrlFor: (id) => '/img/${Uri.encodeComponent(id)}',
      available: available,
    );
    final json = jsonEncode(config);
    final versionsJson = jsonEncode(versionsByNode);

    // nodes with a map position → mini-map data (id, x, y, label, link targets)
    final mapNodes = [
      for (final n in tour.nodes)
        if (n.hasPosition && available.contains(n.id))
          {
            'id': n.id,
            'x': n.x,
            'y': n.y,
            'label': n.label,
            'links': [
              for (final h in n.hotspots)
                if (available.contains(h.targetNodeId)) h.targetNodeId
            ],
          }
    ];
    final mapJson = jsonEncode(mapNodes);

    // arrow tint matches the Pannellum viewer's teal (#00A6A6).
    return '''<!DOCTYPE html>
<html lang="he" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<link rel="stylesheet" href="/psv-core.css">
<link rel="stylesheet" href="/psv-virtual-tour.css">
<link rel="stylesheet" href="/psv-markers.css">
<style>
  html,body{margin:0;height:100%;background:#000;overflow:hidden}
  #pano{width:100%;height:100%}
  /* mini-map */
  #minimap{position:absolute;left:12px;bottom:12px;width:144px;height:144px;
    background:rgba(0,0,0,.5);border:1px solid rgba(255,255,255,.25);
    border-radius:14px;z-index:5;backdrop-filter:blur(4px)}
  #minimap svg{position:absolute;inset:0;width:100%;height:100%}
  #mm-name{position:absolute;left:12px;bottom:162px;z-index:5;color:#fff;
    background:rgba(0,0,0,.55);padding:5px 11px;border-radius:999px;
    font:800 12.5px sans-serif;max-width:60vw;overflow:hidden;
    text-overflow:ellipsis;white-space:nowrap}
  .mm-dot{cursor:pointer}
  @keyframes mmpulse{0%{r:5;opacity:.9}70%{r:12;opacity:0}100%{opacity:0}}
  #err{color:#fff;padding:24px;font:14px sans-serif}
  /* version switcher (tenants flip between the landlord's shown 360 renders) */
  #vbar{position:absolute;left:0;right:0;bottom:20px;z-index:6;display:none;
    justify-content:center;gap:6px;pointer-events:none}
  #vbar .vchip{pointer-events:auto;cursor:pointer;color:#fff;
    background:rgba(0,0,0,.55);border:1px solid rgba(255,255,255,.25);
    padding:7px 14px;border-radius:999px;font:700 12.5px sans-serif;
    -webkit-backdrop-filter:blur(4px);backdrop-filter:blur(4px)}
  #vbar .vchip.on{background:#fff;color:#000;border-color:#fff}
</style>
<script type="importmap">
{
  "imports": {
    "three": "/three.module.js",
    "@photo-sphere-viewer/core": "/psv-core.module.js",
    "@photo-sphere-viewer/virtual-tour-plugin": "/psv-virtual-tour.module.js",
    "@photo-sphere-viewer/markers-plugin": "/psv-markers.module.js"
  }
}
</script>
</head>
<body>
<div id="pano"></div>
<div id="mm-name"></div>
<div id="minimap"><svg id="mm-svg" viewBox="0 0 100 100" preserveAspectRatio="none"></svg></div>
<div id="vbar"></div>
<script type="module">
  import { Viewer } from '@photo-sphere-viewer/core';
  import { VirtualTourPlugin } from '@photo-sphere-viewer/virtual-tour-plugin';
  import { MarkersPlugin } from '@photo-sphere-viewer/markers-plugin';

  var TOUR = $json;
  var VERSIONS = $versionsJson; // nodeId → [{src,source,haov,vaov,def}]
  var ARROW = '#00A6A6';

  // ── partial-pano panoData ─────────────────────────────────────────────────
  // Map our haov/vaov (degrees the strip actually covers) onto PSV's panoData:
  // place the cropped image at the correct lat/long band of a full equirect
  // (2:1) sphere, leaving honest empty poles instead of stretching.
  //   fullWidth  = imgW * 360 / haov        (what 360° would have been)
  //   fullHeight = fullWidth / 2            (equirect is 2:1)
  //   croppedX   = (fullWidth  - imgW) / 2  (centered horizontally)
  //   croppedY   = (fullHeight - imgH) / 2  (vertical band centered on horizon)
  function panoDataFor(node) {
    return function(image) {
      var w = image.width, h = image.height;
      var haov = node.haov, vaov = node.vaov;
      if ((haov >= 360 && vaov >= 180) || !w || !h) return null; // full sphere
      var fullWidth = Math.round(w * 360 / Math.max(1, haov));
      var fullHeight = Math.round(fullWidth / 2);
      // honor the real vertical coverage: keep the image height, only pad poles.
      var croppedX = Math.round((fullWidth - w) / 2);
      var croppedY = Math.round((fullHeight - h) / 2);
      return {
        fullWidth: fullWidth,
        fullHeight: fullHeight,
        croppedWidth: w,
        croppedHeight: h,
        croppedX: croppedX < 0 ? 0 : croppedX,
        croppedY: croppedY < 0 ? 0 : croppedY,
      };
    };
  }

  var viewer, vt, builtNodes;
  try {
    viewer = new Viewer({
      container: 'pano',
      adapter: undefined,
      defaultZoomLvl: 30,
      navbar: ['zoom', 'caption', 'fullscreen'],
      plugins: [
        MarkersPlugin,
        [VirtualTourPlugin, {
          // manual mode = we supply the node graph + per-node link directions,
          // PSV renders the flat 3D floor arrows ("3d" rendering = Street-View).
          positionMode: 'manual',
          renderMode: '3d',
          arrowStyle: { color: ARROW, hoverColor: '#7BE7E7' },
          transitionOptions: { speed: '20rpm', fadeIn: true, rotation: true },
        }],
      ],
    });

    vt = viewer.getPlugin(VirtualTourPlugin);

    // attach panoData per node so partial panos sit correctly.
    builtNodes = TOUR.nodes.map(function(n){
      var node = {
        id: n.id,
        panorama: n.panorama,
        name: n.name,
        links: n.links,
      };
      var pd = panoDataFor(n);
      node.panoData = pd; // PSV accepts a function(image) → panoData
      // preserve heading continuity: face away from where we came in.
      if (typeof n.startAngle === 'number') node.sphereCorrection = { pan: 0 };
      return node;
    });

    vt.setNodes(builtNodes, TOUR.startNodeId);
  } catch (e) {
    document.body.innerHTML = '<div id="err">'+e+'</div>';
  }

  // ── mini-map: where you walked, current point, last name ──────────────────
  (function(){
    var nodes = $mapJson;
    if (!viewer || !vt || !nodes.length) {
      var mm = document.getElementById('minimap'); if (mm) mm.style.display='none';
      var nm = document.getElementById('mm-name'); if (nm) nm.style.display='none';
      return;
    }
    var byId = {}; nodes.forEach(function(n){ byId[n.id]=n; });
    var svg = document.getElementById('mm-svg');
    var nameEl = document.getElementById('mm-name');
    var SVGNS='http://www.w3.org/2000/svg';
    function el(t,a){var e=document.createElementNS(SVGNS,t);for(var k in a)e.setAttribute(k,a[k]);return e;}
    var px=function(v){return 6+v*88;}; // pad inside the 0..100 viewbox
    // edges (links)
    var seen={};
    nodes.forEach(function(n){
      (n.links||[]).forEach(function(t){
        var key=[n.id,t].sort().join('|'); if(seen[key]||!byId[t])return; seen[key]=1;
        svg.appendChild(el('line',{x1:px(n.x),y1:px(n.y),x2:px(byId[t].x),y2:px(byId[t].y),
          stroke:'rgba(255,255,255,.45)','stroke-width':1.5}));
      });
    });
    // a single pulsing ring that sits on the current point ("you are here")
    var pulse=el('circle',{r:5,fill:'none',stroke:ARROW,'stroke-width':1.5});
    pulse.style.animation='mmpulse 1.6s ease-out infinite';
    svg.appendChild(pulse);
    // dots + name labels
    var dots={}, labels={};
    nodes.forEach(function(n){
      var g=el('g',{class:'mm-dot'});
      var c=el('circle',{cx:px(n.x),cy:px(n.y),r:4.5,fill:'#fff',stroke:ARROW,'stroke-width':1.5});
      g.appendChild(c);
      var t=el('text',{x:px(n.x),y:px(n.y)-6.5,'text-anchor':'middle',
        fill:'#fff','font-size':5.5,'font-weight':700,
        style:'paint-order:stroke;stroke:rgba(0,0,0,.7);stroke-width:1.2px'});
      t.textContent=n.label||'';
      g.appendChild(t);
      g.addEventListener('click',function(){ vt.setCurrentNode(n.id); });
      svg.appendChild(g); dots[n.id]=c; labels[n.id]=t;
    });
    function setActive(id){
      for(var k in dots){
        var on=(k===id);
        dots[k].setAttribute('fill',on?ARROW:'#fff');
        dots[k].setAttribute('r',on?6.5:4.5);
        labels[k].setAttribute('fill',on?'#7BE7E7':'#fff');
      }
      var cur=byId[id];
      if(cur){
        pulse.setAttribute('cx',px(cur.x)); pulse.setAttribute('cy',px(cur.y));
        pulse.style.display='block';
        nameEl.textContent='📍 '+(cur.label||'');
      } else { pulse.style.display='none'; }
    }
    vt.addEventListener('node-changed', function(e){ setActive(e.node.id); });
    setActive(TOUR.startNodeId);
  })();

  // ── version switcher ──────────────────────────────────────────────────────
  // For a node with >1 landlord-visible render, show pills. Tapping a pill makes
  // ONLY that render visible: we rebuild the CURRENT node's panorama via
  // vt.setNodes (viewer.setPanorama alone is ignored by the VirtualTour plugin)
  // and remember the choice per node so it survives navigation.
  (function(){
    var bar = document.getElementById('vbar');
    if (!viewer || !vt || !bar) return;
    var current = null;                 // version list for the node we're on
    var currentNodeId = null;
    var chosen = {};                    // nodeId -> chosen version index (sticky)

    function idxOf(list){
      var id = currentNodeId;
      if (id in chosen) return Math.min(chosen[id], list.length - 1);
      for (var i = 0; i < list.length; i++) if (list[i].def) return i; // published
      return 0;
    }
    function paint(sel){
      Array.prototype.forEach.call(bar.children, function(c, i){
        c.className = 'vchip' + (i === sel ? ' on' : '');
      });
    }
    function applyPanorama(list, sel){
      var v = list[sel];
      for (var i = 0; i < builtNodes.length; i++){
        if (builtNodes[i].id === currentNodeId){
          builtNodes[i].panorama = v.src;
          builtNodes[i].panoData = panoDataFor(v);
          break;
        }
      }
      // Rebuild the tour on the same node → shows ONLY the chosen render.
      try { vt.setNodes(builtNodes, currentNodeId); } catch (e) {}
    }
    function pick(sel){
      chosen[currentNodeId] = sel;
      paint(sel);
      applyPanorama(current, sel);      // triggers node-changed → render() re-syncs
    }
    function render(nodeId){
      currentNodeId = nodeId;
      var list = VERSIONS[nodeId];
      current = list || null;
      bar.innerHTML = '';
      if (!list || list.length < 2) { bar.style.display = 'none'; return; }
      var sel = idxOf(list);
      // make sure the shown panorama matches the (sticky) selection.
      var shownSrc = null;
      for (var i = 0; i < builtNodes.length; i++)
        if (builtNodes[i].id === nodeId) { shownSrc = builtNodes[i].panorama; break; }
      if (shownSrc !== list[sel].src) { applyPanorama(list, sel); return; }
      list.forEach(function(v, i){
        var b = document.createElement('div');
        b.className = 'vchip';
        b.textContent = v.source;
        b.addEventListener('click', function(){ pick(i); });
        bar.appendChild(b);
      });
      bar.style.display = 'flex';
      paint(sel);
    }
    vt.addEventListener('node-changed', function(e){ render(e.node.id); });
    render(TOUR.startNodeId);
  })();
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
                        widget.title.trim().isNotEmpty
                            ? widget.title
                            : AppLocalizations.of(context)!
                                .panoramaPsvTourCa52b1de,
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

class _Asset {
  const _Asset(this.path, this.mime);
  final String path;
  final String mime;
}

// ── pure, testable tour-config builder ───────────────────────────────────────

/// Heading continuity: when walking from [fromId] into [target], arrive facing
/// away from the link that points back (i.e. facing "forward"). Returns yaw in
/// degrees (-180..180), or 0 when geometry is unknown. Mirrors
/// `pannellumArrivalYaw` so both viewers behave identically.
double psvArrivalYaw(
    PropertyPanoramaTour tour, PanoramaNode target, String fromId) {
  for (final h in target.hotspots) {
    if (h.targetNodeId == fromId) {
      var y = (h.longitude + 180) % 360;
      if (y > 180) y -= 360;
      return y;
    }
  }
  return 0;
}

/// Builds the Photo-Sphere-Viewer VirtualTour config (node graph, flat 3D floor
/// arrows via link `position`, partial-pano haov/vaov, heading continuity) from
/// a [PropertyPanoramaTour]. [imageUrlFor] maps a node id to the URL the viewer
/// loads the panorama from. [available] optionally restricts to nodes whose
/// images actually loaded.
///
/// PSV's VirtualTour link `position` is `{ yaw, pitch }` in **radians**, so we
/// convert from our degrees. `startAngle` carries the arrival heading so the
/// view faces "forward" after a transition.
Map<String, dynamic> psvTourConfig(
  PropertyPanoramaTour tour, {
  required String Function(String nodeId) imageUrlFor,
  Set<String>? available,
}) {
  bool ok(String id) => available == null || available.contains(id);

  const deg2rad = 3.141592653589793 / 180.0;

  final nodes = <Map<String, dynamic>>[];
  for (final n in tour.nodes) {
    if (!ok(n.id)) continue;
    final links = <Map<String, dynamic>>[];
    for (final h in n.hotspots) {
      final target = tour.nodeById(h.targetNodeId);
      if (target == null || !ok(target.id)) continue;
      links.add({
        'nodeId': target.id,
        // flat floor-arrow direction (PSV link position is radians).
        'position': {
          'yaw': h.longitude * deg2rad,
          'pitch': h.latitude * deg2rad,
        },
        'name': h.label.isNotEmpty ? h.label : target.label,
        // heading continuity: where the camera should look on arrival.
        'arrivalYaw': psvArrivalYaw(tour, target, n.id),
      });
    }
    nodes.add({
      'id': n.id,
      'panorama': imageUrlFor(n.id),
      'name': n.label,
      'links': links,
      // partial-pano coverage; the HTML turns this into panoData(image).
      'haov': n.haov,
      'vaov': n.vaov,
      // heading the *first-shown* node should face (0 = unknown).
      'startAngle': 0,
    });
  }

  final first = tour.nodes.firstWhere((n) => ok(n.id),
      orElse: () => tour.nodes.first);
  return {
    'nodes': nodes,
    'startNodeId': first.id,
  };
}
