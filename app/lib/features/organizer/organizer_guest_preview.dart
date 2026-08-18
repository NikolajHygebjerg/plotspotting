import 'package:flutter/material.dart';

import '../../data/models/event_map_data.dart';
import '../visitor/visitor_experience.dart';
import '../visitor/visitor_map_screen.dart';

/// Gæsteflow som besøgende ser det — åbner direkte på kortet med bundmenu.
class OrganizerGuestPreview extends StatelessWidget {
  const OrganizerGuestPreview({
    super.key,
    required this.data,
  });

  final EventMapData data;

  @override
  Widget build(BuildContext context) {
    final options = availableExperiences(data);
    final experience = options.contains(VisitorExperience.explore)
        ? VisitorExperience.explore
        : (options.isNotEmpty ? options.first : VisitorExperience.search);

    return VisitorMapScreen(
      mapData: data,
      experience: experience,
      organizerPreview: true,
    );
  }
}
