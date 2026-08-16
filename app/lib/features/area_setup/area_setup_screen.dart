import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/constants.dart';
import '../../data/models/map_bounds.dart';
import '../../data/repositories/event_repository.dart';
import '../../widgets/event_map_widget.dart';
import '../../data/models/event_map_data.dart';
import '../map_setup/map_setup_flow.dart';
import '../map_setup/map_setup_step_header.dart';

/// Vælg det geografiske område kortet skal dække.
class AreaSetupScreen extends StatefulWidget {
  const AreaSetupScreen({
    super.key,
    required this.eventId,
    required this.eventName,
    this.initialCenter,
    this.initialBounds,
    this.onboarding = false,
  });

  final String eventId;
  final String eventName;
  final ll.LatLng? initialCenter;
  final MapBounds? initialBounds;
  /// Når true, fortsætter flowet til korttype-valg i stedet for at poppe tilbage.
  final bool onboarding;

  @override
  State<AreaSetupScreen> createState() => _AreaSetupScreenState();
}

class _AreaSetupScreenState extends State<AreaSetupScreen> {
  final _repository = EventRepository();
  MapLibreMapController? _controller;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.onboarding ? 'Vælg kortområde' : 'Skift kortområde'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.onboarding) const MapSetupStepHeader(currentStep: 0),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.onboarding
                      ? 'Zoom ud så hele området er synligt med lidt luft omkring — '
                          'gæster skal kunne pan/zoom og se alle huse, også i kanterne.'
                      : 'Zoom ud så hele området er synligt med lidt luft omkring. '
                          'Gæster får automatisk et større område at bevæge sig i.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Material(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lightbulb_outline, color: Colors.orange.shade800),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Tip: Tag et større udsnit end tegningen — '
                            'så kan man zoome ind på huse og se kanterne (fx nederste huse).',
                            style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                EventMapWidget(
                  data: EventMapData(
                    event: EventMeta(
                      id: widget.eventId,
                      name: widget.eventName,
                      bounds: widget.initialBounds,
                    ),
                  ),
                  initialCenter: widget.initialCenter ??
                      const ll.LatLng(
                        AppConstants.frilandCenterLat,
                        AppConstants.frilandCenterLng,
                      ),
                  myLocationEnabled: true,
                  onMapCreated: (controller) => _controller = controller,
                ),
                IgnorePointer(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 240,
                          height: 240,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: theme.colorScheme.primary,
                              width: 2,
                            ),
                            color: theme.colorScheme.primary.withValues(alpha: 0.06),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Tegningen placeres her',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: _saving ? null : _captureVisibleArea,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.crop_free),
                label: Text(
                  widget.onboarding ? 'Gem område og fortsæt' : 'Gem synligt område',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _captureVisibleArea() async {
    final controller = _controller;
    if (controller == null) return;

    setState(() => _saving = true);
    try {
      final region = await controller.getVisibleRegion();
      final contentBounds = MapBounds(
        south: region.southwest.latitude,
        west: region.southwest.longitude,
        north: region.northeast.latitude,
        east: region.northeast.longitude,
      );
      final viewBounds = contentBounds.scaledAroundCenter(
        AppConstants.areaViewBoundsExpansionFactor,
      );
      final centerLat = (contentBounds.south + contentBounds.north) / 2;
      final centerLng = (contentBounds.west + contentBounds.east) / 2;

      await _repository.saveArea(
        eventId: widget.eventId,
        bounds: contentBounds,
        viewBounds: viewBounds,
        centerLat: centerLat,
        centerLng: centerLng,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Område gemt — gæster kan zoome og panorerer i et større udsnit',
          ),
        ),
      );

      if (widget.onboarding) {
        MapSetupFlow.continueAfterAreaSaved(
          context,
          eventId: widget.eventId,
          eventName: widget.eventName,
          bounds: contentBounds,
        );
      } else {
        Navigator.pop(context, contentBounds);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke gemme område: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
