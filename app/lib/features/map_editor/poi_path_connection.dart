import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/geo/geo_utils.dart';
import '../../core/routing/poi_connection.dart';
import '../../core/routing/path_network_snap.dart';
import '../../data/models/map_edge.dart';
import '../../data/models/map_poi.dart';
import '../../data/models/map_vertex.dart';

export '../../core/routing/poi_connection.dart'
    show findPoiSpurEdge, findPoiVertexId, poiHasActiveConnection;

class PoiPathConnectionProposal {
  const PoiPathConnectionProposal({
    required this.poi,
    required this.snap,
  });

  final MapPoi poi;
  final PathNetworkSnap snap;

  double get distanceMeters => snap.distanceMeters;
}

class BulkPoiPathConnectionPlan {
  const BulkPoiPathConnectionPlan({
    required this.proposals,
    required this.outOfRange,
  });

  final List<PoiPathConnectionProposal> proposals;
  final List<MapPoi> outOfRange;

  int get connectableCount => proposals.length;
  int get skippedCount => outOfRange.length;
}

BulkPoiPathConnectionPlan planAllPoiPathConnections({
  required List<MapPoi> pois,
  required List<MapVertex> vertices,
  required List<MapEdge> edges,
}) {
  if (edges.isEmpty) {
    return BulkPoiPathConnectionPlan(
      proposals: const [],
      outOfRange: List<MapPoi>.from(pois),
    );
  }

  final proposals = <PoiPathConnectionProposal>[];
  final outOfRange = <MapPoi>[];

  for (final poi in pois) {
    final snap = suggestPoiPathConnection(
      poi: poi,
      vertices: vertices,
      edges: edges,
      pois: pois,
    );
    if (snap == null) {
      outOfRange.add(poi);
      continue;
    }
    proposals.add(PoiPathConnectionProposal(poi: poi, snap: snap));
  }

  proposals.sort(
    (a, b) => a.poi.displayTitle.compareTo(b.poi.displayTitle),
  );
  outOfRange.sort(
    (a, b) => a.displayTitle.compareTo(b.displayTitle),
  );

  return BulkPoiPathConnectionPlan(
    proposals: proposals,
    outOfRange: outOfRange,
  );
}

BulkPoiPathConnectionApplyResult applyBulkPoiPathConnectionPlan({
  required BulkPoiPathConnectionPlan plan,
  required List<MapPoi> pois,
  required List<MapVertex> vertices,
  required List<MapEdge> edges,
  Uuid uuid = const Uuid(),
}) {
  var currentVertices = List<MapVertex>.from(vertices);
  var currentEdges = List<MapEdge>.from(edges);
  final poiById = {for (final poi in pois) poi.id: poi};

  for (final proposal in plan.proposals) {
    final currentPois = pois.map((poi) => poiById[poi.id] ?? poi).toList();
    final snap = suggestPoiPathConnection(
      poi: proposal.poi,
      vertices: currentVertices,
      edges: currentEdges,
      pois: currentPois,
    );
    if (snap == null) continue;

    final applied = applyPoiPathConnection(
      poi: proposal.poi,
      snap: snap,
      vertices: currentVertices,
      edges: currentEdges,
      pois: currentPois,
      uuid: uuid,
    );
    currentVertices = applied.vertices;
    currentEdges = applied.edges;
    poiById[proposal.poi.id] =
        proposal.poi.copyWith(accessVertexId: applied.accessVertexId);
  }

  return BulkPoiPathConnectionApplyResult(
    vertices: currentVertices,
    edges: currentEdges,
    pois: pois.map((poi) => poiById[poi.id] ?? poi).toList(),
  );
}

class BulkPoiPathConnectionApplyResult {
  const BulkPoiPathConnectionApplyResult({
    required this.vertices,
    required this.edges,
    required this.pois,
  });

  final List<MapVertex> vertices;
  final List<MapEdge> edges;
  final List<MapPoi> pois;
}

List<List<LatLng>> bulkConnectionPreviewLines(BulkPoiPathConnectionPlan plan) {
  return [
    for (final proposal in plan.proposals)
      poiConnectionPreviewPoints(poi: proposal.poi, snap: proposal.snap),
  ];
}

class ClearPoiConnectionResult {
  const ClearPoiConnectionResult({
    required this.vertices,
    required this.edges,
    required this.poi,
  });

  final List<MapVertex> vertices;
  final List<MapEdge> edges;
  final MapPoi poi;
}

