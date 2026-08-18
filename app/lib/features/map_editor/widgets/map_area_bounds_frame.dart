import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../data/models/map_bounds.dart';

/// Viser det gemte kortområde som en ramme oven på kortet.
class MapAreaBoundsFrame extends StatelessWidget {
  const MapAreaBoundsFrame({
    super.key,
    required this.controller,
    required this.bounds,
    this.revision = 0,
  });

  final MapLibreMapController? controller;
  final MapBounds bounds;
  final int revision;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    if (controller == null || !bounds.isValid) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<Rect?>(
      key: ValueKey(revision),
      future: _boundsToScreenRect(controller, bounds),
      builder: (context, snapshot) {
        final rect = snapshot.data;
        if (rect == null || rect.width < 4 || rect.height < 4) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        return Stack(
          children: [
            Positioned.fromRect(
              rect: rect,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.primary, width: 2),
                    color: theme.colorScheme.primary.withValues(alpha: 0.06),
                  ),
                ),
              ),
            ),
            Positioned(
              left: rect.left,
              top: rect.bottom + 8,
              width: rect.width,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(
                      'Aktivt kortområde',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static Future<Rect?> _boundsToScreenRect(
    MapLibreMapController controller,
    MapBounds bounds,
  ) async {
    final tl = await controller.toScreenLocation(LatLng(bounds.north, bounds.west));
    final tr = await controller.toScreenLocation(LatLng(bounds.north, bounds.east));
    final bl = await controller.toScreenLocation(LatLng(bounds.south, bounds.west));
    final br = await controller.toScreenLocation(LatLng(bounds.south, bounds.east));

    return Rect.fromLTRB(
      math.min(tl.x, math.min(tr.x, math.min(bl.x, br.x))).toDouble(),
      math.min(tl.y, math.min(tr.y, math.min(bl.y, br.y))).toDouble(),
      math.max(tl.x, math.max(tr.x, math.max(bl.x, br.x))).toDouble(),
      math.max(tl.y, math.max(tr.y, math.max(bl.y, br.y))).toDouble(),
    );
  }
}
