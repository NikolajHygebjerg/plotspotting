import 'package:flutter/material.dart';

import '../../../data/models/event_map_data.dart';

enum VisitorExperience {
  search,
  explore,
  audioTour,
}

extension VisitorExperienceInfo on VisitorExperience {
  String get title => switch (this) {
        VisitorExperience.search => 'Find et sted',
        VisitorExperience.explore => 'Gå på opdagelse',
        VisitorExperience.audioTour => 'Lydvandring',
      };

  String get description => switch (this) {
        VisitorExperience.search =>
          'Søg på adresser, navne og steder — og få rutevejledning',
        VisitorExperience.explore =>
          'Udforsk kortet i ro og mag og tryk på steder for info',
        VisitorExperience.audioTour =>
          'Guidet tur — tryk på et sted for at høre historien',
      };

  IconData get icon => switch (this) {
        VisitorExperience.search => Icons.search,
        VisitorExperience.explore => Icons.explore_outlined,
        VisitorExperience.audioTour => Icons.headphones_outlined,
      };
}

List<VisitorExperience> availableExperiences(EventMapData data) {
  final options = <VisitorExperience>[];
  if (data.hasPois) {
    options.add(VisitorExperience.search);
    options.add(VisitorExperience.explore);
  }
  if (data.hasAudioTour) {
    options.add(VisitorExperience.audioTour);
  }
  return options;
}

VisitorExperience defaultExperience(EventMapData data) {
  final options = availableExperiences(data);
  return options.isNotEmpty ? options.first : VisitorExperience.search;
}
