import 'dart:math' as math;

/// Path network graph for A* routing on organizer-drawn trails.
class GraphVertex {
  const GraphVertex({
    required this.id,
    required this.lat,
    required this.lng,
    this.isEntrance = false,
  });

  final String id;
  final double lat;
  final double lng;
  final bool isEntrance;
}

class GraphEdge {
  const GraphEdge({
    required this.id,
    required this.fromId,
    required this.toId,
    required this.lengthMeters,
    this.bidirectional = true,
  });

  final String id;
  final String fromId;
  final String toId;
  final double lengthMeters;
  final bool bidirectional;
}

class PathGraph {
  PathGraph({
    required this.vertices,
    required this.edges,
  });

  final Map<String, GraphVertex> vertices;
  final List<GraphEdge> edges;

  /// Returns ordered vertex ids from [startId] to [goalId], or empty if unreachable.
  List<String> shortestPath(String startId, String goalId) {
    if (!vertices.containsKey(startId) || !vertices.containsKey(goalId)) {
      return const [];
    }
    if (startId == goalId) return [startId];

    final adjacency = <String, List<(String neighbor, double weight)>>{};
    for (final edge in edges) {
      adjacency.putIfAbsent(edge.fromId, () => []).add(
            (edge.toId, edge.lengthMeters),
          );
      if (edge.bidirectional) {
        adjacency.putIfAbsent(edge.toId, () => []).add(
              (edge.fromId, edge.lengthMeters),
            );
      }
    }

    final open = <String>{startId};
    final cameFrom = <String, String>{};
    final gScore = {for (final id in vertices.keys) id: double.infinity};
    gScore[startId] = 0;

    double heuristic(String a, String b) {
      final va = vertices[a]!;
      final vb = vertices[b]!;
      return _haversineMeters(va.lat, va.lng, vb.lat, vb.lng);
    }

    final fScore = {for (final id in vertices.keys) id: double.infinity};
    fScore[startId] = heuristic(startId, goalId);

    while (open.isNotEmpty) {
      final current = open.reduce(
        (a, b) => (fScore[a] ?? double.infinity) <= (fScore[b] ?? double.infinity) ? a : b,
      );

      if (current == goalId) {
        return _reconstruct(cameFrom, current);
      }

      open.remove(current);

      for (final entry in adjacency[current] ?? const []) {
        final neighbor = entry.$1;
        final weight = entry.$2;
        final tentative = (gScore[current] ?? double.infinity) + weight;
        if (tentative < (gScore[neighbor] ?? double.infinity)) {
          cameFrom[neighbor] = current;
          gScore[neighbor] = tentative;
          fScore[neighbor] = tentative + heuristic(neighbor, goalId);
          open.add(neighbor);
        }
      }
    }

    return const [];
  }

  List<String> _reconstruct(Map<String, String> cameFrom, String current) {
    final path = [current];
    while (cameFrom.containsKey(current)) {
      current = cameFrom[current]!;
      path.insert(0, current);
    }
    return path;
  }
}

double _haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadius = 6371000.0;
  final dLat = _toRad(lat2 - lat1);
  final dLng = _toRad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_toRad(lat1)) * math.cos(_toRad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _toRad(double deg) => deg * math.pi / 180;
