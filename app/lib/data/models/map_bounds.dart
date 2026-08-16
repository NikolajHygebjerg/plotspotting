import 'dart:math' as math;

import 'package:maplibre_gl/maplibre_gl.dart';

/// Geographic bounding box for illustrated basemap georeferencing.
class MapBounds {
  const MapBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;

  bool get isValid =>
      south < north && west < east && south.abs() <= 90 && north.abs() <= 90;

  double get centerLat => (south + north) / 2;

  double get centerLng => (east + west) / 2;

  MapBounds translated(double dLat, double dLng) => MapBounds(
        south: south + dLat,
        north: north + dLat,
        west: west + dLng,
        east: east + dLng,
      );

  /// [factor] > 1 giver et større geografisk udsnit (billedet fylder mindre).
  MapBounds scaledAroundCenter(double factor) {
    final latHalf = (north - south) / 2 * factor;
    final lngHalf = (east - west) / 2 * factor;
    return MapBounds(
      south: centerLat - latHalf,
      north: centerLat + latHalf,
      west: centerLng - lngHalf,
      east: centerLng + lngHalf,
    );
  }

  /// Udvider dette udsnit så det dækker [other] (typisk større gæste-område).
  MapBounds encompassing(MapBounds other) {
    return MapBounds(
      south: math.min(south, other.south),
      west: math.min(west, other.west),
      north: math.max(north, other.north),
      east: math.max(east, other.east),
    );
  }

  /// Bevarer midten og justerer højde efter billedets proportioner.
  static MapBounds fitImageAspect(MapBounds bounds, double imageAspect) {
    final lngSpan = bounds.east - bounds.west;
    final latPerLng = math.cos(bounds.centerLat * math.pi / 180);
    final latSpan = lngSpan * latPerLng / imageAspect;
    return MapBounds(
      south: bounds.centerLat - latSpan / 2,
      north: bounds.centerLat + latSpan / 2,
      west: bounds.centerLng - lngSpan / 2,
      east: bounds.centerLng + lngSpan / 2,
    );
  }

  LatLngQuad toLatLngQuad() {
    return LatLngQuad(
      topLeft: LatLng(north, west),
      topRight: LatLng(north, east),
      bottomRight: LatLng(south, east),
      bottomLeft: LatLng(south, west),
    );
  }

  LatLngBounds toLatLngBounds() {
    return LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );
  }

  CameraTargetBounds toCameraTargetBounds() {
    return CameraTargetBounds(toLatLngBounds());
  }

  /// Rough zoom level so the whole area is visible before the map animates to fit.
  double estimateInitialZoom() {
    final latSpan = (north - south).abs();
    final lngSpan = (east - west).abs();
    final span = math.max(latSpan, lngSpan);
    if (span <= 0) return 16;
    final zoom = math.log(360 / span) / math.ln2 - 1.2;
    return zoom.clamp(10.0, 18.0);
  }

  factory MapBounds.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const MapBounds(south: 0, west: 0, north: 0, east: 0);
    }
    return MapBounds(
      south: (json['south'] as num?)?.toDouble() ?? 0,
      west: (json['west'] as num?)?.toDouble() ?? 0,
      north: (json['north'] as num?)?.toDouble() ?? 0,
      east: (json['east'] as num?)?.toDouble() ?? 0,
    );
  }

  factory MapBounds.fromEventMeta({
    double? south,
    double? west,
    double? north,
    double? east,
  }) {
    if (south == null || west == null || north == null || east == null) {
      return const MapBounds(south: 0, west: 0, north: 0, east: 0);
    }
    return MapBounds(south: south, west: west, north: north, east: east);
  }

  Map<String, dynamic> toJson() => {
        'south': south,
        'west': west,
        'north': north,
        'east': east,
      };
}