class PoiSpurHit {
  const PoiSpurHit({
    required this.poi,
    required this.distanceMeters,
  });

  final MapPoi poi;
  final double distanceMeters;
}

Set<String> collectPoiSpurEdgeIds({
  required List<MapPoi> pois,
  required List<MapVertex> vertices,
  required List<MapEdge> edges,
}) {
  final ids = <String>{};
  for (final poi in pois) {
    final spur = findPoiSpurEdge(
      poi: poi,
      vertices: vertices,
      edges: edges,
    );
    if (spur != null) ids.add(spur.id);
  }
  return ids;
}

Set<String> collectPoiVertexIds({
  required List<MapPoi> pois,
  required List<MapVertex> vertices,
}) {
  final ids = <String>{};
  for (final poi in pois) {
    final id = findPoiVertexId(poi: poi, vertices: vertices);
    if (id != null) ids.add(id);
  }
  return ids;
}

PathNetworkSnap? findNearestPointOnOfficialPathNetwork({
  required double lat,
  required double lng,
  required List<MapVertex> vertices,
  required List<MapEdge> edges,
  required List<MapPoi> pois,
  double maxDistanceMeters = double.infinity,
}) {
  return findNearestPointOnPathNetwork(
    lat: lat,
    lng: lng,
    vertices: vertices,
    edges: edges,
    maxDistanceMeters: maxDistanceMeters,
    excludedEdgeIds: collectPoiSpurEdgeIds(
      pois: pois,
      vertices: vertices,
      edges: edges,
    ),
    excludedVertexIds: collectPoiVertexIds(
      pois: pois,
      vertices: vertices,
    ),
  );
}

bool snapIsOnOfficialPath({
  required PathNetworkSnap snap,
  required List<MapPoi> pois,
  required List<MapVertex> vertices,
  required List<MapEdge> edges,
}) {
  if (snap.edgeFromId == snap.edgeToId) {
    return !collectPoiVertexIds(pois: pois, vertices: vertices)
        .contains(snap.edgeFromId);
  }

  for (final edge in edges) {
    if (edge.fromId != snap.edgeFromId || edge.toId != snap.edgeToId) {
      if (edge.fromId != snap.edgeToId || edge.toId != snap.edgeFromId) {
        continue;
      }
    }
    return !collectPoiSpurEdgeIds(
      pois: pois,
      vertices: vertices,
      edges: edges,
    ).contains(edge.id);
  }
  return false;
}

bool poiConnectionIsBroken({
  required MapPoi poi,
  required List<MapVertex> vertices,
  required List<MapEdge> edges,
}) {
  if (poi.accessVertexId == null) {
    return findPoiSpurEdge(poi: poi, vertices: vertices, edges: edges) != null;
  }
  return !poiHasActiveConnection(poi: poi, vertices: vertices, edges: edges);
}

ClearPoiConnectionResult clearPoiConnection({
  required MapPoi poi,
  required List<MapVertex> vertices,
  required List<MapEdge> edges,
}) {
  var currentVertices = List<MapVertex>.from(vertices);
  var currentEdges = List<MapEdge>.from(edges);
  final poiVertexId = findPoiVertexId(poi: poi, vertices: currentVertices);

  if (poiVertexId != null) {
    currentEdges = currentEdges
        .where(
          (edge) => edge.fromId != poiVertexId && edge.toId != poiVertexId,
        )
        .toList();

    final stillConnected = currentEdges.any(
      (edge) => edge.fromId == poiVertexId || edge.toId == poiVertexId,
    );
    if (!stillConnected) {
      for (final vertex in currentVertices) {
        if (vertex.id != poiVertexId) continue;
        final distance = haversineMeters(
          poi.lat,
          poi.lng,
          vertex.lat,
          vertex.lng,
        );
        if (distance <= AppConstants.pathDrawSnapMeters) {
          currentVertices =
              currentVertices.where((v) => v.id != poiVertexId).toList();
        }
        break;
      }
    }
  }

  return ClearPoiConnectionResult(
    vertices: currentVertices,
    edges: currentEdges,
    poi: poi.copyWith(clearAccessVertexId: true),
  );
}

MapPoi? findPoiForAccessVertex({
  required String vertexId,
  required List<MapPoi> pois,
}) {
  MapPoi? match;
  for (final poi in pois) {
    if (poi.accessVertexId != vertexId) continue;
    if (match != null) return null;
    match = poi;
  }
  return match;
}

