import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';

enum UserLocationDisplayMode {
  /// Lille blå prik med retnings-"tåge" (Google Maps uden navigation).
  exploring,

  /// Blå pil i telefonens retning (Google Maps under vejvisning).
  navigating,
}

/// Brugerens placering som Flutter-overlay — virker på web og mobil.
class UserLocationOverlay extends StatefulWidget {
  const UserLocationOverlay({
    super.key,
    required this.controller,
    required this.location,
    this.heading,
    this.mode = UserLocationDisplayMode.exploring,
  });

  final MapLibreMapController controller;
  final ll.LatLng? location;
  final double? heading;
  final UserLocationDisplayMode mode;

  @override
  State<UserLocationOverlay> createState() => UserLocationOverlayState();
}

class UserLocationOverlayState extends State<UserLocationOverlay> {
  Offset? _position;
  double _mapBearing = 0;
  var _updateToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => updatePosition());
  }

  @override
  void didUpdateWidget(covariant UserLocationOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location ||
        oldWidget.heading != widget.heading ||
        oldWidget.mode != widget.mode) {
      updatePosition();
    }
  }

  Future<void> updatePosition() async {
    final location = widget.location;
    if (!mounted || location == null) {
      if (_position != null) {
        setState(() => _position = null);
      }
      return;
    }

    final token = ++_updateToken;
    try {
      final screenPoint = await widget.controller.toScreenLocation(
        LatLng(location.latitude, location.longitude),
      );
      if (!mounted || token != _updateToken) return;
      setState(() {
        _position = Offset(screenPoint.x.toDouble(), screenPoint.y.toDouble());
        _mapBearing = widget.controller.cameraPosition?.bearing ?? 0;
      });
    } on Object {
      if (!mounted || token != _updateToken) return;
      Future<void>.delayed(const Duration(milliseconds: 250), () {
        if (mounted && token == _updateToken) {
          updatePosition();
        }
      });
    }
  }

  double? get _screenHeading {
    final heading = widget.heading;
    if (heading == null || heading < 0) return null;
    return (heading - _mapBearing) * math.pi / 180;
  }

  @override
  Widget build(BuildContext context) {
    final position = _position;
    if (position == null) {
      return const SizedBox.expand();
    }

    return IgnorePointer(
      child: CustomPaint(
        painter: _UserLocationPainter(
          position: position,
          screenHeading: _screenHeading,
          mode: widget.mode,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _UserLocationPainter extends CustomPainter {
  _UserLocationPainter({
    required this.position,
    required this.screenHeading,
    required this.mode,
  });

  final Offset position;
  final double? screenHeading;
  final UserLocationDisplayMode mode;

  static const _blue = Color(0xFF4285F4);
  static const _dotRadius = 7.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (mode == UserLocationDisplayMode.navigating) {
      _paintNavigationArrow(canvas);
      return;
    }
    _paintExploringDot(canvas);
  }

  void _paintExploringDot(Canvas canvas) {
    if (screenHeading != null) {
      _paintHeadingCone(canvas, spreadRadians: 0.55, length: 42);
    }

    final fillPaint = Paint()..color = _blue;
    final ringPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    canvas.drawCircle(position, _dotRadius + 1.5, Paint()..color = Colors.black.withValues(alpha: 0.18));
    canvas.drawCircle(position, _dotRadius, fillPaint);
    canvas.drawCircle(position, _dotRadius - 0.5, ringPaint);
  }

  void _paintNavigationArrow(Canvas canvas) {
    if (screenHeading == null) {
      _paintExploringDot(canvas);
      return;
    }
    canvas.save();
    canvas.translate(position.dx, position.dy);
    if (screenHeading != null) {
      canvas.rotate(screenHeading!);
    }

    const arrowHeight = 28.0;
    const arrowWidth = 20.0;

    final path = Path()
      ..moveTo(0, -arrowHeight * 0.55)
      ..lineTo(arrowWidth * 0.42, arrowHeight * 0.18)
      ..quadraticBezierTo(
        arrowWidth * 0.18,
        arrowHeight * 0.34,
        0,
        arrowHeight * 0.28,
      )
      ..quadraticBezierTo(
        -arrowWidth * 0.18,
        arrowHeight * 0.34,
        -arrowWidth * 0.42,
        arrowHeight * 0.18,
      )
      ..close();

    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.25), 3, false);

    final fillPaint = Paint()..color = _blue;
    final strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, strokePaint);

    canvas.restore();
  }

  void _paintHeadingCone(Canvas canvas, {required double spreadRadians, required double length}) {
    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(screenHeading!);

    final conePath = Path();
    conePath.moveTo(0, 0);
    conePath.arcTo(
      Rect.fromCircle(center: Offset.zero, radius: length),
      -spreadRadians / 2 - math.pi / 2,
      spreadRadians,
      false,
    );
    conePath.close();

    final gradient = ui.Gradient.radial(
      Offset.zero,
      length,
      [
        _blue.withValues(alpha: 0.38),
        _blue.withValues(alpha: 0.12),
        _blue.withValues(alpha: 0),
      ],
      [0, 0.45, 1],
    );

    canvas.drawPath(
      conePath,
      Paint()
        ..shader = gradient
        ..style = PaintingStyle.fill,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _UserLocationPainter oldDelegate) {
    return oldDelegate.position != position ||
        oldDelegate.screenHeading != screenHeading ||
        oldDelegate.mode != mode;
  }
}
