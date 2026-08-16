import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../geo/geo_utils.dart';
import 'path_network_snap.dart';
import 'poi_connection.dart';
import '../../data/models/map_edge.dart';
import '../../data/models/map_poi.dart';
import '../../data/models/map_vertex.dart';
import 'graph.dart';

class RoutePlan {
  const RoutePlan({
    required this.points,
    required this.vertexPath,
    required this.approachMeters,
    required this.pathMeters,
    this.departureMeters = 0,
  });

  final List<LatLng> points;
  final List<String> vertexPath;
  final double approachMeters;
  final double pathMeters;
  final double departureMeters;

  double get totalMeters => approachMeters + pathMeters + departureMeters;
}

class RoutingService {
  static const approachMergeMeters = 4.0;

  MapEdge? _edgeBetween(List<MapEdge> edges, String fromId, String toId) {
    for (final edge in edges) {
      if (edge.fromId == fromId && edge.toId == toId) return edge;
      if (edge.bidirectional && edge.fromId == toId && edge.toId == fromId) {
        return edge;
      }
    }
    return null;
  }

  MapVertex? _vertexById(List<MapVertex> vertices, String id) {
    for (final vertex in vertices) {
      if (vertex.id == id) return vertex;
    }
    return null;
  }

  double pathLengthMeters({
    required List<MapVertex> vertices,
    required List<MapEdge> edges,
    required List<String> vertexPath,
  }) {
    if (vertexPath.length < 2) return 0;

    var total = 0.0;
    for (var i = 0; i < vertexPath.length - 1; i++) {
      final edge = _edgeBetween(edges, vertexPath[i], vertexPath[i + 1]);
      if (edge != null && edge.lengthMeters > 0) {
        total += edge.lengthMeters;
        continue;
      }

      final from = _vertexById(vertices, vertexPath[i]);
      final to = _vertexById(vertices, vertexPath[i + 1]);
      if (from != null && to != null) {
        total += haversineMeters(from.lat, from.lng, to.lat, to.lng);
      }
    }
    return total;
  }

  List<LatLng> expandPathPoints({
    required List<MapVertex> vertices,
    required List<MapEdge> edges,
    required List<String> vertexPath,
  }) {
    if (vertexPath.isEmpty) return const [];

    final points = <LatLng>[];
    for (var i = 0; i < vertexPath.length - 1; i++) {
      final edge = _edgeBetween(edges, vertexPath[i], vertexPath[i + 1]);
      if (edge != null && edge.geometry.length >= 2) {
        if (points.isEmpty) {
          points.addAll(edge.geometry);
        } else {
          points.addAll(edge.geometry.skip(1));
        }
        continue;
      }

      final vertex = _vertexById(vertices, vertexPath[i]);
      if (vertex != null) {
        points.add(LatLng(vertex.lat, vertex.lng));
      }
    }

    final last = _vertexById(vertices, vertexPath.last);
    if (last != null) {
      if (points.isEmpty ||
          points.last.latitude != last.lat ||
          points.last.longitude != last.lng) {
        points.add(LatLng(last.lat, last.lng));
      }
    }

    if (points.length >= 2) return points;
    return decodeRouteCoordinates(vertices, vertexPath);
  }

  List<String> routeBetween({
    required List<MapVertex> vertices,
    required List<MapEdge> edges,
    required String startVertexId,
    required String goalVertexId,
  }) {
    final graph = PathGraph(
      vertices: {
        for (final v in vertices)
          v.id: GraphVertex(id: v.id, lat: v.lat, lng: v.lng, isEntrance: v.isEntrance),
      },
      edges: [
        for (final e in edges)
          GraphEdge(
            id: e.id,
            fromId: e.fromId,
            toId: e.toId,
            lengthMeters: e.lengthMeters,
            bidirectional: e.bidirectional,
          ),
      ],
    );
    return graph.shortestPath(startVertexId, goalVertexId);
  }

  RoutePlan? planRouteFromLocation({
    required double lat,
    required double lng,
    required List<MapVertex> vertices,
    required List<MapEdge> edges,
    required String goalVertexId,
  }) {
    final goal = _vertexById(vertices, goalVertexId);
    if (goal == null) return null;

    return planRouteBetweenCoordinates(
      startLat: lat,
      startLng: lng,
      goalLat: goal.lat,
      goalLng: goal.lng,
      vertices: vertices,
      edges: edges,
    );
  }

