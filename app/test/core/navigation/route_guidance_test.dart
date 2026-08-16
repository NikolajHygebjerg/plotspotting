import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:event_map/core/navigation/route_guidance.dart';

void main() {
  test('buildRouteManeuvers detects a right turn', () {
    final route = [
      const LatLng(56.0, 10.0),
      const LatLng(56.001, 10.0),
      const LatLng(56.001, 10.001),
    ];

    final maneuvers = buildRouteManeuvers(route);
    expect(maneuvers.any((m) => m.kind == ManeuverKind.turnRight), isTrue);
    expect(maneuvers.last.kind, ManeuverKind.arrive);
  });

  test('buildNavigationInstruction returns distance to next turn', () {
    final route = [
      const LatLng(56.0, 10.0),
      const LatLng(56.001, 10.0),
      const LatLng(56.001, 10.001),
    ];
    final maneuvers = buildRouteManeuvers(route);

    final instruction = buildNavigationInstruction(
      route: route,
      maneuvers: maneuvers,
      lat: 56.0,
      lng: 10.0,
    );

    expect(instruction, isNotNull);
    expect(instruction!.primaryText, contains('m'));
    expect(instruction.secondaryText, isNotEmpty);
  });

  test('buildNavigationInstruction shows remaining distance when already on path', () {
    final route = [
      const LatLng(56.0, 10.0),
      const LatLng(56.001, 10.0),
      const LatLng(56.002, 10.0),
    ];
    final maneuvers = buildRouteManeuvers(route);

    final instruction = buildNavigationInstruction(
      route: route,
      maneuvers: maneuvers,
      lat: 56.0005,
      lng: 10.0,
    );

    expect(instruction, isNotNull);
    expect(instruction!.distanceMeters, greaterThan(0));
  });
}
