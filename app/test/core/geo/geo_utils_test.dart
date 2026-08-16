import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:event_map/core/geo/geo_utils.dart';

void main() {
  test('samplePointsAlongPolyline spaces dots along route', () {
    final points = [
      const LatLng(56.0, 10.0),
      const LatLng(56.0005, 10.0),
    ];
    final samples = samplePointsAlongPolyline(points, intervalMeters: 20);
    expect(samples.length, greaterThan(1));
    expect(samples.first.latitude, points.first.latitude);
    expect(samples.last.latitude, points.last.latitude);
  });
}
