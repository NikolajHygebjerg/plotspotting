import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../data/models/map_poi.dart';

/// Synlige, trykbare POI-markører oven på illustreret kort (MapLibre-annotations
/// kan ligge under billedlaget).
class PoiMapOverlay extends StatefulWidget {
  const PoiMapOverlay({
    super.key,
    required this.controller,
    required this.pois,
    required this.onPoiTapped,
    this.destinationPoiId,
    this.selectedPoiId,
  });

  final MapLibreMapController controller;
  final List<MapPoi> pois;
  final void Function(MapPoi poi) onPoiTapped;
  final String? destinationPoiId;
  final String? selectedPoiId;

  @override
  State<PoiMapOverlay> createState() => PoiMapOverlayState();
}

class PoiMapOverlayState extends State<PoiMapOverlay> {
  Map<String, Offset> _positions = const {};
  var _updateToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => updatePositions());
  }

  @override
  void didUpdateWidget(covariant PoiMapOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pois != widget.pois) {
      updatePositions();
      return;
    }
    if (oldWidget.destinationPoiId != widget.destinationPoiId ||
        oldWidget.selectedPoiId != widget.selectedPoiId) {
      setState(() {});
    }
  }

  Future<void> updatePositions() async {
    if (!mounted || widget.pois.isEmpty) return;

    final token = ++_updateToken;
    try {
      final points = await widget.controller.toScreenLocationBatch(
        widget.pois.map((poi) => LatLng(poi.lat, poi.lng)),
      );
      if (!mounted || token != _updateToken) return;
      setState(() {
        _positions = {
          for (var index = 0; index < widget.pois.length; index++)
            widget.pois[index].id: Offset(
              points[index].x.toDouble(),
              points[index].y.toDouble(),
            ),
        };
      });
    } on Object {
      // Kortet kan være midt i reload.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        for (final poi in widget.pois)
          if (_positions.containsKey(poi.id))
            _PoiOverlayMarker(
              position: _positions[poi.id]!,
              poi: poi,
              isDestination: poi.id == widget.destinationPoiId,
              isSelected: poi.id == widget.selectedPoiId,
              onTap: () => widget.onPoiTapped(poi),
            ),
      ],
    );
  }
}

class _PoiOverlayMarker extends StatelessWidget {
  const _PoiOverlayMarker({
    required this.position,
    required this.poi,
    required this.isDestination,
    required this.isSelected,
    required this.onTap,
  });

  final Offset position;
  final MapPoi poi;
  final bool isDestination;
  final bool isSelected;
  final VoidCallback onTap;

  static const _pinSize = 26.0;
  static const _minTapSize = 44.0;
  static const _borderWidth = 2.0;
  static const _iconFontSize = 14.0;

  @override
  Widget build(BuildContext context) {
    final pinColor = isDestination
        ? const Color(0xFFE53935)
        : isSelected
            ? const Color(0xFFD84315)
            : _colorFromHex(poi.markerColorHex);

    final left = position.dx - _minTapSize / 2;
    final top = position.dy - _pinSize / 2;

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.translucent,
        child: SizedBox(
          width: _minTapSize,
          height: _minTapSize,
          child: Center(
            child: Material(
              elevation: 3,
              shadowColor: Colors.black38,
              shape: const CircleBorder(),
              child: Ink(
                width: _pinSize,
                height: _pinSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: pinColor.withValues(
                    alpha: isDestination || isSelected ? 1.0 : 0.25,
                  ),
                  border: Border.all(color: Colors.white, width: _borderWidth),
                ),
                child: Center(
                  child: Text(
                    poi.mapPinIcon,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: _iconFontSize,
                      height: 1,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _colorFromHex(String hex) {
    final value = hex.replaceFirst('#', '');
    return Color(int.parse('FF$value', radix: 16));
  }
}
