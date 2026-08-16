import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../../data/models/map_poi.dart';
import '../../data/models/map_vertex.dart';

const _distance = Distance();

double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  return _distance(
    LatLng(lat1, lng1),
    LatLng(lat2, lng2),
  );
}

double polylineLengthMeters(List<LatLng> points) {
  if (points.length < 2) return 0;
  var total = 0.0;
  for (var i = 0; i < points.length - 1; i++) {
    total += haversineMeters(
      points[i].latitude,
      points[i].longitude,
      points[i + 1].latitude,
      points[i + 1].longitude,
    );
  }
  return total;
}

MapVertex? findNearestVertex({
  required double lat,
  required double lng,
  required List<MapVertex> vertices,
  double maxDistanceMeters = AppConstants.snapDistanceMeters,
}) {
  MapVertex? nearest;
  var best = maxDistanceMeters;
  for (final vertex in vertices) {
    final d = haversineMeters(lat, lng, vertex.lat, vertex.lng);
    if (d <= best) {
      best = d;
      nearest = vertex;
    }
  }
  return nearest;
}

String? findNearestVertexId({
  required double lat,
  required double lng,
  required List<MapVertex> vertices,
  double maxDistanceMeters = AppConstants.routingSnapMaxMeters,
}) {
  return findNearestVertex(
    lat: lat,
    lng: lng,
    vertices: vertices,
    maxDistanceMeters: maxDistanceMeters,
  )?.id;
}

List<LatLng> decodeRouteCoordinates(List<MapVertex> vertices, List<String> vertexIds) {
  final points = <LatLng>[];
  for (final id in vertexIds) {
    for (final vertex in vertices) {
      if (vertex.id == id) {
        points.add(LatLng(vertex.lat, vertex.lng));
        break;
      }
    }
  }
  return points;
}

int estimateWalkMinutes(double meters) => math.max(1, (meters / 80).round());

/// Samples points along a polyline at fixed intervals (for dotted route display).
List<LatLng> samplePointsAlongPolyline(
  List<LatLng> points, {
  double intervalMeters = 8,
}) {
  if (points.length < 2) return points;
  final samples = <LatLng>[points.first];
  var traversed = 0.0;

  for (var i = 0; i < points.length - 1; i++) {
    final start = points[i];
    final end = points[i + 1];
    final segmentLength = haversineMeters(
      start.latitude,
      start.longitude,
      end.latitude,
      end.longitude,
    );
    if (segmentLength <= 0) continue;

    var cursor = intervalMeters - (traversed % intervalMeters);
    if (cursor <= 0) cursor = intervalMeters;

    while (cursor <= segmentLength) {
      final t = cursor / segmentLength;
      samples.add(
        LatLng(
          start.latitude + (end.latitude - start.latitude) * t,
          start.longitude + (end.longitude - start.longitude) * t,
        ),
      );
      cursor += intervalMeters;
    }
    traversed += segmentLength;
  }

  if (samples.isEmpty ||
      samples.last.latitude != points.last.latitude ||
      samples.last.longitude != points.last.longitude) {
    samples.add(points.last);
  }
  return samples;
}

MapPoi? findNearestPoi({
  required double lat,
  required double lng,
  required List<MapPoi> pois,
  double maxDistanceMeters = AppConstants.poiTapMaxMeters,
}) {
  MapPoi? nearest;
  var best = maxDistanceMeters;
  for (final poi in pois) {
    final d = haversineMeters(lat, lng, poi.lat, poi.lng);
    if (d <= best) {
      best = d;
      nearest = poi;
    }
  }
  return nearest;
}

String locationLabelNear({
  required double lat,
  required double lng,
  required List<MapVertex> vertices,
  required List<MapPoi> pois,
}) {
  final vertex = findNearestVertex(
    lat: lat,
    lng: lng,
    vertices: vertices,
    maxDistanceMeters: AppConstants.routingSnapMaxMeters,
  );
  if (vertex?.label != null && vertex!.label!.isNotEmpty) {
    return vertex.label!;
  }

  for (final v in vertices) {
    if (v.isEntrance && v.label != null && v.label!.isNotEmpty) {
      final d = haversineMeters(lat, lng, v.lat, v.lng);
      if (d <= AppConstants.routingSnapMaxMeters) {
        return v.label!;
      }
    }
  }

  final poi = findNearestPoi(lat: lat, lng: lng, pois: pois, maxDistanceMeters: 25);
  if (poi != null) return poi.displayTitle;

  return 'Din placering';
}
