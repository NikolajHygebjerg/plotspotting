import 'package:event_map/core/routing/graph.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shortestPath finds route through bidirectional edges', () {
    final graph = PathGraph(
      vertices: {
        'a': const GraphVertex(id: 'a', lat: 55.0, lng: 12.0),
        'b': const GraphVertex(id: 'b', lat: 55.001, lng: 12.0),
        'c': const GraphVertex(id: 'c', lat: 55.002, lng: 12.0),
      },
      edges: [
        const GraphEdge(id: 'e1', fromId: 'a', toId: 'b', lengthMeters: 100),
        const GraphEdge(id: 'e2', fromId: 'b', toId: 'c', lengthMeters: 100),
      ],
    );

    expect(graph.shortestPath('a', 'c'), ['a', 'b', 'c']);
  });

  test('shortestPath returns empty when unreachable', () {
    final graph = PathGraph(
      vertices: {
        'a': const GraphVertex(id: 'a', lat: 55.0, lng: 12.0),
        'b': const GraphVertex(id: 'b', lat: 55.001, lng: 12.0),
      },
      edges: const [],
    );

    expect(graph.shortestPath('a', 'b'), isEmpty);
  });
}
