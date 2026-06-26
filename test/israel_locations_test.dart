import 'package:flutter_test/flutter_test.dart';
import 'package:dating_app/core/services/israel_locations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await IsraelLocations.ensureLoaded();
  });

  test('loads thousands of cities including ירושלים', () {
    final all = IsraelLocations.searchCities('', limit: 5000);
    expect(all.length, greaterThan(1000));
    expect(all, contains('ירושלים'));
  });

  test('streetsOf("ירושלים") is non-empty', () {
    final streets = IsraelLocations.streetsOf('ירושלים');
    expect(streets, isNotEmpty);
  });

  test('searchCities("תל") surfaces Tel Aviv', () {
    final results = IsraelLocations.searchCities('תל');
    expect(results.any((c) => c.contains('תל אביב')), isTrue);
  });

  test('searchCities prefix matches rank first', () {
    final results = IsraelLocations.searchCities('ירוש');
    expect(results.first, 'ירושלים');
  });

  test('street search filters results', () {
    final all = IsraelLocations.streetsOf('ירושלים', limit: 10000);
    expect(all.length, greaterThan(1));
    // Pick a substring from a real street and confirm filtering narrows.
    final sample = all.first;
    final probe = sample.length >= 2 ? sample.substring(0, 2) : sample;
    final filtered = IsraelLocations.streetsOf('ירושלים', query: probe, limit: 10000);
    expect(filtered.length, lessThanOrEqualTo(all.length));
    expect(filtered, isNotEmpty);
  });

  test('Hebrew normalization ignores quotes/geresh', () {
    final withQuote = IsraelLocations.searchCities('תל-אביב');
    expect(withQuote.any((c) => c.contains('תל אביב')), isTrue);
  });

  test('ensureLoaded is idempotent', () async {
    await IsraelLocations.ensureLoaded();
    await IsraelLocations.ensureLoaded();
    expect(IsraelLocations.searchCities('').isNotEmpty, isTrue);
  });
}
