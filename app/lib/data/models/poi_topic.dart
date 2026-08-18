import 'package:flutter/material.dart';

import 'map_poi.dart';
import 'poi_media.dart';

/// Emner som sted-information kan grupperes i.
enum PoiTopic {
  address,
  name,
  info,
  audio,
}

extension PoiTopicLabels on PoiTopic {
  String get label => switch (this) {
        PoiTopic.address => 'Adresse',
        PoiTopic.name => 'Navn',
        PoiTopic.info => 'Info',
        PoiTopic.audio => 'Lyd',
      };

  IconData get icon => switch (this) {
        PoiTopic.address => Icons.location_on_outlined,
        PoiTopic.name => Icons.badge_outlined,
        PoiTopic.info => Icons.info_outline,
        PoiTopic.audio => Icons.headphones_outlined,
      };

  String get description => switch (this) {
        PoiTopic.address => 'Husnummer og adresse',
        PoiTopic.name => 'Navne og beboere',
        PoiTopic.info => 'Tekst, billeder og video',
        PoiTopic.audio => 'Lydfortællinger',
      };
}

extension MapPoiTopicContent on MapPoi {
  String? get resolvedHouseNumber {
    final direct = houseNumber?.trim();
    if (direct != null && direct.isNotEmpty) return direct;

    final label = name.trim();
    if (label.isEmpty || label == 'Sted') return null;

    final dotted = RegExp(r'^(\d+)\s*[·•]\s*').firstMatch(label);
    if (dotted != null) return dotted.group(1);

    final numbered = RegExp(r'^Nr\.?\s*(\d+)', caseSensitive: false).firstMatch(label);
    if (numbered != null) return numbered.group(1);

    if (RegExp(r'^\d+$').hasMatch(label)) return label;
    return null;
  }

  bool get hasAddressTopic {
    final number = resolvedHouseNumber;
    return number != null && number.isNotEmpty;
  }

  bool get hasNameTopic =>
      occupants.isNotEmpty ||
      (name.trim().isNotEmpty && name.trim() != 'Sted') ||
      (primaryOccupantName != null && primaryOccupantName!.trim().isNotEmpty);

  bool get hasInfoTopic =>
      (description != null && description!.trim().isNotEmpty) || hasVisualMedia;

  bool get hasAudioTopic => hasAudio;

  bool hasTopic(PoiTopic topic) => switch (topic) {
        PoiTopic.address => hasAddressTopic,
        PoiTopic.name => hasNameTopic,
        PoiTopic.info => hasInfoTopic,
        PoiTopic.audio => hasAudioTopic,
      };

  Set<PoiTopic> get availableTopics => {
        if (hasAddressTopic) PoiTopic.address,
        if (hasNameTopic) PoiTopic.name,
        if (hasInfoTopic) PoiTopic.info,
        if (hasAudioTopic) PoiTopic.audio,
      };

  bool matchesActiveTopics(Set<PoiTopic> activeTopics) {
    if (activeTopics.isEmpty) return false;
    if (activeTopics.length == PoiTopic.values.length) return true;
    if (availableTopics.isEmpty) return false;
    return availableTopics.intersection(activeTopics).isNotEmpty;
  }

  List<PoiMedia> get infoMedia =>
      media.where((item) => item.kind != PoiMediaKind.audio).toList();

  String get addressTopicText {
    final parts = <String>[];
    final number = resolvedHouseNumber;
    if (number != null && number.isNotEmpty) {
      parts.add(number);
    }
    if (name.trim().isNotEmpty &&
        name.trim() != 'Sted' &&
        !parts.contains(name.trim())) {
      parts.add(name.trim());
    }
    return parts.join(' · ');
  }

  String get nameTopicTitle {
    if (occupants.isNotEmpty) return occupantsLabel;
    if (name.trim().isNotEmpty && name.trim() != 'Sted') return name.trim();
    return displayTitle;
  }

  String? get nameTopicSubtitle {
    if (occupants.isEmpty) return null;
    if (name.trim().isNotEmpty &&
        name.trim() != 'Sted' &&
        !occupantsLabel.contains(name.trim())) {
      return name.trim();
    }
    return null;
  }
}
