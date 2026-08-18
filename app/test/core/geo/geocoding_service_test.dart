import 'package:flutter_test/flutter_test.dart';

import 'package:event_map/core/geo/geocoding_service.dart';

void main() {
  group('GeocodingService.parseSearchResponse', () {
    test('parses Nominatim JSON array', () {
      const body = '''
[
  {
    "display_name": "Friland, Feldballe, Danmark",
    "lat": "56.361234",
    "lon": "10.521234",
    "boundingbox": ["56.350", "56.370", "10.510", "10.530"]
  }
]
''';

      final results = GeocodingService.parseSearchResponse(body);
      expect(results, hasLength(1));
      expect(results.first.displayName, contains('Friland'));
      expect(results.first.lat, closeTo(56.361234, 0.0001));
      expect(results.first.lng, closeTo(10.521234, 0.0001));
      expect(results.first.bounds?.south, closeTo(56.350, 0.001));
      expect(results.first.bounds?.north, closeTo(56.370, 0.001));
    });

    test('returns empty list for invalid JSON', () {
      expect(GeocodingService.parseSearchResponse('{}'), isEmpty);
      expect(GeocodingService.parseSearchResponse('not json'), throwsFormatException);
    });
  });

  test('GeocodingBounds estimateZoom prefers larger span', () {
    const tight = GeocodingBounds(
      south: 56.36,
      north: 56.37,
      west: 10.52,
      east: 10.53,
    );
    const wide = GeocodingBounds(
      south: 56.0,
      north: 57.0,
      west: 10.0,
      east: 11.0,
    );
    expect(tight.estimateZoom(), greaterThan(wide.estimateZoom()));
  });
}
