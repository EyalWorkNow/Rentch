import 'package:flutter/foundation.dart';

/// One scanned room on the property draft. Either a cloud reconstruction (KIRI
/// → mesh/splat URLs) or a fast on-device RoomPlan capture (local USDZ path).
///
/// Lives in the data layer (not the capture screen) so the persisted
/// [PropertyModel3d] can carry the full room list end-to-end without the model
/// layer depending on `presentation/`.
@immutable
class ScannedRoom {
  const ScannedRoom({
    required this.name,
    this.meshGlbUrl,
    this.splatUrl,
    this.usdzPath,
    this.source = 'cloud',
  });

  /// Hebrew room name chosen by the user (סלון / מטבח / חדר שינה …).
  final String name;

  /// Textured mesh URL when reconstructed in the cloud.
  final String? meshGlbUrl;

  /// Gaussian-splat URL when reconstructed in the cloud.
  final String? splatUrl;

  /// Local USDZ path from an on-device RoomPlan capture (display is a backend
  /// follow-up — for now we only confirm it was captured).
  final String? usdzPath;

  /// 'cloud' (KIRI) or 'roomplan' (iPhone Pro LiDAR).
  final String source;

  bool get isCloud => source == 'cloud';
  bool get hasViewableAsset =>
      (meshGlbUrl?.isNotEmpty ?? false) || (splatUrl?.isNotEmpty ?? false);

  ScannedRoom copyWith({String? name}) => ScannedRoom(
        name: name ?? this.name,
        meshGlbUrl: meshGlbUrl,
        splatUrl: splatUrl,
        usdzPath: usdzPath,
        source: source,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        if (meshGlbUrl != null) 'meshGlbUrl': meshGlbUrl,
        if (splatUrl != null) 'splatUrl': splatUrl,
        if (usdzPath != null) 'usdzPath': usdzPath,
        'source': source,
      };

  factory ScannedRoom.fromJson(Map<String, dynamic> json) => ScannedRoom(
        name: json['name']?.toString() ?? 'חדר',
        meshGlbUrl: _nonEmpty(json['meshGlbUrl']),
        splatUrl: _nonEmpty(json['splatUrl']),
        usdzPath: _nonEmpty(json['usdzPath']),
        source: json['source']?.toString() ?? 'cloud',
      );

  static String? _nonEmpty(Object? v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }
}
