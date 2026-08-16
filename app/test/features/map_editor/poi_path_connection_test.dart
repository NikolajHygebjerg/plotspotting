import 'package:event_map/features/map_editor/poi_path_connection.dart';
import 'package:event_map/data/models/map_edge.dart';
import 'package:event_map/data/models/map_poi.dart';
import 'package:event_map/data/models/map_vertex.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('planAllPoiPathConnections', () {
    test('foreslår tilkobling til nærmeste sti', () {
      const v1 = MapVertex(id: 'v1', lat: 56.0, lng: 10.0);
      const v2 = MapVertex(id: 'v2', lat: 56.001, lng: 10.0);
      final edge = MapEdge(
        id: 'e1',
        fromId: 'v1',
        toId: 'v2',
        geometry: const [LatLng(56.0, 10.0), LatLng(56.001, 10.0)],
        lengthMeters: 111,
      );
      const poi = MapPoi(
        id: 'p1',
        name: 'Hytten',
        category: 'home',
        lat: 56.0005,
        lng: 10.0002,
      );

      final plan = planAllPoiPathConnections(
        pois: const [poi],
        vertices: const [v1, v2],
        edges: [edge],
      );

      expect(plan.connectableCount, 1);
      expect(plan.skippedCount, 0);
      expect(plan.proposals.single.poi.id, 'p1');
      expect(plan.proposals.single.distanceMeters, lessThan(50));
    });

    test('markerer steder uden for rækkevidde', () {
      const v1 = MapVertex(id: 'v1', lat: 56.0, lng: 10.0);
      const v2 = MapVertex(id: 'v2', lat: 56.001, lng: 10.0);
      final edge = MapEdge(
        id: 'e1',
        fromId: 'v1',
        toId: 'v2',
        geometry: const [LatLng(56.0, 10.0), LatLng(56.001, 10.0)],
        lengthMeters: 111,
      );
      const poi = MapPoi(
        id: 'p1',
        name: 'Langt væk',
        category: 'home',
        lat: 56.02,
        lng: 10.02,
      );

      final plan = planAllPoiPathConnections(
        pois: const [poi],
        vertices: const [v1, v2],
        edges: [edge],
      );

      expect(plan.connectableCount, 0);
      expect(plan.skippedCount, 1);
      expect(plan.outOfRange.single.id, 'p1');
    });
  });

  group('applyBulkPoiPathConnectionPlan', () {
    test('sætter accessVertexId og tegner sti fra sted til rute', () {
      const v1 = MapVertex(id: 'v1', lat: 56.0, lng: 10.0);
      const v2 = MapVertex(id: 'v2', lat: 56.001, lng: 10.0);
      final edge = MapEdge(
        id: 'e1',
        fromId: 'v1',
        toId: 'v2',
        geometry: const [LatLng(56.0, 10.0), LatLng(56.001, 10.0)],
        lengthMeters: 111,
      );
      const poi = MapPoi(
        id: 'p1',
        name: 'Hytten',
        category: 'home',
        lat: 56.0005,
        lng: 10.0005,
      );

      final plan = planAllPoiPathConnections(
        pois: const [poi],
        vertices: const [v1, v2],
        edges: [edge],
      );

      final result = applyBulkPoiPathConnectionPlan(
        plan: plan,
        pois: const [poi],
        vertices: const [v1, v2],
        edges: [edge],
      );

      expect(result.pois.single.accessVertexId, isNotNull);
      expect(result.vertices.length, greaterThan(2));
      expect(result.edges.length, greaterThan(1));
    });
  });

  group('official path only', () {
    test('ignorerer stikoblinger til andre steder', () {
      const v1 = MapVertex(id: 'v1', lat: 56.0, lng: 10.0);
      const v2 = MapVertex(id: 'v2', lat: 56.001, lng: 10.0);
      const poiAVertex = MapVertex(id: 'pa', lat: 56.0003, lng: 10.0003);
      final mainEdge = MapEdge(
        id: 'main',
        fromId: 'v1',
        toId: 'v2',
        geometry: const [LatLng(56.0, 10.0), LatLng(56.001, 10.0)],
        lengthMeters: 111,
      );
      final spurA = MapEdge(
        id: 'spur-a',
        fromId: 'pa',
        toId: 'v1',
        geometry: const [LatLng(56.0003, 10.0003), LatLng(56.0, 10.0)],
        lengthMeters: 33,
      );
      const poiA = MapPoi(
        id: 'a',
        name: 'Hus A',
        category: 'home',
        lat: 56.0003,
        lng: 10.0003,
        accessVertexId: 'v1',
      );
      const poiB = MapPoi(
        id: 'b',
        name: 'Hus B',
        category: 'home',
        lat: 56.00025,
        lng: 10.00025,
      );

      final snap = suggestPoiPathConnection(
        poi: poiB,
        vertices: const [v1, v2, poiAVertex],
        edges: [mainEdge, spurA],
        pois: const [poiA, poiB],
      );

      expect(snap, isNotNull);
      expect(snap!.edgeFromId, 'v1');
      expect(snap.edgeToId, 'v2');
    });
  });

  group('clearPoiConnection', () {
    test('fjerner stikobling og nulstiller accessVertexId', () {
      const v1 = MapVertex(id: 'v1', lat: 56.0, lng: 10.0);
      const v2 = MapVertex(id: 'v2', lat: 56.001, lng: 10.0);
      const poiVertex = MapVertex(id: 'pv1', lat: 56.0005, lng: 10.0005);
      final mainEdge = MapEdge(
        id: 'e1',
        fromId: 'v1',
        toId: 'v2',
        geometry: const [LatLng(56.0, 10.0), LatLng(56.001, 10.0)],
        lengthMeters: 111,
      );
      final spurEdge = MapEdge(
        id: 'e2',
        fromId: 'pv1',
        toId: 'v1',
        geometry: const [LatLng(56.0005, 10.0005), LatLng(56.0, 10.0)],
        lengthMeters: 55,
      );
      const poi = MapPoi(
        id: 'p1',
        name: 'Hytten',
        category: 'home',
        lat: 56.0005,
        lng: 10.0005,
        accessVertexId: 'v1',
      );

      final cleared = clearPoiConnection(
        poi: poi,
        vertices: const [v1, v2, poiVertex],
        edges: [mainEdge, spurEdge],
      );

      expect(cleared.poi.accessVertexId, isNull);
      expect(cleared.edges, [mainEdge]);
      expect(cleared.vertices.any((vertex) => vertex.id == 'pv1'), isFalse);
    });
  });

  group('repairBrokenPoiConnections', () {
    test('rydder accessVertexId når stikobling mangler', () {
      const poi = MapPoi(
        id: 'p1',
        name: 'Hytten',
        category: 'home',
        lat: 56.0005,
        lng: 10.0005,
        accessVertexId: 'v1',
      );

      final repaired = repairBrokenPoiConnections(
        pois: const [poi],
        vertices: const [
          MapVertex(id: 'v1', lat: 56.0, lng: 10.0),
        ],
        edges: const [],
      );

      expect(repaired.single.accessVertexId, isNull);
    });
  });
}
