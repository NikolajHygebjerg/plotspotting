import 'package:flutter/material.dart';

import '../../data/models/audio_tour.dart';
import '../../data/models/event_map_data.dart';
import 'visitor_experience.dart';
import 'visitor_map_screen.dart';

class VisitorAudioTourPickerScreen extends StatelessWidget {
  const VisitorAudioTourPickerScreen({
    super.key,
    required this.mapData,
    this.onTourSelected,
    this.embed = false,
    this.organizerPreview = false,
  });

  final EventMapData mapData;
  final ValueChanged<AudioTourConfig>? onTourSelected;
  final bool embed;
  final bool organizerPreview;

  void _openTour(BuildContext context, AudioTourConfig tour) {
    if (onTourSelected != null) {
      onTourSelected!(tour);
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => VisitorMapScreen(
          mapData: mapData,
          experience: VisitorExperience.audioTour,
          audioTourConfig: tour,
          embed: embed,
          organizerPreview: organizerPreview,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tours = mapData.audioTourCatalog.configuredTours;

    return Scaffold(
      appBar: embed ? null : AppBar(
        title: Text(mapData.event.name),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Text(
              'Vælg lydvandring',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Hvert tema bruger sine egne fortællinger på stederne',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade700,
                  ),
            ),
            const SizedBox(height: 24),
            for (final tour in tours) ...[
              _TourCard(
                title: tour.displayTitle,
                stopCount: tour.poiStopIds.length,
                onTap: () => _openTour(context, tour),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _TourCard extends StatelessWidget {
  const _TourCard({
    required this.title,
    required this.stopCount,
    required this.onTap,
  });

  final String title;
  final int stopCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFF6A1B9A).withValues(alpha: 0.12),
                child: const Icon(Icons.headphones, color: Color(0xFF6A1B9A), size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$stopCount stop${stopCount == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF6A1B9A)),
            ],
          ),
        ),
      ),
    );
  }
}
