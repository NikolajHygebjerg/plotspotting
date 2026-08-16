import 'map_edge.dart';
import 'map_vertex.dart';

/// Jagt-specifikke stier gemmes i metadata og bruges kun i skattejagt.
class TreasureHuntPathNetwork {
  const TreasureHuntPathNetwork({
    this.vertices = const [],
    this.edges = const [],
  });

  final List<MapVertex> vertices;
  final List<MapEdge> edges;

  bool get isEmpty => vertices.isEmpty && edges.isEmpty;

  TreasureHuntPathNetwork copyWith({
    List<MapVertex>? vertices,
    List<MapEdge>? edges,
  }) {
    return TreasureHuntPathNetwork(
      vertices: vertices ?? this.vertices,
      edges: edges ?? this.edges,
    );
  }

  Map<String, dynamic> toJson() => {
        if (vertices.isNotEmpty)
          'vertices': vertices.map((vertex) => vertex.toJson()).toList(),
        if (edges.isNotEmpty)
          'edges': edges.map((edge) => edge.toJson()).toList(),
      };

  factory TreasureHuntPathNetwork.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) {
      return const TreasureHuntPathNetwork();
    }
    return TreasureHuntPathNetwork(
      vertices: (json['vertices'] as List? ?? const [])
          .map((item) => MapVertex.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
      edges: (json['edges'] as List? ?? const [])
          .map((item) => MapEdge.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
    );
  }
}