PoiSpurHit? findPoiSpurNearTap({
  required double lat,
  required double lng,
  required List<MapPoi> pois,
  required List<MapVertex> vertices,
  required List<MapEdge> edges,
  double maxDistanceMeters = 8,
}) {
  final tap = LatLng(lat, lng);
  PoiSpurHit? best;

  for (final poi in pois) {
    final spur = findPoiSpurEdge(
      poi: poi,
      vertices: vertices,
      edges: edges,
    );
    if (spur == null) continue;

    final geometry = edgeGeometryPoints(spur, vertices);
    for (var index = 0; index < geometry.length - 1; index++) {
      final projection = projectPointOnSegment(
        point: tap,
        start: geometry[index],
        end: geometry[index + 1],
      );
      if (projection.distanceMeters > maxDistanceMeters) continue;
      if (best == null || projection.distanceMeters < best.distanceMeters) {
        best = PoiSpurHit(
          poi: poi,
          distanceMeters: projection.distanceMeters,
        );
      }
    }
  }

  return best;
}

List<MapPoi> repairBrokenPoiConnections({
  required List<MapPoi> pois,
  required List<MapVertex> vertices,
  required List<MapEdge> edges,
}) {
  return pois.map((poi) {
    if (!poiConnectionIsBroken(
      poi: poi,
      vertices: vertices,
      edges: edges,
    )) {
      return poi;
    }
    return poi.copyWith(clearAccessVertexId: true);
  }).toList();
}

class PoiPathConnectionDraft {
  const PoiPathConnectionDraft({
    required this.poi,
    required this.snap,
    required this.isNew,
  });

  final MapPoi poi;
  final PathNetworkSnap snap;
  final bool isNew;
}

class PoiPathConnectionApplyResult {
  const PoiPathConnectionApplyResult({
    required this.vertices,
    required this.edges,
    required this.accessVertexId,
    required this.snap,
  });

  final List<MapVertex> vertices;
  final List<MapEdge> edges;
  final String accessVertexId;
  final PathNetworkSnap snap;
}

PathNetworkSnap? suggestPoiPathConnection({
  required MapPoi poi,
  required List<MapVertex> vertices,
  required List<MapEdge> edges,
  required List<MapPoi> pois,
}) {
  return findNearestPointOnOfficialPathNetwork(
    lat: poi.lat,
    lng: poi.lng,
    vertices: vertices,
    edges: edges,
    pois: pois,
    maxDistanceMeters: AppConstants.poiPathAccessMaxMeters,
  );
}

PathNetworkSnap? snapNearMapTap({
  required double lat,
  required double lng,
  required List<MapVertex> vertices,
  required List<MapEdge> edges,
  required List<MapPoi> pois,
}) {
  return findNearestPointOnOfficialPathNetwork(
    lat: lat,
    lng: lng,
    vertices: vertices,
    edges: edges,
    pois: pois,
    maxDistanceMeters: AppConstants.poiPathAccessMaxMeters,
  );
}

PathNetworkSnap? snapForExistingAccess({
  required MapPoi poi,
  required List<MapVertex> vertices,
}) {
  final accessVertexId = poi.accessVertexId;
  if (accessVertexId == null) return null;

  for (final vertex in vertices) {
    if (vertex.id != accessVertexId) continue;
    return PathNetworkSnap(
      point: LatLng(vertex.lat, vertex.lng),
      edgeFromId: vertex.id,
      edgeToId: vertex.id,
      distanceMeters: haversineMeters(
        poi.lat,
        poi.lng,
        vertex.lat,
        vertex.lng,
      ),
    );
  }
  return null;
}

List<LatLng> poiConnectionPreviewPoints({
  required MapPoi poi,
  required PathNetworkSnap snap,
}) {
  return [
    LatLng(poi.lat, poi.lng),
    snap.point,
  ];
}

