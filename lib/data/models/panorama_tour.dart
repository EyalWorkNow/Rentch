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
  });

  final String id;
  final String imageUrl; // equirectangular panorama, network or file path
  final String label; // e.g. "סלון", "מטבח"
  final List<PanoramaHotspot> hotspots;

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

  PanoramaNode copyWith({
    String? id,
    String? imageUrl,
    String? label,
    List<PanoramaHotspot>? hotspots,
    double? x,
    double? y,
    double? haov,
    double? vaov,
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