  RoutePlan? planRouteToPoi({
    required double lat,
    required double lng,
    required List<MapVertex> vertices,
    required List<MapEdge> edges,
    required MapPoi poi,
    List<MapPoi> pois = const [],
  }) {
    final goalAnchor = resolvePoiPathAnchor(
      poi: poi,
      vertices: vertices,
      edges: edges,
    );
    if (goalAnchor == null) return null;

    final startAnchor = resolveUserPathAnchor(
      lat: lat,
      lng: lng,
      pois: pois,
      vertices: vertices,
      edges: edges,
    );
    if (startAnchor == null) return null;

    return _planRouteBetweenAnchors(
      start: startAnchor,
      goal: goalAnchor,
      vertices: vertices,
      edges: edges,
    );
  }

  RoutePlan? _planRouteBetweenAnchors({
    required PoiPathAnchor start,
    required PoiPathAnchor goal,
    required List<MapVertex> vertices,
    required List<MapEdge> edges,
  }) {
    final points = _composeRoutePointsFromAnchors(
      start: start,
      goal: goal,
      vertices: vertices,
      edges: edges,
    );
    if (points.length < 2) return null;

    final approachMeters = start.localDistanceMeters > approachMergeMeters
        ? start.localDistanceMeters
        : 0.0;
    final departureMeters = goal.localDistanceMeters > approachMergeMeters
        ? goal.localDistanceMeters
        : 0.0;
    final total = polylineLengthMeters(points);
    final pathMeters = (total - approachMeters - departureMeters)
        .clamp(0.0, total)
        .toDouble();

    final vertexPath = start.pathVertexId == goal.pathVertexId
        ? <String>[start.pathVertexId]
        : routeBetween(
            vertices: vertices,
            edges: edges,
            startVertexId: start.pathVertexId,
            goalVertexId: goal.pathVertexId,
          );

    return RoutePlan(
      points: points,
      vertexPath: vertexPath,
      approachMeters: approachMeters,
      pathMeters: pathMeters,
      departureMeters: departureMeters,
    );
  }

  List<LatLng> _composeRoutePointsFromAnchors({
    required PoiPathAnchor start,
    required PoiPathAnchor goal,
    required List<MapVertex> vertices,
    required List<MapEdge> edges,
  }) {
    final points = <LatLng>[];

    void addPoint(LatLng point) {
      if (points.isEmpty) {
        points.add(point);
        return;
      }
      final last = points.last;
      if (haversineMeters(
            last.latitude,
            last.longitude,
            point.latitude,
            point.longitude,
          ) >
          1.5) {
        points.add(point);
      }
    }

    if (start.localDistanceMeters > approachMergeMeters) {
      addPoint(start.localPoint);
    }
    addPoint(start.pathPoint);

    if (start.pathVertexId == goal.pathVertexId) {
      addPoint(goal.pathPoint);
    } else {
      final vertexPath = routeBetween(
        vertices: vertices,
        edges: edges,
        startVertexId: start.pathVertexId,
        goalVertexId: goal.pathVertexId,
      );
      if (vertexPath.isEmpty) return const [];

      final expanded = expandPathPoints(
        vertices: vertices,
        edges: edges,
        vertexPath: vertexPath,
      );
      for (final point in expanded) {
        addPoint(point);
      }
      addPoint(goal.pathPoint);
    }

    if (goal.localDistanceMeters > approachMergeMeters) {
      addPoint(goal.localPoint);
    }

    if (points.length < 2) {
      addPoint(goal.pathPoint);
    }
    if (points.length < 2) {
      addPoint(goal.localPoint);
    }

    return points;
  }