PoiPathConnectionApplyResult applyPoiPathConnection({
  required MapPoi poi,
  required PathNetworkSnap snap,
  required List<MapVertex> vertices,
  required List<MapEdge> edges,
  required List<MapPoi> pois,
  Uuid uuid = const Uuid(),
}) {
  if (!snapIsOnOfficialPath(
    snap: snap,
    pois: pois,
    vertices: vertices,
    edges: edges,
  )) {
    throw StateError('Tilkobling skal være på en officiel sti — ikke et andet sted');
  }

  final access = _ensureAccessOnPathNetwork(
    snap: snap,
    vertices: vertices,
    edges: edges,
    uuid: uuid,
  );

  final spur = _ensurePoiSpurToAccess(
    poi: poi,
    accessVertexId: access.accessVertexId,
    accessPoint: access.snap.point,
    vertices: access.vertices,
    edges: access.edges,
    uuid: uuid,
  );

  return PoiPathConnectionApplyResult(
    vertices: spur.vertices,
    edges: spur.edges,
    accessVertexId: access.accessVertexId,
    snap: access.snap,
  );
}

class _GraphPatch {
  const _GraphPatch({
    required this.vertices,
    required this.edges,
    required this.accessVertexId,
    required this.snap,
  });

  final List<MapVertex> vertices;
  final List<MapEdge> edges;
  final String accessVertexId;
  final PathNetworkSnap snap;
}

_GraphPatch _ensureAccessOnPathNetwork({
  required PathNetworkSnap snap,
  required List<MapVertex> vertices,
  required List<MapEdge> edges,
  Uuid uuid = const Uuid(),
}) {
  final nearVertex = findNearestVertex(
    lat: snap.point.latitude,
    lng: snap.point.longitude,
    vertices: vertices,
    maxDistanceMeters: AppConstants.pathDrawSnapMeters,
  );
  if (nearVertex != null) {
    return _GraphPatch(
      vertices: vertices,
      edges: edges,
      accessVertexId: nearVertex.id,
      snap: PathNetworkSnap(
        point: LatLng(nearVertex.lat, nearVertex.lng),
        edgeFromId: nearVertex.id,
        edgeToId: nearVertex.id,
        distanceMeters: snap.distanceMeters,
      ),
    );
  }

  if (snap.edgeFromId == snap.edgeToId) {
    return _GraphPatch(
      vertices: vertices,
      edges: edges,
      accessVertexId: snap.edgeFromId,
      snap: snap,
    );
  }

  final junction = MapVertex(
    id: uuid.v4(),
    lat: snap.point.latitude,
    lng: snap.point.longitude,
  );
  final updatedVertices = [...vertices, junction];
  final split = _splitEdgeAtPoint(
    snap: snap,
    junctionId: junction.id,
    vertices: updatedVertices,
    edges: edges,
    uuid: uuid,
  );

  return _GraphPatch(
    vertices: updatedVertices,
    edges: split,
    accessVertexId: junction.id,
    snap: PathNetworkSnap(
      point: LatLng(junction.lat, junction.lng),
      edgeFromId: junction.id,
      edgeToId: junction.id,
      distanceMeters: snap.distanceMeters,
    ),
  );
}

_GraphPatch _ensurePoiSpurToAccess({
  required MapPoi poi,
  required String accessVertexId,
  required LatLng accessPoint,
  required List<MapVertex> vertices,
  required List<MapEdge> edges,
  Uuid uuid = const Uuid(),
}) {
  final poiVertexId = _ensurePoiVertex(
    poi: poi,
    vertices: vertices,
    uuid: uuid,
  );
  final poiVertex = vertices.firstWhere((vertex) => vertex.id == poiVertexId);

  final spurDistance = haversineMeters(
    poiVertex.lat,
    poiVertex.lng,
    accessPoint.latitude,
    accessPoint.longitude,
  );
  if (spurDistance <= AppConstants.pathDrawSnapMeters) {
    return _GraphPatch(
      vertices: vertices,
      edges: edges,
      accessVertexId: accessVertexId,
      snap: PathNetworkSnap(
        point: accessPoint,
        edgeFromId: accessVertexId,
        edgeToId: accessVertexId,
        distanceMeters: spurDistance,
      ),
    );
  }

  final withoutOldSpurs = edges.where((edge) {
    final touchesPoi =
        edge.fromId == poiVertexId || edge.toId == poiVertexId;
    return !touchesPoi;
  }).toList();

  if (_hasEdgeBetween(withoutOldSpurs, poiVertexId, accessVertexId)) {
    return _GraphPatch(
      vertices: vertices,
      edges: withoutOldSpurs,
      accessVertexId: accessVertexId,
      snap: PathNetworkSnap(
        point: accessPoint,
        edgeFromId: accessVertexId,
        edgeToId: accessVertexId,
        distanceMeters: spurDistance,
      ),
    );
  }

  final geometry = [
    LatLng(poiVertex.lat, poiVertex.lng),
    accessPoint,
  ];
  final spurEdge = MapEdge(
    id: uuid.v4(),
    fromId: poiVertexId,
    toId: accessVertexId,
    geometry: geometry,
    lengthMeters: polylineLengthMeters(geometry),
  );

  return _GraphPatch(
    vertices: vertices,
    edges: [...withoutOldSpurs, spurEdge],
    accessVertexId: accessVertexId,
    snap: PathNetworkSnap(
      point: accessPoint,
      edgeFromId: accessVertexId,
      edgeToId: accessVertexId,
      distanceMeters: spurDistance,
    ),
  );
}

