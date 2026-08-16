import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../core/constants.dart';
import '../core/geo/geo_utils.dart';

/// Blå rute-prikker i faste skærm-pixels oven på illustreret kort.
class RouteDotsOverlay extends StatefulWidget {
  const RouteDotsOverlay({
    super.key,
    required this.controller,
    required this.routePoints,
  });

  final MapLibreMapController controller;
  final List<ll.LatLng> routePoints;

  @override
  State<RouteDotsOverlay> createState() => RouteDotsOverlayState();
}

class RouteDotsOverlayState extends State<RouteDotsOverlay> {
  List<Offset> _positions = const [];
  var _updateToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => updatePositions());
  }

  @override
  void didUpdateWidget(covariant RouteDotsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.routePoints != widget.routePoints) {
      updatePositions();
    }
  }

  Future<void> updatePositions() async {
    if (!mounted || widget.routePoints.length < 2) {
      if (_positions.isNotEmpty) {
        setState(() => _positions = const []);
      }
      return;
    }

    final token = ++_updateToken;
    final samples = samplePointsAlongPolyline(
      widget.routePoints,
      intervalMeters: AppConstants.routeDotIntervalMeters,
    );

    try {
      final points = await widget.controller.toScreenLocationBatch(
        samples.map((point) => LatLng(point.latitude, point.longitude)),
      );
      if (!mounted || token != _updateToken) return;
      setState(() {
        _positions = points
            .map((point) => Offset(point.x.toDouble(), point.y.toDouble()))
            .toList();
      });
    } on Object {
      // Kortet kan være midt i reload.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_positions.isEmpty) {
      return const SizedBox.expand();
    }

    return CustomPaint(
      painter: _RouteDotsPainter(_positions),
      size: Size.infinite,
    );
  }
}

class _RouteDotsPainter extends CustomPainter {
  _RouteDotsPainter(this.positions);

  final List<Offset> positions;

  static const _dotSize = AppConstants.routeDotScreenSize;
  static const _half = _dotSize / 2;
  static const _fill = Color(0xFF4285F4);

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()..color = _fill;
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final position in positions) {
      final center = Offset(position.dx, position.dy);
      canvas.drawCircle(center, _half, fillPaint);
      canvas.drawCircle(center, _half - 0.5, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RouteDotsPainter oldDelegate) {
    return oldDelegate.positions != positions;
  }
}
