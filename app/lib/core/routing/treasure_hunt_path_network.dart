import 'package:latlong2/latlong.dart';

import '../../core/constants.dart';
import '../../core/geo/geo_utils.dart';
import '../../data/models/event_map_data.dart';
import '../../data/models/map_edge.dart';
import '../../data/models/map_vertex.dart';
import '../../data/models/treasure_hunt.dart';

/// Routing-netværk = officielle stier + jagt-specifikke stier.
class TreasureHuntRoutingNetwork {
  const TreasureHuntRoutingNetwork({
    required this.vertices,
    required this.edges,
    required this.officialVertices,
    required this.officialEdges,
    required this.huntVertices,
    required this.huntEdges,
  });

  final List<MapVertex> vertices;
  final List<MapEdge> edges;
  final List<MapVertex> officialVertices;
  final List<MapEdge> officialEdges;
  final List<MapVertex> huntVertices;
  final List<MapEdge> huntEdges;

  factory TreasureHuntRoutingNetwork.fromEvent({
    required EventMapData data,
    required TreasureHuntConfig hunt,
  }) {
    final officialVertices = data.vertices;
    final officialEdges = data.edges;
    final huntNetwork = hunt.pathNetwork;

    final vertexById = <String, MapVertex>{
      for (final vertex in officialVertices) vertex.id: vertex,
      for (final vertex in huntNetwork.vertices) vertex.id: vertex,
    };

    return TreasureHuntRoutingNetwork(
      vertices: vertexById.values.toList(),
      edges: [...officialEdges, ...huntNetwork.edges],
      officialVertices: officialVertices,
      officialEdges: officialEdges,
      huntVertices: huntNetwork.vertices,
      huntEdges: huntNetwork.edges,
    );
  }
}

class TreasureHuntPathDrawState {
  const TreasureHuntPathDrawState({
    required this.vertices,
    required this.edges,
    this.lastVertexId,
    this.strokeVertexIds = const [],
  });

  final List<MapVertex> vertices;
  final List<MapEdge> edges;
  final String? lastVertexId;
  final List<String> strokeVertexIds;
}

TreasureHuntPathDrawState addTreasureHuntPathPoint({
  required TreasureHuntPathDrawState state,
  required double lat,
  required double lng,
  required List<MapVertex> officialVertices,
  required String Function() newVertexId,
  required String Function() newEdgeId,
}) {
  final vertices = List<MapVertex>.from(state.vertices);
  final edges = List<MapEdge>.from(state.edges);
  final strokeVertexIds = List<String>.from(state.strokeVertexIds);

  final snapPool = [...officialVertices, ...vertices];
  final snapped = findNearestVertex(
    lat: lat,
    lng: lng,
    vertices: snapPool,
    maxDistanceMeters: AppConstants.pathDrawSnapMeters,
  );

  final vertex = snapped ??
      MapVertex(
        id: newVertexId(),
        lat: lat,
        lng: lng,
      );

  if (snapped == null) {
    vertices.add(vertex);
  }

  var lastVertexId = state.lastVertexId;
  if (lastVertexId != null && lastVertexId != vertex.id) {
    MapVertex? from;
    for (final candidate in snapPool) {
      if (candidate.id == lastVertexId) {
        from = candidate;
        break;
      }
    }
    if (from != null) {
      final geometry = [
        LatLng(from.lat, from.lng),
        LatLng(vertex.lat, vertex.lng),
      ];
      edges.add(
        MapEdge(
          id: newEdgeId(),
          fromId: lastVertexId,
          toId: vertex.id,
          geometry: geometry,
          lengthMeters: polylineLengthMeters(geometry),
        ),
      );
    }
  }

  lastVertexId = vertex.id;
  if (strokeVertexIds.isEmpty || strokeVertexIds.last != vertex.id) {
    strokeVertexIds.add(vertex.id);
  }

  return TreasureHuntPathDrawState(
    vertices: vertices,
    edges: edges,
    lastVertexId: lastVertexId,
    strokeVertexIds: strokeVertexIds,
  );
}

TreasureHuntPathDrawState? undoTreasureHuntPathPoint(TreasureHuntPathDrawState state) {
  if (state.strokeVertexIds.isEmpty && state.lastVertexId == null) {
    return null;
  }

  final vertices = List<MapVertex>.from(state.vertices);
  final edges = List<MapEdge>.from(state.edges);
  final strokeVertexIds = List<String>.from(state.strokeVertexIds);

  final removedId = strokeVertexIds.isNotEmpty
      ? strokeVertexIds.removeLast()
      : state.lastVertexId;
  if (removedId == null) return null;

  edges.removeWhere(
    (edge) => edge.fromId == removedId || edge.toId == removedId,
  );

  final stillReferenced = edges.any(
    (edge) => edge.fromId == removedId || edge.toId == removedId,
  );
  if (!stillReferenced) {
    vertices.removeWhere((vertex) => vertex.id == removedId);
  }

  final lastVertexId =
      strokeVertexIds.isNotEmpty ? strokeVertexIds.last : null;

  return TreasureHuntPathDrawState(
    vertices: vertices,
    edges: edges,
    lastVertexId: lastVertexId,
    strokeVertexIds: strokeVertexIds,
  );
}
