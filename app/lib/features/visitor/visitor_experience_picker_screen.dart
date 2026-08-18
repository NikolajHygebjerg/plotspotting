import 'package:flutter/material.dart';

import '../../data/models/audio_tour.dart';
import '../../data/models/event_map_data.dart';
import 'visitor_experience.dart';
import 'visitor_audio_tour_picker_screen.dart';
import 'visitor_map_screen.dart';

typedef VisitorExperienceSelected = void Function(
  VisitorExperience experience, {
  AudioTourConfig? audioTour,
});

class VisitorExperiencePickerScreen extends StatelessWidget {
  const VisitorExperiencePickerScreen({
    super.key,
    required this.mapData,
    this.initialSearch,
    this.embed = false,
    this.onExperienceSelected,
  });

  final EventMapData mapData;
  final String? initialSearch;
  final bool embed;
  final VisitorExperienceSelected? onExperienceSelected;

  void _openExperience(BuildContext context, VisitorExperience experience) {
    if (experience == VisitorExperience.audioTour) {
      final tours = mapData.audioTourCatalog.configuredTours;
      if (tours.length > 1) {
        if (onExperienceSelected != null) {
          onExperienceSelected!(experience);
          return;
        }
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => VisitorAudioTourPickerScreen(mapData: mapData),
          ),
        );
        return;
      }
      _complete(
        context,
        experience,
        audioTour: tours.isNotEmpty ? tours.first : null,
      );
      return;
    }

    _complete(context, experience);
  }

  void _complete(
    BuildContext context,
    VisitorExperience experience, {
    AudioTourConfig? audioTour,
  }) {
    if (onExperienceSelected != null) {
      onExperienceSelected!(experience, audioTour: audioTour);
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => VisitorMapScreen(
          mapData: mapData,
          experience: experience,
          audioTourConfig: audioTour,
          initialSearch: experience == VisitorExperience.search ? initialSearch : null,
          embed: embed,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final options = availableExperiences(mapData);

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
              'Hvad vil du?',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Vælg hvordan du vil opleve kortet',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade700,
                  ),
            ),
            const SizedBox(height: 24),
            for (final experience in options) ...[
              _ExperienceCard(
                experience: experience,
                onTap: () => _openExperience(context, experience),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _ExperienceCard extends StatelessWidget {
  const _ExperienceCard({
    required this.experience,
    required this.onTap,
  });

  final VisitorExperience experience;
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
                backgroundColor: const Color(0xFF1565C0).withValues(alpha: 0.12),
                child: Icon(experience.icon, color: const Color(0xFF1565C0), size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      experience.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      experience.description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            height: 1.35,
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF1565C0)),
            ],
          ),
        ),
      ),
    );
  }
}
