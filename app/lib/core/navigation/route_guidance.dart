import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

enum ManeuverKind {
  depart,
  continueStraight,
  turnSlightLeft,
  turnLeft,
  turnSharpLeft,
  turnSlightRight,
  turnRight,
  turnSharpRight,
  arrive,
}

class RouteManeuver {
  const RouteManeuver({
    required this.kind,
    required this.location,
    required this.routeIndex,
    required this.distanceAlongRoute,
  });

  final ManeuverKind kind;
  final LatLng location;
  final int routeIndex;
  final double distanceAlongRoute;
}

class NavigationInstruction {
  const NavigationInstruction({
    required this.distanceMeters,
    required this.primaryText,
    required this.secondaryText,
    required this.kind,
    required this.mapBearing,
  });

  final double distanceMeters;
  final String primaryText;
  final String secondaryText;
  final ManeuverKind kind;
  final double mapBearing;
}

double bearingDegrees(LatLng from, LatLng to) {
  final lat1 = from.latitude * math.pi / 180;
  final lat2 = to.latitude * math.pi / 180;
  final dLng = (to.longitude - from.longitude) * math.pi / 180;
  final y = math.sin(dLng) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

double normalizeSignedDegrees(double degrees) {
  var value = degrees % 360;
  if (value > 180) value -= 360;
  if (value < -180) value += 360;
  return value;
}

ManeuverKind classifyTurn(double deltaDegrees) {
  final delta = normalizeSignedDegrees(deltaDegrees);
  final abs = delta.abs();
  if (abs < 25) return ManeuverKind.continueStraight;
  if (delta > 0) {
    if (abs < 60) return ManeuverKind.turnSlightRight;
    if (abs < 120) return ManeuverKind.turnRight;
    return ManeuverKind.turnSharpRight;
  }
  if (abs < 60) return ManeuverKind.turnSlightLeft;
  if (abs < 120) return ManeuverKind.turnLeft;
  return ManeuverKind.turnSharpLeft;
}

String maneuverLabel(ManeuverKind kind) {
  return switch (kind) {
    ManeuverKind.depart => 'Start ruten',
    ManeuverKind.continueStraight => 'Fortsæt ligeud',
    ManeuverKind.turnSlightLeft => 'Drej let til venstre',
    ManeuverKind.turnLeft => 'Drej til venstre',
    ManeuverKind.turnSharpLeft => 'Drej skarpt til venstre',
    ManeuverKind.turnSlightRight => 'Drej let til højre',
    ManeuverKind.turnRight => 'Drej til højre',
    ManeuverKind.turnSharpRight => 'Drej skarpt til højre',
    ManeuverKind.arrive => 'Du er fremme',
  };
}

List<RouteManeuver> buildRouteManeuvers(List<LatLng> route) {
  if (route.isEmpty) return const [];
  if (route.length == 1) {
    return [
      RouteManeuver(
        kind: ManeuverKind.arrive,
        location: route.first,
        routeIndex: 0,
        distanceAlongRoute: 0,
      ),
    ];
  }

  final maneuvers = <RouteManeuver>[
    RouteManeuver(
      kind: ManeuverKind.depart,
      location: route.first,
      routeIndex: 0,
      distanceAlongRoute: 0,
    ),
  ];

  var traversed = 0.0;
  for (var index = 1; index < route.length - 1; index++) {
    traversed += _segmentLength(route[index - 1], route[index]);
    final bearingIn = bearingDegrees(route[index - 1], route[index]);
    final bearingOut = bearingDegrees(route[index], route[index + 1]);
    final kind = classifyTurn(bearingOut - bearingIn);
    if (kind == ManeuverKind.continueStraight) continue;
    maneuvers.add(
      RouteManeuver(
        kind: kind,
        location: route[index],
        routeIndex: index,
        distanceAlongRoute: traversed,
      ),
    );
  }

  final total = polylineLength(route);
  maneuvers.add(
    RouteManeuver(
      kind: ManeuverKind.arrive,
      location: route.last,
      routeIndex: route.length - 1,
      distanceAlongRoute: total,
    ),
  );
  return maneuvers;
}

double polylineLength(List<LatLng> points) {
  if (points.length < 2) return 0;
  var total = 0.0;
  for (var i = 0; i < points.length - 1; i++) {
    total += _segmentLength(points[i], points[i + 1]);
  }
  return total;
}

double _segmentLength(LatLng a, LatLng b) {
  const distance = Distance();
  return distance(a, b);
}

class RouteProgress {
  const RouteProgress({
    required this.segmentIndex,
    required this.distanceAlongRoute,
    required this.distanceToRouteMeters,
  });

  final int segmentIndex;
  final double distanceAlongRoute;
  final double distanceToRouteMeters;
}

RouteProgress projectOntoRoute({
  required List<LatLng> route,
  required double lat,
  required double lng,
}) {
  if (route.isEmpty) {
    return const RouteProgress(
      segmentIndex: 0,
      distanceAlongRoute: 0,
      distanceToRouteMeters: double.infinity,
    );
  }
  if (route.length == 1) {
    return RouteProgress(
      segmentIndex: 0,
      distanceAlongRoute: 0,
      distanceToRouteMeters: _segmentLength(route.first, LatLng(lat, lng)),
    );
  }

  var bestDistance = double.infinity;
  var bestAlong = 0.0;
  var bestSegment = 0;
  var traversed = 0.0;

  for (var i = 0; i < route.length - 1; i++) {
    final start = route[i];
    final end = route[i + 1];
    final segmentLength = _segmentLength(start, end);
    final projection = _projectPointOnSegment(
      point: LatLng(lat, lng),
      start: start,
      end: end,
    );
    if (projection.distanceMeters < bestDistance) {
      bestDistance = projection.distanceMeters;
      bestAlong = traversed + projection.alongMeters;
      bestSegment = i;
    }
    traversed += segmentLength;
  }

  return RouteProgress(
    segmentIndex: bestSegment,
    distanceAlongRoute: bestAlong,
    distanceToRouteMeters: bestDistance,
  );
}

class _SegmentProjection {
  const _SegmentProjection({
    required this.alongMeters,
    required this.distanceMeters,
  });

  final double alongMeters;
  final double distanceMeters;
}

_SegmentProjection _projectPointOnSegment({
  required LatLng point,
  required LatLng start,
  required LatLng end,
}) {
  final segmentLength = _segmentLength(start, end);
  if (segmentLength <= 0) {
    return _SegmentProjection(
      alongMeters: 0,
      distanceMeters: _segmentLength(start, point),
    );
  }

  final dx = end.longitude - start.longitude;
  final dy = end.latitude - start.latitude;
  final px = point.longitude - start.longitude;
  final py = point.latitude - start.latitude;
  final denom = dx * dx + dy * dy;
  final t = denom == 0 ? 0 : ((px * dx + py * dy) / denom).clamp(0.0, 1.0);
  final projected = LatLng(
    start.latitude + dy * t,
    start.longitude + dx * t,
  );
  return _SegmentProjection(
    alongMeters: segmentLength * t,
    distanceMeters: _segmentLength(projected, point),
  );
}

NavigationInstruction? buildNavigationInstruction({
  required List<LatLng> route,
  required List<RouteManeuver> maneuvers,
  required double lat,
  required double lng,
  double? userHeading,
}) {
  if (route.length < 2 || maneuvers.isEmpty) return null;

  final progress = projectOntoRoute(route: route, lat: lat, lng: lng);
  RouteManeuver? nextManeuver;
  for (final maneuver in maneuvers) {
    if (maneuver.distanceAlongRoute + 8 >= progress.distanceAlongRoute) {
      nextManeuver = maneuver;
      break;
    }
  }
  nextManeuver ??= maneuvers.last;

  final remaining = math.max(
    0.0,
    nextManeuver.distanceAlongRoute - progress.distanceAlongRoute,
  );
  var distance = (nextManeuver.kind == ManeuverKind.arrive &&
          progress.distanceAlongRoute >= nextManeuver.distanceAlongRoute - 12
      ? 0.0
      : remaining);

  if (distance <= 0 &&
      nextManeuver.kind == ManeuverKind.depart &&
      maneuvers.length > 1) {
    final totalRemaining =
        polylineLength(route) - progress.distanceAlongRoute;
    if (totalRemaining > 0) {
      distance = totalRemaining;
    }
  }

  final lookAheadIndex = math.min(
    nextManeuver.routeIndex + 1,
    route.length - 1,
  );
  final lookAhead = route[lookAheadIndex];
  final mapBearing = userHeading != null && userHeading >= 0
      ? userHeading
      : bearingDegrees(LatLng(lat, lng), lookAhead);

  final primaryText = nextManeuver.kind == ManeuverKind.arrive && distance <= 0
      ? 'Fremme'
      : '${distance.round()} m';
  final secondaryText = maneuverLabel(nextManeuver.kind);

  return NavigationInstruction(
    distanceMeters: distance,
    primaryText: primaryText,
    secondaryText: secondaryText,
    kind: nextManeuver.kind,
    mapBearing: mapBearing,
  );
}
