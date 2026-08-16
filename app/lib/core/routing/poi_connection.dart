import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../geo/geo_utils.dart';
import '../../data/models/map_edge.dart';
import '../../data/models/map_poi.dart';
import '../../data/models/map_vertex.dart';
import 'path_network_snap.dart';

String? findPoiVertexId({
  required MapPoi poi,
  required List<MapVertex> vertices,
}) {
  return findNearestVertexId(
    lat: poi.lat,
    lng: poi.lng,
    vertices: vertices,
    maxDistanceMeters: AppConstants.pathDrawSnapMeters,
  );
}

MapEdge? findPoiSpurEdge({
  required MapPoi poi,
  required List<MapVertex> vertices,
  required List<MapEdge> edges,
}) {
  final poiVertexId = findPoiVertexId(poi: poi, vertices: vertices);
  if (poiVertexId == null) return null;

  MapEdge? fallback;
  for (final edge in edges) {
    if (edge.fromId != poiVertexId && edge.toId != poiVertexId) continue;
    fallback ??= edge;
    final otherId = edge.fromId == poiVertexId ? edge.toId : edge.fromId;
    if (poi.accessVertexId != null && otherId == poi.accessVertexId) {
      return edge;
    }
  }
  return fallback;
}

bool poiHasActiveConnection({
  required MapPoi poi,
  required List<MapVertex> vertices,
  required List<MapEdge> edges,
}) {
  final spur = findPoiSpurEdge(
    poi: poi,
    vertices: vertices,
    edges: edges,
  );
  if (spur != null) return true;

  final accessVertexId = poi.accessVertexId;
  if (accessVertexId == null) return false;

  for (final vertex in vertices) {
    if (vertex.id != accessVertexId) continue;
    return haversineMeters(poi.lat, poi.lng, vertex.lat, vertex.lng) <=
        AppConstants.pathDrawSnapMeters;
  }
  return false;
}

/// Routing anchor: where a person or POI meets the path network.
class PoiPathAnchor {
  const PoiPathAnchor({
    required this.pathVertexId,
    required this.pathPoint,
    required this.localPoint,
    required this.localDistanceMeters,
  });

  final String pathVertexId;
  final LatLng pathPoint;
  final LatLng localPoint;
  final double localDistanceMeters;
}

PoiPathAnchor? resolvePoiPathAnchor({
  required MapPoi poi,
  required List<MapVertex> vertices,
  required List<MapEdge> edges,
}) {
  final localPoint = LatLng(poi.lat, poi.lng);

  if (poi.accessVertexId != null &&
      poiHasActiveConnection(poi: poi, vertices: vertices, edges: edges)) {
    final accessVertexId = poi.accessVertexId!;
    for (final vertex in vertices) {
      if (vertex.id != accessVertexId) continue;
      final pathPoint = LatLng(vertex.lat, vertex.lng);
      return PoiPathAnchor(
        pathVertexId: accessVertexId,
        pathPoint: pathPoint,
        localPoint: localPoint,
        localDistanceMeters: haversineMeters(
          localPoint.latitude,
          localPoint.longitude,
          pathPoint.latitude,
          pathPoint.longitude,
        ),
      );
    }
  }

  final snap = findNearestPointOnPathNetwork(
    lat: poi.lat,
    lng: poi.lng,
    vertices: vertices,
    edges: edges,
    maxDistanceMeters: AppConstants.poiPathAccessMaxMeters,
  );
  if (snap == null) return null;

  final pathVertexId = closerPathEndpointId(snap: snap, vertices: vertices);
  if (pathVertexId == null) return null;

  return PoiPathAnchor(
    pathVertexId: pathVertexId,
    pathPoint: snap.point,
    localPoint: localPoint,
    localDistanceMeters: snap.distanceMeters,
  );
}

PoiPathAnchor? resolveUserPathAnchor({
  required double lat,
  required double lng,
  required List<MapPoi> pois,
  required List<MapVertex> vertices,
  required List<MapEdge> edges,
}) {
  final localPoint = LatLng(lat, lng);

  final nearPoi = findNearestPoi(
    lat: lat,
    lng: lng,
    pois: pois,
    maxDistanceMeters: AppConstants.routingSnapMaxMeters,
  );
  if (nearPoi != null) {
    final poiAnchor = resolvePoiPathAnchor(
      poi: nearPoi,
      vertices: vertices,
      edges: edges,
    );
    if (poiAnchor != null) {
      return PoiPathAnchor(
        pathVertexId: poiAnchor.pathVertexId,
        pathPoint: poiAnchor.pathPoint,
        localPoint: localPoint,
        localDistanceMeters: haversineMeters(
          localPoint.latitude,
          localPoint.longitude,
          poiAnchor.pathPoint.latitude,
          poiAnchor.pathPoint.longitude,
        ),
      );
    }
  }

  final snap = findNearestPointOnPathNetwork(
    lat: lat,
    lng: lng,
    vertices: vertices,
    edges: edges,
  );
  if (snap == null) return null;

  final pathVertexId = closerPathEndpointId(snap: snap, vertices: vertices);
  if (pathVertexId == null) return null;

  return PoiPathAnchor(
    pathVertexId: pathVertexId,
    pathPoint: snap.point,
    localPoint: localPoint,
    localDistanceMeters: snap.distanceMeters,
  );
}
