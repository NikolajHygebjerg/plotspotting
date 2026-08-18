import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/navigation/route_guidance.dart';

/// Shared Google Maps-style navigation camera animation.
class RouteMapNavigationCamera {
  RouteMapNavigationCamera._();

  static const navigationZoom = 17.5;
  static const programmaticMoveGrace = Duration(milliseconds: 350);

  static Future<void> animateToInstruction({
    required MapLibreMapController? controller,
    required Position position,
    required NavigationInstruction instruction,
    required void Function(bool isProgrammatic) setProgrammaticFlag,
  }) async {
    if (controller == null) return;

    try {
      setProgrammaticFlag(true);
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(position.latitude, position.longitude),
            zoom: navigationZoom,
            bearing: instruction.mapBearing,
            tilt: 0,
          ),
        ),
      );
    } on Object {
      // Native map may be gone after leaving the screen.
    } finally {
      Future<void>.delayed(programmaticMoveGrace, () {
        setProgrammaticFlag(false);
      });
    }
  }

  static Future<void> animateToUser({
    required MapLibreMapController? controller,
    required double lat,
    required double lng,
    required void Function(bool isProgrammatic) setProgrammaticFlag,
    double? bearing,
    double zoom = navigationZoom,
  }) async {
    if (controller == null) return;

    try {
      setProgrammaticFlag(true);
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(lat, lng),
            zoom: zoom,
            bearing: bearing ?? 0,
            tilt: 0,
          ),
        ),
      );
    } on Object {
      // Native map may be gone after leaving the screen.
    } finally {
      Future<void>.delayed(programmaticMoveGrace, () {
        setProgrammaticFlag(false);
      });
    }
  }
}