String _ensurePoiVertex({
  required MapPoi poi,
  required List<MapVertex> vertices,
  required Uuid uuid,
}) {
  final nearVertex = findNearestVertex(
    lat: poi.lat,
    lng: poi.lng,
    vertices: vertices,
    maxDistanceMeters: AppConstants.pathDrawSnapMeters,
  );
  if (nearVertex != null) {
    return nearVertex.id;
  }

  final poiVertex = MapVertex(
    id: uuid.v4(),
    lat: poi.lat,
    lng: poi.lng,
  );
  vertices.add(poiVertex);
  return poiVertex.id;
}

bool _hasEdgeBetween(List<MapEdge> edges, String fromId, String toId) {
  for (final edge in edges) {
    if ((edge.fromId == fromId && edge.toId == toId) ||
        (edge.fromId == toId && edge.toId == fromId)) {
      return true;
    }
  }
  return false;
}

List<MapEdge> _splitEdgeAtPoint({
  required PathNetworkSnap snap,
  required String junctionId,
  required List<MapVertex> vertices,
  required List<MapEdge> edges,
  required Uuid uuid,
}) {
  final updated = <MapEdge>[];
  var split = false;

  for (final edge in edges) {
    final matchesForward =
        edge.fromId == snap.edgeFromId && edge.toId == snap.edgeToId;
    final matchesReverse =
        edge.fromId == snap.edgeToId && edge.toId == snap.edgeFromId;
    if (!matchesForward && !matchesReverse) {
      updated.add(edge);
      continue;
    }

    final geometry = edgeGeometryPoints(edge, vertices);
    if (geometry.length < 2) {
      updated.add(edge);
      continue;
    }

    split = true;
    if (matchesReverse) {
      final reversed = geometry.reversed.toList();
      updated.addAll(
        _splitGeometryEdge(
          edge: edge,
          geometry: reversed,
          junctionId: junctionId,
          fromId: snap.edgeToId,
          toId: snap.edgeFromId,
          snapPoint: snap.point,
          uuid: uuid,
        ),
      );
      continue;
    }

    updated.addAll(
      _splitGeometryEdge(
        edge: edge,
        geometry: geometry,
        junctionId: junctionId,
        fromId: snap.edgeFromId,
        toId: snap.edgeToId,
        snapPoint: snap.point,
        uuid: uuid,
      ),
    );
  }

  if (!split) {
    return edges;
  }
  return updated;
}

List<MapEdge> _splitGeometryEdge({
  required MapEdge edge,
  required List<LatLng> geometry,
  required String junctionId,
  required String fromId,
  required String toId,
  required LatLng snapPoint,
  required Uuid uuid,
}) {
  var bestSegment = 0;
  var bestDistance = double.infinity;
  for (var index = 0; index < geometry.length - 1; index++) {
    final projection = projectPointOnSegment(
      point: snapPoint,
      start: geometry[index],
      end: geometry[index + 1],
    );
    if (projection.distanceMeters < bestDistance) {
      bestDistance = projection.distanceMeters;
      bestSegment = index;
    }
  }

  final firstGeometry = [
    ...geometry.sublist(0, bestSegment + 1),
    snapPoint,
  ];
  final secondGeometry = [
    snapPoint,
    ...geometry.sublist(bestSegment + 1),
  ];

  return [
    MapEdge(
      id: uuid.v4(),
      fromId: fromId,
      toId: junctionId,
      geometry: firstGeometry,
      lengthMeters: polylineLengthMeters(firstGeometry),
      bidirectional: edge.bidirectional,
    ),
    MapEdge(
      id: uuid.v4(),
      fromId: junctionId,
      toId: toId,
      geometry: secondGeometry,
      lengthMeters: polylineLengthMeters(secondGeometry),
      bidirectional: edge.bidirectional,
    ),
  ];
}
