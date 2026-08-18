import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/constants.dart';
import '../../../core/geo/geo_utils.dart';

/// Transparent overlay der optager træk-be vægelser og konverterer dem til stipunkter.
class MapFreehandDrawLayer extends StatefulWidget {
  const MapFreehandDrawLayer({
    super.key,
    required this.controller,
    required this.onDrawPoint,
    this.minStepMeters = AppConstants.freehandMinStepMeters,
  });

  final MapLibreMapController controller;
  final void Function(LatLng coordinate) onDrawPoint;
  final double minStepMeters;

  @override
  State<MapFreehandDrawLayer> createState() => _MapFreehandDrawLayerState();
}

class _MapFreehandDrawLayerState extends State<MapFreehandDrawLayer> {
  bool _drawing = false;
  double? _lastLat;
  double? _lastLng;

  Future<void> _addPoint(Offset localPosition) async {
    final latLng = await widget.controller.toLatLng(
      math.Point(localPosition.dx, localPosition.dy),
    );

    if (_lastLat != null && _lastLng != null) {
      final distance = haversineMeters(
        latLng.latitude,
        latLng.longitude,
        _lastLat!,
        _lastLng!,
      );
      if (distance < widget.minStepMeters) return;
    }

    _lastLat = latLng.latitude;
    _lastLng = latLng.longitude;
    widget.onDrawPoint(latLng);
  }

  void _startStroke(PointerDownEvent event) {
    _drawing = true;
    _lastLat = null;
    _lastLng = null;
    _addPoint(event.localPosition);
  }

  void _continueStroke(PointerMoveEvent event) {
    if (!_drawing) return;
    _addPoint(event.localPosition);
  }

  void _endStroke() {
    _drawing = false;
    _lastLat = null;
    _lastLng = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _startStroke,
      onPointerMove: _continueStroke,
      onPointerUp: (_) => _endStroke(),
      onPointerCancel: (_) => _endStroke(),
      child: const SizedBox.expand(),
    );
  }
}
