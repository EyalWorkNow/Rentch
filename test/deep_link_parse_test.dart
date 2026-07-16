import 'package:dating_app/core/services/deep_link_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeepLinkService.propertyIdFrom', () {
    test('parses the custom rently://property/<id> scheme', () {
      expect(DeepLinkService.propertyIdFrom(Uri.parse('rently://property/abc123')),
          'abc123');
    });

    test('parses the plain https /p/<id> Universal Link', () {
      expect(
          DeepLinkService.propertyIdFrom(Uri.parse('https://rent.ly/p/xyz789')),
          'xyz789');
    });

    test('tolerates the /prod stage prefix in https /prod/p/<id>', () {
      expect(
          DeepLinkService.propertyIdFrom(
              Uri.parse('https://api.example.com/prod/p/id-42')),
          'id-42');
    });

    test('returns null for unrelated / malformed links', () {
      expect(DeepLinkService.propertyIdFrom(Uri.parse('rently://property/')),
          isNull);
      expect(DeepLinkService.propertyIdFrom(Uri.parse('rently://other/abc')),
          isNull);
      expect(DeepLinkService.propertyIdFrom(Uri.parse('https://rent.ly/p/')),
          isNull);
      expect(DeepLinkService.propertyIdFrom(Uri.parse('https://rent.ly/about')),
          isNull);
    });
  });
}
