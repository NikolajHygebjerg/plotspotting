import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../data/models/event_map_data.dart';
import '../../data/models/map_bounds.dart';
import '../area_setup/area_setup_screen.dart';
import '../map_editor/map_editor_screen.dart';
import 'map_style_choice_screen.dart';

/// Navigation mellem trin i kortopsætning: område → korttype → editor.
abstract final class MapSetupFlow {
  static Future<void> startAreaSetup(
    BuildContext context, {
    required String eventId,
    required String eventName,
    ll.LatLng? initialCenter,
    MapBounds? initialBounds,
    bool replace = false,
  }) async {
    final route = MaterialPageRoute(
      builder: (context) => AreaSetupScreen(
        onboarding: true,
        eventId: eventId,
        eventName: eventName,
        initialCenter: initialCenter,
        initialBounds: initialBounds,
      ),
    );
    if (replace) {
      await Navigator.pushReplacement(context, route);
    } else {
      await Navigator.push(context, route);
    }
  }

  static void continueAfterAreaSaved(
    BuildContext context, {
    required String eventId,
    required String eventName,
    required MapBounds bounds,
  }) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => MapStyleChoiceScreen(
          eventId: eventId,
          eventName: eventName,
          bounds: bounds,
        ),
      ),
    );
  }

  static void openEditor(
    BuildContext context, {
    required String eventId,
    required String eventName,
    EventMapData? initialData,
  }) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => MapEditorScreen(
          eventId: eventId,
          eventName: eventName,
          initialData: initialData,
        ),
      ),
    );
  }

  /// Åbn editor — går via områdeopsætning hvis bounds mangler.
  static Future<void> openEditorOrSetup(
    BuildContext context, {
    required String eventId,
    required String eventName,
    required EventMapData data,
  }) async {
    final bounds = data.event.bounds;
    if (bounds == null || !bounds.isValid) {
      await startAreaSetup(
        context,
        eventId: eventId,
        eventName: eventName,
        initialCenter: data.event.centerLat != null && data.event.centerLng != null
            ? ll.LatLng(data.event.centerLat!, data.event.centerLng!)
            : null,
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MapEditorScreen(
          eventId: eventId,
          eventName: eventName,
          initialData: data,
        ),
      ),
    );
  }
}
