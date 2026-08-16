import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:event_map/core/routing/routing_service.dart';
import 'package:event_map/data/models/map_edge.dart';
import 'package:event_map/data/models/map_poi.dart';
import 'package:event_map/data/models/map_vertex.dart';

void main() {
  const v1 = MapVertex(id: 'v1', lat: 56.0, lng: 10.0);
  const v2 = MapVertex(id: 'v2', lat: 56.0004, lng: 10.0);
  const v3 = MapVertex(id: 'v3', lat: 56.0008, lng: 10.0);
  const edge = MapEdge(
    id: 'e1',
    fromId: 'v1',
    toId: 'v2',
    geometry: [LatLng(56.0, 10.0), LatLng(56.0004, 10.0)],
    lengthMeters: 44,
  );
  const edge2 = MapEdge(
    id: 'e2',
    fromId: 'v2',
    toId: 'v3',
    geometry: [LatLng(56.0004, 10.0), LatLng(56.0008, 10.0)],
    lengthMeters: 44,
  );
  const poiOnPath = MapPoi(
    id: 'p1',
    name: 'Hus',
    category: 'home',
    lat: 56.0008,
    lng: 10.0,
    accessVertexId: 'v3',
  );

  final routing = RoutingService();

  test('planRouteFromLocation prepends approach leg when user is off path', () {
    final plan = routing.planRouteToPoi(
      lat: 56.0,
      lng: 10.0003,
      vertices: const [v1, v2, v3],
      edges: const [edge, edge2],
      poi: poiOnPath,
    );

    expect(plan, isNotNull);
    expect(plan!.points.first, LatLng(56.0, 10.0003));
    expect(plan.points.last, LatLng(56.0008, 10.0));
    expect(plan.approachMeters, greaterThan(RoutingService.approachMergeMeters));
    expect(plan.points.length, greaterThan(2));
  });

  test('planRouteFromLocation skips approach leg when already on path', () {
    final plan = routing.planRouteToPoi(
      lat: v1.lat,
      lng: v1.lng,
      vertices: const [v1, v2, v3],
      edges: const [edge, edge2],
      poi: poiOnPath,
    );

    expect(plan, isNotNull);
    expect(plan!.approachMeters, 0);
    expect(plan.pathMeters, closeTo(88, 3));
    expect(plan.totalMeters, closeTo(88, 3));
    expect(plan.points.first, LatLng(v1.lat, v1.lng));
  });

  test('planRouteToPoi routes to path point nearest house without access vertex', () {
    const houseOffPath = MapPoi(
      id: 'p2',
      name: 'Hus ved stien',
      category: 'home',
      lat: 56.0008,
      lng: 10.00025,
    );

    final plan = routing.planRouteToPoi(
      lat: 56.0,
      lng: 10.0003,
      vertices: const [v1, v2, v3],
      edges: const [edge, edge2],
      poi: houseOffPath,
    );

    expect(plan, isNotNull);
    expect(plan!.departureMeters, greaterThan(RoutingService.approachMergeMeters));
    expect(plan.points.last, LatLng(houseOffPath.lat, houseOffPath.lng));
    expect(plan.points.length, greaterThan(2));
  });

  test('planRouteToPoi snaps user to nearest path segment between vertices', () {
    final plan = routing.planRouteToPoi(
      lat: 56.0002,
      lng: 10.00025,
      vertices: const [v1, v2, v3],
      edges: const [edge, edge2],
      poi: poiOnPath,
    );

    expect(plan, isNotNull);
    expect(plan!.approachMeters, greaterThan(RoutingService.approachMergeMeters));
    expect(plan.points.first.latitude, closeTo(56.0002, 0.00005));
  });

  test('planRouteToPoi uses POI koblinger for start and destination', () {
    const poiVertex36 = MapVertex(id: 'pv36', lat: 56.0, lng: 10.0003);
    const poiVertex13 = MapVertex(id: 'pv13', lat: 56.0008, lng: 10.0003);
    final spur36 = MapEdge(
      id: 'spur36',
      fromId: 'pv36',
      toId: 'v1',
      geometry: const [LatLng(56.0, 10.0003), LatLng(56.0, 10.0)],
      lengthMeters: 22,
    );
    final spur13 = MapEdge(
      id: 'spur13',
      fromId: 'pv13',
      toId: 'v3',
      geometry: const [LatLng(56.0008, 10.0003), LatLng(56.0008, 10.0)],
      lengthMeters: 22,
    );
    const poi36 = MapPoi(
      id: 'p36',
      name: 'Friland 36',
      category: 'home',
      lat: 56.0,
      lng: 10.0003,
      accessVertexId: 'v1',
    );
    const poi13 = MapPoi(
      id: 'p13',
      name: 'Friland 13',
      category: 'home',
      lat: 56.0008,
      lng: 10.0003,
      accessVertexId: 'v3',
    );

    final plan = routing.planRouteToPoi(
      lat: poi36.lat,
      lng: poi36.lng,
      vertices: const [v1, v2, v3, poiVertex36, poiVertex13],
      edges: [edge, edge2, spur36, spur13],
      poi: poi13,
      pois: const [poi36, poi13],
    );

    expect(plan, isNotNull);
    expect(plan!.points.first, LatLng(poi36.lat, poi36.lng));
    expect(plan.points.last, LatLng(poi13.lat, poi13.lng));
    expect(plan.pathMeters, greaterThan(0));
    expect(plan.departureMeters, greaterThan(RoutingService.approachMergeMeters));
  });

  test('pathLengthMeters uses edge length metadata', () {
    final length = routing.pathLengthMeters(
      vertices: const [v1, v2, v3],
      edges: const [edge, edge2],
      vertexPath: const ['v1', 'v2', 'v3'],
    );

    expect(length, closeTo(88, 0.1));
  });
}
