// ════════════════════════════════════════════════════════════════════════════
// PANORAMA TOUR — lightweight, Street-View-style 360° walkthrough
// ════════════════════════════════════════════════════════════════════════════
//
// A do-it-yourself alternative to the (heavy, backend-dependent) 3D scan: the
// landlord stands at a few points in the apartment, captures a 360° panorama at
// each, and links them. Viewers then drag/gyro to look around each point and tap
// arrows to walk to the next — exactly like Google Street View, with zero server
// processing (just equirectangular images in S3).
//
// Model:
//   PanoramaHotspot — a tappable arrow inside a node pointing to another node.
//   PanoramaNode    — one capture point: an equirectangular image + its hotspots.
//   PropertyPanoramaTour — the ordered set of nodes for a property.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:convert';

class PanoramaHotspot {
  const PanoramaHotspot({
    required this.targetNodeId,
    this.longitude = 0.0, // yaw, -180..180 (where the arrow sits)
    this.latitude = -8.0, // pitch, slightly down (floor-ward) by default
    this.label = '',
  });

  final String targetNodeId;
  final double longitude;
  final double latitude;
  final String label;

  PanoramaHotspot copyWith({
    String? targetNodeId,
    double? longitude,
    double? latitude,
    String? label,
  }) =>
      PanoramaHotspot(
        targetNodeId: targetNodeId ?? this.targetNodeId,
        longitude: longitude ?? this.longitude,
        latitude: latitude ?? this.latitude,
        label: label ?? this.label,
      );

  factory PanoramaHotspot.fromJson(Map<String, dynamic> j) => PanoramaHotspot(
        targetNodeId: j['targetNodeId']?.toString() ?? '',
        longitude: (j['longitude'] as num?)?.toDouble() ?? 0.0,
        latitude: (j['latitude'] as num?)?.toDouble() ?? -8.0,
        label: j['label']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'targetNodeId': targetNodeId,
        'longitude': longitude,
        'latitude': latitude,
        if (label.isNotEmpty) 'label': label,
      };
}

/// One 360° render of a node's viewpoint. A node can hold several — the raw
/// stitch, an AI ceiling/floor completion, a gpt-image-2 regen — and the
/// landlord picks the active one. Non-destructive: adding a version never
/// discards the previous image.
class PanoVersion {
  const PanoVersion({
    required this.imageUrl,
    this.haov = 360,
    this.vaov = 180,
    this.source = '',
    this.hidden = false,
  });

  final String imageUrl;
  final double haov;
  final double vaov;

  /// Short human label for the picker: 'מקור', 'משופר ✨', 'AI ✨'.
  final String source;

  /// Landlord-only: when true this render is NOT offered to viewers (tenants).
  /// The landlord toggles it to curate which versions the 360 viewer shows.
  final bool hidden;

  PanoVersion copyWith(
          {String? imageUrl, double? haov, double? vaov, String? source, bool? hidden}) =>
      PanoVersion(
        imageUrl: imageUrl ?? this.imageUrl,
        haov: haov ?? this.haov,
        vaov: vaov ?? this.vaov,
        source: source ?? this.source,
        hidden: hidden ?? this.hidden,
      );

  factory PanoVersion.fromJson(Map<String, dynamic> j) => PanoVersion(
        imageUrl: j['imageUrl']?.toString() ?? '',
        haov: (j['haov'] as num?)?.toDouble() ?? 360,
        vaov: (j['vaov'] as num?)?.toDouble() ?? 180,
        source: j['source']?.toString() ?? '',
        hidden: j['hidden'] == true,
      );

  Map<String, dynamic> toJson() => {
        'imageUrl': imageUrl,
        'haov': haov,
        'vaov': vaov,
        if (source.isNotEmpty) 'source': source,
        if (hidden) 'hidden': true,
      };
}

class PanoramaNode {
  const PanoramaNode({
    required this.id,
    required this.imageUrl,
    this.label = '',
    this.hotspots = const [],
    this.x,
    this.y,
    this.haov = 360,
    this.vaov = 180,
    this.versions = const [],
    this.activeVersion = 0,
  });

