import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../data/models/map_bounds.dart';

/// Halvgennemsigtigt overlay-billede der kan trækkes og skaleres over kortet.
class MapOverlayAlignmentLayer extends StatefulWidget {
  const MapOverlayAlignmentLayer({
    super.key,
    required this.controller,
    required this.imageBytes,
    required this.bounds,
    required this.onBoundsChanged,
    required this.revision,
    this.opacity = 0.55,
  });

  final MapLibreMapController? controller;
  final Uint8List imageBytes;
  final MapBounds bounds;
  final ValueChanged<MapBounds> onBoundsChanged;
  final int revision;
  final double opacity;

  @override
  State<MapOverlayAlignmentLayer> createState() => _MapOverlayAlignmentLayerState();
}

class _MapOverlayAlignmentLayerState extends State<MapOverlayAlignmentLayer> {
  Rect? _screenRect;
  MapBounds? _gestureStartBounds;
  Offset _gesturePan = Offset.zero;

  @override
  void initState() {
    super.initState();
    _updateGeometry();
  }

  @override
  void didUpdateWidget(MapOverlayAlignmentLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bounds != widget.bounds ||
        oldWidget.controller != widget.controller ||
        oldWidget.revision != widget.revision) {
      _updateGeometry();
    }
  }

  Future<void> _updateGeometry() async {
    final controller = widget.controller;
    if (controller == null || !mounted) return;

    final bounds = widget.bounds;
    final tl = await controller.toScreenLocation(LatLng(bounds.north, bounds.west));
    final tr = await controller.toScreenLocation(LatLng(bounds.north, bounds.east));
    final bl = await controller.toScreenLocation(LatLng(bounds.south, bounds.west));
    final br = await controller.toScreenLocation(LatLng(bounds.south, bounds.east));

    if (!mounted) return;
    setState(() {
      _screenRect = Rect.fromLTRB(
        math.min(tl.x, math.min(tr.x, math.min(bl.x, br.x))).toDouble(),
        math.min(tl.y, math.min(tr.y, math.min(bl.y, br.y))).toDouble(),
        math.max(tl.x, math.max(tr.x, math.max(bl.x, br.x))).toDouble(),
        math.max(tl.y, math.max(tr.y, math.max(bl.y, br.y))).toDouble(),
      );
    });
  }

  Future<({double lat, double lng})> _screenDeltaToGeo(Offset delta) async {
    final controller = widget.controller;
    if (controller == null) return (lat: 0.0, lng: 0.0);

    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return (lat: 0.0, lng: 0.0);

    final center = box.size.center(Offset.zero);
    final a = await controller.toLatLng(math.Point(center.dx, center.dy));
    final b = await controller.toLatLng(
      math.Point(center.dx + delta.dx, center.dy + delta.dy),
    );
    return (lat: b.latitude - a.latitude, lng: b.longitude - a.longitude);
  }

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStartBounds = widget.bounds;
    _gesturePan = Offset.zero;
  }

  Future<void> _onScaleUpdate(ScaleUpdateDetails details) async {
    final start = _gestureStartBounds;
    if (start == null) return;

    _gesturePan += details.focalPointDelta;
    final pan = await _screenDeltaToGeo(_gesturePan);

    var bounds = start.scaledAroundCenter(1 / details.scale);
    bounds = bounds.translated(pan.lat, pan.lng);

    widget.onBoundsChanged(bounds);
    await _updateGeometry();
  }

  void nudgeScale(double factor) {
    widget.onBoundsChanged(widget.bounds.scaledAroundCenter(factor));
    _updateGeometry();
  }

  @override
  Widget build(BuildContext context) {
    final rect = _screenRect;
    if (rect == null || rect.width <= 4 || rect.height <= 4) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return Stack(
      children: [
        Positioned.fromRect(
          rect: rect,
          child: GestureDetector(
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            child: Opacity(
              opacity: widget.opacity,
              child: Image.memory(
                widget.imageBytes,
                fit: BoxFit.fill,
                gaplessPlayback: true,
              ),
            ),
          ),
        ),
        Positioned.fromRect(
          rect: rect,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.primary, width: 2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
