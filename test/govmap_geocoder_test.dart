import 'package:dating_app/core/services/govmap_geocoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Guards the ITM (EPSG:2039) → WGS84 port against a typo. Reference points are
  // GovMap DetailsByQuery results (X/Y) with their known lat/lon.
  test('ITM → WGS84 matches known Israeli points', () {
    void near(List<double> got, double lat, double lon) {
      expect(got[0], closeTo(lat, 0.001), reason: 'lat');
      expect(got[1], closeTo(lon, 0.001), reason: 'lon');
    }

    near(GovMapGeocoder.itmToWgs84(178827.6335, 665188.2267), 32.0789, 34.7734); // Dizengoff 100, TLV
    near(GovMapGeocoder.itmToWgs84(193155, 544017), 30.9865, 34.9284); // Yeruham
    near(GovMapGeocoder.itmToWgs84(181009, 572228), 31.2406, 34.8002); // Rothschild, Beer Sheva
  });
}
