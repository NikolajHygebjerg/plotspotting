import 'package:flutter/material.dart';

import '../../data/models/audio_tour.dart';
import '../../data/models/event_map_data.dart';
import '../visitor/visitor_audio_tour_picker_screen.dart';
import '../visitor/visitor_experience.dart';
import '../visitor/visitor_experience_picker_screen.dart';
import '../visitor/visitor_map_screen.dart';

enum _GuestPreviewStep { experience, audioTour, map }

/// Gæsteflow som besøgende ser det — oplevelsesvalg og derefter kort.
class OrganizerGuestPreview extends StatefulWidget {
  const OrganizerGuestPreview({
    super.key,
    required this.data,
  });

  final EventMapData data;

  @override
  State<OrganizerGuestPreview> createState() => _OrganizerGuestPreviewState();
}

class _OrganizerGuestPreviewState extends State<OrganizerGuestPreview> {
  late _GuestPreviewStep _step;
  VisitorExperience? _experience;
  AudioTourConfig? _audioTour;

  @override
  void initState() {
    super.initState();
    final options = availableExperiences(widget.data);
    if (options.length == 1) {
      _experience = options.first;
      _step = _GuestPreviewStep.map;
      if (_experience == VisitorExperience.audioTour) {
        final tours = widget.data.audioTourCatalog.configuredTours;
        _audioTour = tours.isNotEmpty ? tours.first : null;
      }
    } else {
      _step = _GuestPreviewStep.experience;
    }
  }

  void _backToExperiencePicker() {
    setState(() {
      _step = _GuestPreviewStep.experience;
      _experience = null;
      _audioTour = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case _GuestPreviewStep.experience:
        return VisitorExperiencePickerScreen(
          mapData: widget.data,
          embed: true,
          onExperienceSelected: (experience, {audioTour}) {
            if (experience == VisitorExperience.audioTour &&
                widget.data.audioTourCatalog.configuredTours.length > 1 &&
                audioTour == null) {
              setState(() => _step = _GuestPreviewStep.audioTour);
              return;
            }
            setState(() {
              _experience = experience;
              _audioTour = audioTour;
              _step = _GuestPreviewStep.map;
            });
          },
        );
      case _GuestPreviewStep.audioTour:
        return VisitorAudioTourPickerScreen(
          mapData: widget.data,
          embed: true,
          onTourSelected: (tour) {
            setState(() {
              _experience = VisitorExperience.audioTour;
              _audioTour = tour;
              _step = _GuestPreviewStep.map;
            });
          },
        );
      case _GuestPreviewStep.map:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (availableExperiences(widget.data).length > 1)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _backToExperiencePicker,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Skift oplevelse'),
                ),
              ),
            Expanded(
              child: VisitorMapScreen(
                mapData: widget.data,
                experience: _experience ?? VisitorExperience.search,
                audioTourConfig: _audioTour,
                organizerPreview: true,
              ),
            ),
          ],
        );
    }
  }
}