  final String id;
  // The ACTIVE version's image + FOV. Kept as plain fields so every viewer and
  // toJson reader that already uses imageUrl/haov/vaov needs no change; the
  // [versions] list is additive metadata for the picker.
  final String imageUrl; // equirectangular panorama, network or file path
  final String label; // e.g. "סלון", "מטבח"
  final List<PanoramaHotspot> hotspots;

  /// All 360° renders captured/generated for this point. Empty on legacy nodes;
  /// use [allVersions] to always get at least the current image as one entry.
  final List<PanoVersion> versions;

  /// Index into [allVersions] of the currently-shown render.
  final int activeVersion;

  /// Normalized position (0..1) on the floor sketch, for the mini-map and for
  /// computing geometrically-correct link directions. Null until placed.
  final double? x;
  final double? y;

  /// Horizontal / vertical angle of view (degrees) the panorama actually covers.
  /// 360×180 = full sphere; a partial panorama (e.g. a single wide shot) sets a
  /// smaller haov/vaov so Pannellum renders it without faking the missing parts.
  final double haov;
  final double vaov;

  bool get hasPosition => x != null && y != null;

  bool get isLocal =>
      imageUrl.startsWith('/') || imageUrl.startsWith('file://');

  /// Always at least one entry: legacy nodes (empty [versions]) synthesize a
  /// single 'מקור' version from the current image so the picker/UI is uniform.
  List<PanoVersion> get allVersions => versions.isNotEmpty
      ? versions
      : [PanoVersion(imageUrl: imageUrl, haov: haov, vaov: vaov, source: 'מקור')];

  bool get hasMultipleVersions => allVersions.length > 1;

  /// Versions offered to viewers (tenants) — the landlord's curated set. Always
  /// includes the active version so the viewer is never left with nothing.
  List<PanoVersion> get viewerVersions {
    final shown = allVersions.where((v) => !v.hidden).toList();
    if (shown.isNotEmpty) return shown;
    final all = allVersions;
    return [all[activeVersion.clamp(0, all.length - 1)]];
  }

  /// Toggle a version's visibility to viewers. Refuses to hide the last visible
  /// one (a node must always show something).
  PanoramaNode toggleVersionHidden(int i) {
    final list = [...allVersions];
    if (i < 0 || i >= list.length) return this;
    final willHide = !list[i].hidden;
    if (willHide && list.where((v) => !v.hidden).length <= 1) return this;
    list[i] = list[i].copyWith(hidden: willHide);
    // If we hid the active version, move active to the first still-visible one.
    var idx = activeVersion;
    if (list[idx].hidden) {
      final firstVisible = list.indexWhere((v) => !v.hidden);
      if (firstVisible >= 0) idx = firstVisible;
    }
    // Route through _withVersions so the active render's image/FOV are mirrored
    // into imageUrl/haov/vaov (the published default that viewers first see).
    return _withVersions(list, idx);
  }

  /// Non-destructive: append [v] and (optionally) make it active. The previous
  /// image is preserved as an earlier version — this is what makes enhance/AI
  /// reversible and comparable. Materializes [versions] so it persists.
  PanoramaNode addVersion(PanoVersion v, {bool makeActive = true}) {
    final list = [...allVersions, v];
    final idx = makeActive ? list.length - 1 : activeVersion;
    return _withVersions(list, idx);
  }

  /// Switch the shown render to [i]; mirrors its image/FOV into the active
  /// fields so viewers (which read imageUrl/haov/vaov) update with no changes.
  PanoramaNode selectVersion(int i) {
    final list = allVersions;
    final idx = i.clamp(0, list.length - 1);
    return _withVersions(list, idx);
  }

  PanoramaNode _withVersions(List<PanoVersion> list, int idx) {
    final active = list[idx];
    return copyWith(
      versions: list,
      activeVersion: idx,
      imageUrl: active.imageUrl,
      haov: active.haov,
      vaov: active.vaov,
    );
  }

