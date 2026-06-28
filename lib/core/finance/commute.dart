// ════════════════════════════════════════════════════════════════════════════
// COMMUTE — straight-line → coarse drive/transit time estimate
// ════════════════════════════════════════════════════════════════════════════
//
// Tenant Feature #3: for relocating professionals & families, commute-to-work is
// often THE deciding factor — yet no listing surfaces it. This pure, deterministic
// helper turns a (property, work) coordinate pair into an honest, clearly-
// approximated commute estimate.
//
// It is intentionally NOT a routing engine: no roads, no live traffic, no deps.
// We take the great-circle (haversine) distance, inflate it by a coarse urban
// road factor, and divide by an effective city-driving speed. Every label is
// prefixed with "כ-" (≈) so it never overpromises precision.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;

/// A coarse, deterministic commute estimate between two coordinates.
class CommuteEstimate {
  const CommuteEstimate({
    required this.straightLineKm,
    required this.approxDriveMinutes,
    required this.approxTransitMinutes,
    required this.plainHebrewLabel,
  });

  /// Great-circle distance (km) between property and work.
  final double straightLineKm;

  /// Approximate door-to-door driving time in minutes (urban, no traffic model).
  final int approxDriveMinutes;

  /// Approximate public-transit time in minutes (slower than driving + wait).
  final int approxTransitMinutes;

  /// User-facing Hebrew label, e.g. `כ-22 דק' לעבודה (~8 ק"מ)`.
  final String plainHebrewLabel;
}

class Commute {
  const Commute._();

  // Road distance ≈ this × straight-line in a typical Israeli urban grid.
  static const double _roadFactor = 1.3;

  // Effective door-to-door urban driving speed (km/h) including stops/lights.
  static const double _driveSpeedKmh = 25.0;

  // Effective transit speed (km/h) — slower vehicle speed; the fixed wait is
  // added separately below.
  static const double _transitSpeedKmh = 18.0;

  // Typical fixed overhead for transit (walk to stop + wait), in minutes.
  static const double _transitOverheadMin = 8.0;

  /// Coarse, deterministic commute estimate from a property to a work location.
  ///
  /// Returns `null` only when a coordinate is clearly invalid (≈ null island),
  /// matching the convention used by the gov-data geo helpers.
  static CommuteEstimate? estimate({
    required double propLat,
    required double propLon,
    required double workLat,
    required double workLon,
  }) {
    if (!_valid(propLat, propLon) || !_valid(workLat, workLon)) return null;

    final straightKm = _haversineKm(propLat, propLon, workLat, workLon);
    final roadKm = straightKm * _roadFactor;

    final driveMin = (roadKm / _driveSpeedKmh * 60).round();
    final transitMin =
        (_transitOverheadMin + roadKm / _transitSpeedKmh * 60).round();

    return CommuteEstimate(
      straightLineKm: straightKm,
      approxDriveMinutes: driveMin,
      approxTransitMinutes: transitMin,
      plainHebrewLabel: _label(driveMin, straightKm),
    );
  }

  // "כ-22 דק' לעבודה (~8 ק"מ)" — always approximate (כ- / ~).
  static String _label(int driveMin, double straightKm) {
    final km = straightKm < 10
        ? straightKm.toStringAsFixed(1)
        : straightKm.round().toString();
    return 'כ-$driveMin דק\' לעבודה (~$km ק"מ)';
  }

  // Reject the null-island region (mirrors GovData._validCoord).
  static bool _valid(double lat, double lon) => lat.abs() > 0.1 && lon.abs() > 0.1;

  static double _haversineKm(double la1, double lo1, double la2, double lo2) {
    const r = 6371.0088;
    final dLa = _rad(la2 - la1);
    final dLo = _rad(lo2 - lo1);
    final a = math.sin(dLa / 2) * math.sin(dLa / 2) +
        math.cos(_rad(la1)) *
            math.cos(_rad(la2)) *
            math.sin(dLo / 2) *
            math.sin(dLo / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double d) => d * math.pi / 180.0;
}
