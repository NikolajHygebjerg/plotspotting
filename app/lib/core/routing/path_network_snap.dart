import 'package:latlong2/latlong.dart';

import '../geo/geo_utils.dart';
import '../../data/models/map_edge.dart';
import '../../data/models/map_vertex.dart';

/// Closest point on the path network (sti-kanter), not kun hjørner.
class PathNetworkSnap {
  const PathNetworkSnap({
    required this.point,
    required this.edgeFromId,
    required this.edgeToId,
    required this.distanceMeters,
  });

  final LatLng point;
  final String edgeFromId;
  final String edgeToId;
  final double distanceMeters;

  List<String> get endpointIds =>
      edgeFromId == edgeToId ? [edgeFromId] : [edgeFromId, edgeToId];
}

class SegmentProjection {
  const SegmentProjection({
    required this.point,
    required this.alongMeters,
    required this.distanceMeters,
  });

  final LatLng point;
  final double alongMeters;
  final double distanceMeters;
}

SegmentProjection projectPointOnSegment({
  required LatLng point,
  required LatLng start,
  required LatLng end,
}) {
  final segmentLength = haversineMeters(
    start.latitude,
    start.longitude,
    end.latitude,
    end.longitude,
  );
  if (segmentLength <= 0) {
    return SegmentProjection(
      point: start,
      alongMeters: 0,
      distanceMeters: haversineMeters(
        start.latitude,
        start.longitude,
        point.latitude,
        point.longitude,
      ),
    );
  }

  final dx = end.longitude - start.longitude;
  final dy = end.latitude - start.latitude;
  final px = point.longitude - start.longitude;
  final py = point.latitude - start.latitude;
  final denom = dx * dx + dy * dy;
  final t = denom == 0 ? 0.0 : ((px * dx + py * dy) / denom).clamp(0.0, 1.0);
  final projected = LatLng(
    start.latitude + dy * t,
    start.longitude + dx * t,
  );

  return SegmentProjection(
    point: projected,
    alongMeters: segmentLength * t,
    distanceMeters: haversineMeters(
      projected.latitude,
      projected.longitude,
      point.latitude,
      point.longitude,
    ),
  );
}

List<LatLng> edgeGeometryPoints(MapEdge edge, List<MapVertex> vertices) {
  if (edge.geometry.length >= 2) return edge.geometry;

  MapVertex? vertexById(String id) {
    for (final vertex in vertices) {
      if (vertex.id == id) return vertex;
    }
    return null;
  }

  final from = vertexById(edge.fromId);
  final to = vertexById(edge.toId);
  if (from != null && to != null) {
    return [LatLng(from.lat, from.lng), LatLng(to.lat, to.lng)];
  }
  return const [];
}

PathNetworkSnap? findNearestPointOnPathNetwork({
  required double lat,
  required double lng,
  required List<MapVertex> vertices,
  required List<MapEdge> edges,
  double maxDistanceMeters = double.infinity,
  Set<String> excludedEdgeIds = const {},
  Set<String> excludedVertexIds = const {},
}) {
  if (edges.isEmpty) {
    final vertex = findNearestVertex(
      lat: lat,
      lng: lng,
      vertices: vertices,
      maxDistanceMeters: maxDistanceMeters,
    );
    if (vertex == null || excludedVertexIds.contains(vertex.id)) return null;
    final distance = haversineMeters(lat, lng, vertex.lat, vertex.lng);
    return PathNetworkSnap(
      point: LatLng(vertex.lat, vertex.lng),
      edgeFromId: vertex.id,
      edgeToId: vertex.id,
      distanceMeters: distance,
    );
  }

  final target = LatLng(lat, lng);
  PathNetworkSnap? best;

  for (final edge in edges) {
    if (excludedEdgeIds.contains(edge.id)) continue;

    final geometry = edgeGeometryPoints(edge, vertices);
    for (var index = 0; index < geometry.length - 1; index++) {
      final projection = projectPointOnSegment(
        point: target,
        start: geometry[index],
        end: geometry[index + 1],
      );
      if (projection.distanceMeters > maxDistanceMeters) continue;
      if (best == null || projection.distanceMeters < best.distanceMeters) {
        best = PathNetworkSnap(
          point: projection.point,
          edgeFromId: edge.fromId,
          edgeToId: edge.toId,
          distanceMeters: projection.distanceMeters,
        );
      }
    }
  }

  if (best != null) return best;

  final vertex = findNearestVertex(
    lat: lat,
    lng: lng,
    vertices: vertices,
    maxDistanceMeters: maxDistanceMeters,
  );
  if (vertex == null || excludedVertexIds.contains(vertex.id)) return null;
  final distance = haversineMeters(lat, lng, vertex.lat, vertex.lng);
  return PathNetworkSnap(
    point: LatLng(vertex.lat, vertex.lng),
    edgeFromId: vertex.id,
    edgeToId: vertex.id,
    distanceMeters: distance,
  );
}

String? closerPathEndpointId({
  required PathNetworkSnap snap,
  required List<MapVertex> vertices,
}) {
  MapVertex? vertexById(String id) {
    for (final vertex in vertices) {
      if (vertex.id == id) return vertex;
    }
    return null;
  }

  if (snap.edgeFromId == snap.edgeToId) return snap.edgeFromId;

  final from = vertexById(snap.edgeFromId);
  final to = vertexById(snap.edgeToId);
  if (from == null) return snap.edgeToId;
  if (to == null) return snap.edgeFromId;

  final fromDistance = haversineMeters(
    snap.point.latitude,
    snap.point.longitude,
    from.lat,
    from.lng,
  );
  final toDistance = haversineMeters(
    snap.point.latitude,
    snap.point.longitude,
    to.lat,
    to.lng,
  );
  return fromDistance <= toDistance ? snap.edgeFromId : snap.edgeToId;
}
