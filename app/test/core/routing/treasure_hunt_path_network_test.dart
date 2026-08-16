import 'package:flutter_test/flutter_test.dart';

import 'package:event_map/core/routing/treasure_hunt_path_network.dart';
import 'package:event_map/data/models/event_map_data.dart';
import 'package:event_map/data/models/map_edge.dart';
import 'package:event_map/data/models/map_vertex.dart';
import 'package:event_map/data/models/treasure_hunt.dart';
import 'package:event_map/data/models/treasure_hunt_path_network.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('routing network merges official and hunt paths', () {
    const officialVertex = MapVertex(id: 'v1', lat: 56.0, lng: 10.0);
    const huntVertex = MapVertex(id: 'hv1', lat: 56.001, lng: 10.001);
    const officialEdge = MapEdge(
      id: 'e1',
      fromId: 'v1',
      toId: 'v1',
      geometry: [LatLng(56.0, 10.0), LatLng(56.0005, 10.0)],
      lengthMeters: 55,
    );
    const huntEdge = MapEdge(
      id: 'he1',
      fromId: 'v1',
      toId: 'hv1',
      geometry: [LatLng(56.0, 10.0), LatLng(56.001, 10.001)],
      lengthMeters: 120,
    );

    final data = EventMapData(
      event: const EventMeta(id: 'event', name: 'Test'),
      vertices: const [officialVertex],
      edges: const [officialEdge],
    );
    const hunt = TreasureHuntConfig(
      id: 'h1',
      pathNetwork: TreasureHuntPathNetwork(
        vertices: [huntVertex],
        edges: [huntEdge],
      ),
    );

    final network = TreasureHuntRoutingNetwork.fromEvent(data: data, hunt: hunt);
    expect(network.vertices.length, 2);
    expect(network.edges.length, 2);
    expect(network.huntEdges.length, 1);
  });

  test('addTreasureHuntPathPoint snaps to official vertices', () {
    const officialVertex = MapVertex(id: 'v1', lat: 56.0, lng: 10.0);
    const state = TreasureHuntPathDrawState(vertices: [], edges: []);

    final next = addTreasureHuntPathPoint(
      state: state,
      lat: 56.0,
      lng: 10.0,
      officialVertices: const [officialVertex],
      newVertexId: () => 'hv-new',
      newEdgeId: () => 'he-new',
    );

    expect(next.lastVertexId, 'v1');
    expect(next.vertices, isEmpty);
  });
}