  RoutePlan? planRouteBetweenCoordinates({
    required double startLat,
    required double startLng,
    required double goalLat,
    required double goalLng,
    required List<MapVertex> vertices,
    required List<MapEdge> edges,
  }) {
    if (vertices.isEmpty) return null;

    final user = LatLng(startLat, startLng);
    final goal = LatLng(goalLat, goalLng);

    final startSnap = findNearestPointOnPathNetwork(
      lat: startLat,
      lng: startLng,
      vertices: vertices,
      edges: edges,
    );
    final goalSnap = findNearestPointOnPathNetwork(
      lat: goalLat,
      lng: goalLng,
      vertices: vertices,
      edges: edges,
      maxDistanceMeters: AppConstants.poiPathAccessMaxMeters,
    );

    if (startSnap == null || goalSnap == null) return null;

    final startVertexId = closerPathEndpointId(
      snap: startSnap,
      vertices: vertices,
    );
    final goalVertexId = closerPathEndpointId(
      snap: goalSnap,
      vertices: vertices,
    );
    if (startVertexId == null || goalVertexId == null) return null;

    final points = _composeRoutePoints(
      user: user,
      goal: goal,
      startSnap: startSnap,
      goalSnap: goalSnap,
      startVertexId: startVertexId,
      goalVertexId: goalVertexId,
      vertices: vertices,
      edges: edges,
    );
    if (points.length < 2) return null;

    final approach = haversineMeters(
      user.latitude,
      user.longitude,
      startSnap.point.latitude,
      startSnap.point.longitude,
    );
    final departure = haversineMeters(
      goalSnap.point.latitude,
      goalSnap.point.longitude,
      goal.latitude,
      goal.longitude,
    );
    final total = polylineLengthMeters(points);
    final approachMeters =
        approach > approachMergeMeters ? approach : 0.0;
    final departureMeters =
        departure > approachMergeMeters ? departure : 0.0;
    final pathMeters = (total - approachMeters - departureMeters)
        .clamp(0.0, total)
        .toDouble();

    final List<String> vertexPath = startVertexId == goalVertexId
        ? <String>[startVertexId]
        : routeBetween(
            vertices: vertices,
            edges: edges,
            startVertexId: startVertexId,
            goalVertexId: goalVertexId,
          );

    return RoutePlan(
      points: points,
      vertexPath: vertexPath,
      approachMeters: approachMeters,
      pathMeters: pathMeters,
      departureMeters: departureMeters,
    );
  }

  List<LatLng> _composeRoutePoints({
    required LatLng user,
    required LatLng goal,
    required PathNetworkSnap startSnap,
    required PathNetworkSnap goalSnap,
    required String startVertexId,
    required String goalVertexId,
    required List<MapVertex> vertices,
    required List<MapEdge> edges,
  }) {
    final points = <LatLng>[];

    void addPoint(LatLng point) {
      if (points.isEmpty) {
        points.add(point);
        return;
      }
      final last = points.last;
      if (haversineMeters(
            last.latitude,
            last.longitude,
            point.latitude,
            point.longitude,
          ) >
          1.5) {
        points.add(point);
      }
    }

    if (haversineMeters(
          user.latitude,
          user.longitude,
          startSnap.point.latitude,
          startSnap.point.longitude,
        ) >
        approachMergeMeters) {
      addPoint(user);
    }
    addPoint(startSnap.point);

    if (startVertexId == goalVertexId) {
      addPoint(goalSnap.point);
    } else {
      final vertexPath = routeBetween(
        vertices: vertices,
        edges: edges,
        startVertexId: startVertexId,
        goalVertexId: goalVertexId,
      );
      if (vertexPath.isEmpty) return const [];

      final expanded = expandPathPoints(
        vertices: vertices,
        edges: edges,
        vertexPath: vertexPath,
      );
      for (final point in expanded) {
        addPoint(point);
      }
      addPoint(goalSnap.point);
    }

    if (haversineMeters(
          goalSnap.point.latitude,
          goalSnap.point.longitude,
          goal.latitude,
          goal.longitude,
        ) >
        approachMergeMeters) {
      addPoint(goal);
    }

    if (points.length < 2) {
      addPoint(goalSnap.point);
    }
    if (points.length < 2) {
      addPoint(goal);
    }

    return points;
  }

  List<String> routeToPoi({
    required List<MapVertex> vertices,
    required List<MapEdge> edges,
    required String startVertexId,
    required MapPoi poi,
  }) {
    final startSnap = findNearestPointOnPathNetwork(
      lat: poi.lat,
      lng: poi.lng,
      vertices: vertices,
      edges: edges,
      maxDistanceMeters: AppConstants.poiPathAccessMaxMeters,
    );
    final goalVertexId = startSnap == null
        ? poi.accessVertexId
        : closerPathEndpointId(snap: startSnap, vertices: vertices) ??
            poi.accessVertexId;
    if (goalVertexId == null) return const [];

    return routeBetween(
      vertices: vertices,
      edges: edges,
      startVertexId: startVertexId,
      goalVertexId: goalVertexId,
    );
  }
}
