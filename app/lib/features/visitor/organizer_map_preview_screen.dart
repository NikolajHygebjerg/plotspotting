import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/storage/organizer_session_persistence.dart';
import '../../data/models/event_map_data.dart';
import '../../data/repositories/event_repository.dart';
import '../../widgets/event_map_widget.dart';
import '../map_setup/map_setup_flow.dart';

/// Read-only forhåndsvisning af kortet for arrangører — uden GPS og besøger-UI.
class OrganizerMapPreviewScreen extends StatefulWidget {
  const OrganizerMapPreviewScreen({
    super.key,
    required this.mapData,
  });

  final EventMapData mapData;

  @override
  State<OrganizerMapPreviewScreen> createState() => _OrganizerMapPreviewScreenState();
}

class _OrganizerMapPreviewScreenState extends State<OrganizerMapPreviewScreen> {
  final _repository = EventRepository();

  late EventMapData _data;

  @override
  void initState() {
    super.initState();
    _data = widget.mapData;
  }

  Future<void> _openEditor() async {
    try {
      final data = await _repository.loadForEdit(eventId: _data.event.id);
      await persistOrganizerSession(
        eventId: data.event.id,
        eventName: data.event.name,
        publicSlug: data.event.publicSlug,
      );
      if (!mounted) return;
      await MapSetupFlow.openEditorOrSetup(
        context,
        eventId: data.event.id,
        eventName: data.event.name,
        data: data,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke åbne redigering: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasIllustrated = _data.event.hasIllustratedBasemap;
    final hasBounds = _data.event.navigationBounds?.isValid == true;

    return Scaffold(
      appBar: AppBar(
        title: Text(_data.event.name),
        actions: [
          TextButton.icon(
            onPressed: _openEditor,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Rediger'),
          ),
        ],
      ),
      body: Stack(
        children: [
          EventMapWidget(
            data: _data,
            initialCenter: _data.event.centerLat != null && _data.event.centerLng != null
                ? ll.LatLng(_data.event.centerLat!, _data.event.centerLng!)
                : null,
            constrainToEventBounds: hasBounds,
            boundsFitPadding: const EdgeInsets.all(24),
            showIllustratedBasemap: hasIllustrated,
            illustratedMapOnly: false,
            showEventPaths: !hasIllustrated,
            showPathVertices: false,
            showPoiMarkers: true,
            onPoiTapped: (poi) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(poi.name)),
              );
            },
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(12),
              color: Colors.white.withValues(alpha: 0.94),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(
                  'Sådan ser gæster kortet. Tryk «Rediger» for at ændre stier og steder.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
