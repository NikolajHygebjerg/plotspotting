import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../data/models/event_map_data.dart';
import '../../data/models/map_poi.dart';
import '../../data/models/poi_topic.dart';
import '../../widgets/event_map_widget.dart';
import '../visitor/widgets/visitor_poi_topic_sheets.dart';

/// Gæstevisning af kortet — overlay, steder og stier som besøgende ser det.
class OrganizerGuestMapView extends StatelessWidget {
  const OrganizerGuestMapView({
    super.key,
    required this.data,
    this.onDataChanged,
  });

  final EventMapData data;
  final ValueChanged<EventMapData>? onDataChanged;

  @override
  Widget build(BuildContext context) {
    final hasIllustrated = data.event.hasIllustratedBasemap;
    final hasBounds = data.event.navigationBounds?.isValid == true;

    return EventMapWidget(
      data: data,
      initialCenter: data.event.centerLat != null && data.event.centerLng != null
          ? ll.LatLng(data.event.centerLat!, data.event.centerLng!)
          : null,
      constrainToEventBounds: hasBounds,
      boundsFitPadding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
      showIllustratedBasemap: true,
      illustratedMapOnly: hasIllustrated,
      showEventPaths: !hasIllustrated,
      showPathVertices: false,
      showPoiMarkers: true,
      onPoiTapped: (poi) => _showPoiInfo(context, poi),
    );
  }

  void _showPoiInfo(BuildContext context, MapPoi poi) {
    showVisitorPoiTopicPicker(
      context,
      poi: poi,
      activeTopics: PoiTopic.values.toSet(),
      isDestination: false,
    );
  }
}