  PanoramaNode copyWith({
    String? id,
    String? imageUrl,
    String? label,
    List<PanoramaHotspot>? hotspots,
    double? x,
    double? y,
    double? haov,
    double? vaov,
    List<PanoVersion>? versions,
    int? activeVersion,
  }) =>
      PanoramaNode(
        id: id ?? this.id,
        imageUrl: imageUrl ?? this.imageUrl,
        label: label ?? this.label,
        hotspots: hotspots ?? this.hotspots,
        x: x ?? this.x,
        y: y ?? this.y,
        haov: haov ?? this.haov,
        vaov: vaov ?? this.vaov,
        versions: versions ?? this.versions,
        activeVersion: activeVersion ?? this.activeVersion,
      );

  factory PanoramaNode.fromJson(Map<String, dynamic> j) => PanoramaNode(
        id: j['id']?.toString() ?? '',
        imageUrl: j['imageUrl']?.toString() ?? '',
        label: j['label']?.toString() ?? '',
        hotspots: (j['hotspots'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((m) => PanoramaHotspot.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
        x: (j['x'] as num?)?.toDouble(),
        y: (j['y'] as num?)?.toDouble(),
        haov: (j['haov'] as num?)?.toDouble() ?? 360,
        vaov: (j['vaov'] as num?)?.toDouble() ?? 180,
        versions: (j['versions'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((m) => PanoVersion.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
        activeVersion: (j['activeVersion'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'imageUrl': imageUrl,
        if (label.isNotEmpty) 'label': label,
        'hotspots': hotspots.map((h) => h.toJson()).toList(),
        if (x != null) 'x': x,
        if (y != null) 'y': y,
        if (haov != 360) 'haov': haov,
        if (vaov != 180) 'vaov': vaov,
        // Persist versions when there's a real choice (>1) OR a single version
        // still carries curation metadata (a source label like 'AI ✨' or a
        // hidden flag) — otherwise that labeling silently reverts to 'מקור' on
        // reload.
        if (versions.length > 1 ||
            versions.any((v) => v.source.isNotEmpty || v.hidden)) ...{
          'versions': versions.map((v) => v.toJson()).toList(),
          'activeVersion': activeVersion,
        },
      };
}

class PropertyPanoramaTour {
  const PropertyPanoramaTour({this.nodes = const []});

  final List<PanoramaNode> nodes;

  bool get isEmpty => nodes.isEmpty;
  bool get isNotEmpty => nodes.isNotEmpty;
  int get length => nodes.length;
  PanoramaNode? get first => nodes.isEmpty ? null : nodes.first;

  PanoramaNode? nodeById(String id) {
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  PropertyPanoramaTour copyWith({List<PanoramaNode>? nodes}) =>
      PropertyPanoramaTour(nodes: nodes ?? this.nodes);

  /// Parse from arbitrary JSON (object with `nodes`, or a bare list), tolerant of
  /// nulls so it can sit alongside other optional property fields.
  static PropertyPanoramaTour? fromJsonOrNull(Object? raw) {
    if (raw == null) return null;
    // The backend stores the tour as a JSON *string* (jsonEncode(toJson())), so a
    // remote fetch/deep-link arrives here as a String, not a Map. Without this
    // decode the whole tour silently drops to null and the 360 vanishes off the
    // device that captured it.
    if (raw is String) {
      final s = raw.trim();
      if (s.isEmpty) return null;
      try {
        return fromJsonOrNull(jsonDecode(s));
      } catch (_) {
        return null;
      }
    }
    List<dynamic>? list;
    if (raw is Map && raw['nodes'] is List) {
      list = raw['nodes'] as List<dynamic>;
    } else if (raw is List) {
      list = raw;
    }
    if (list == null || list.isEmpty) return null;
    final nodes = list
        .whereType<Map>()
        .map((m) => PanoramaNode.fromJson(Map<String, dynamic>.from(m)))
        .where((n) => n.id.isNotEmpty && n.imageUrl.isNotEmpty)
        .toList();
    if (nodes.isEmpty) return null;
    return PropertyPanoramaTour(nodes: nodes);
  }

  Map<String, dynamic> toJson() =>
      {'nodes': nodes.map((n) => n.toJson()).toList()};
}
