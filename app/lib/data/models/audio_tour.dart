enum AudioTourItemKind {
  poi,
  wander;

  static AudioTourItemKind fromJson(String? value) =>
      value == 'wander' ? AudioTourItemKind.wander : AudioTourItemKind.poi;

  String toJson() => switch (this) {
        AudioTourItemKind.wander => 'wander',
        AudioTourItemKind.poi => 'poi',
      };
}

class AudioTourWanderClip {
  const AudioTourWanderClip({
    required this.id,
    required this.url,
    this.storagePath,
    this.title,
  });

  final String id;
  final String url;
  final String? storagePath;
  final String? title;

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        if (storagePath != null) 'storage_path': storagePath,
        if (title != null && title!.isNotEmpty) 'title': title,
      };

  factory AudioTourWanderClip.fromJson(Map<String, dynamic> json) {
    return AudioTourWanderClip(
      id: json['id'] as String,
      url: json['url'] as String,
      storagePath: json['storage_path'] as String?,
      title: json['title'] as String?,
    );
  }
}

class AudioTourItem {
  const AudioTourItem.poi({
    required this.poiId,
    this.audioId,
  })  : kind = AudioTourItemKind.poi,
        wander = null;

  const AudioTourItem.wander({required this.wander})
      : kind = AudioTourItemKind.wander,
        poiId = null,
        audioId = null;

  final AudioTourItemKind kind;
  final String? poiId;
  final String? audioId;
  final AudioTourWanderClip? wander;

  Map<String, dynamic> toJson() => switch (kind) {
        AudioTourItemKind.poi => {
            'kind': kind.toJson(),
            'poi_id': poiId,
            if (audioId != null) 'audio_id': audioId,
          },
        AudioTourItemKind.wander => {
            'kind': kind.toJson(),
            ...wander!.toJson(),
          },
      };

  factory AudioTourItem.fromJson(Map<String, dynamic> json) {
    final kind = AudioTourItemKind.fromJson(json['kind'] as String?);
    if (kind == AudioTourItemKind.wander) {
      return AudioTourItem.wander(wander: AudioTourWanderClip.fromJson(json));
    }
    return AudioTourItem.poi(
      poiId: json['poi_id'] as String,
      audioId: json['audio_id'] as String?,
    );
  }
}

class AudioTourConfig {
  const AudioTourConfig({
    required this.id,
    this.title,
    this.enabled = false,
    this.items = const [],
  });

  final String id;
  final String? title;
  final bool enabled;
  final List<AudioTourItem> items;

  String get displayTitle =>
      title?.trim().isNotEmpty == true ? title!.trim() : 'Lydvandring';

  bool get isConfigured =>
      enabled &&
      items.isNotEmpty &&
      items.any((item) => item.kind == AudioTourItemKind.poi);

  String? get startPoiId {
    for (final item in items) {
      if (item.kind == AudioTourItemKind.poi) return item.poiId;
    }
    return null;
  }

  List<String> get poiStopIds => [
        for (final item in items)
          if (item.kind == AudioTourItemKind.poi) item.poiId!,
      ];

  AudioTourItem? poiItemAtStopIndex(int stopIndex) {
    if (stopIndex < 0) return null;
    var seen = 0;
    for (final item in items) {
      if (item.kind != AudioTourItemKind.poi) continue;
      if (seen == stopIndex) return item;
      seen++;
    }
    return null;
  }

  AudioTourConfig copyWith({
    String? id,
    String? title,
    bool? enabled,
    List<AudioTourItem>? items,
  }) {
    return AudioTourConfig(
      id: id ?? this.id,
      title: title ?? this.title,
      enabled: enabled ?? this.enabled,
      items: items ?? this.items,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (title != null && title!.isNotEmpty) 'title': title,
        'enabled': enabled,
        'items': items.map((item) => item.toJson()).toList(),
      };

  factory AudioTourConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) {
      return const AudioTourConfig(id: 'default');
    }
    final rawItems = json['items'] as List? ?? const [];
    return AudioTourConfig(
      id: json['id'] as String? ?? 'default',
      title: json['title'] as String?,
      enabled: json['enabled'] as bool? ?? false,
      items: rawItems
          .map((item) => AudioTourItem.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
    );
  }

  static AudioTourConfig fromEventMetadata(Map<String, dynamic>? metadata) {
    return AudioTourCatalog.fromEventMetadata(metadata).primaryTour;
  }

  Map<String, dynamic> toEventMetadata() => AudioTourCatalog([this]).toEventMetadata();
}

class AudioTourCatalog {
  const AudioTourCatalog(this.tours);

  final List<AudioTourConfig> tours;

  List<AudioTourConfig> get configuredTours =>
      tours.where((tour) => tour.isConfigured).toList();

  bool get hasConfiguredTour => configuredTours.isNotEmpty;

  AudioTourConfig get primaryTour {
    if (configuredTours.isNotEmpty) return configuredTours.first;
    if (tours.isNotEmpty) return tours.first;
    return const AudioTourConfig(id: 'default');
  }

  AudioTourConfig? tourById(String id) {
    for (final tour in tours) {
      if (tour.id == id) return tour;
    }
    return null;
  }

  AudioTourCatalog copyWith({List<AudioTourConfig>? tours}) =>
      AudioTourCatalog(tours ?? this.tours);

  static AudioTourCatalog fromEventMetadata(Map<String, dynamic>? metadata) {
    if (metadata == null || metadata.isEmpty) return const AudioTourCatalog([]);

    final rawTours = metadata['audio_tours'];
    if (metadata.containsKey('audio_tours')) {
      final items = rawTours is List ? rawTours : const [];
      return AudioTourCatalog(
        items
            .map(
              (tour) => AudioTourConfig.fromJson(
                Map<String, dynamic>.from(tour as Map),
              ),
            )
            .toList(),
      );
    }

    final legacy = metadata['audio_tour'];
    if (legacy is Map) {
      final tour = AudioTourConfig.fromJson(Map<String, dynamic>.from(legacy));
      return AudioTourCatalog([
        tour.copyWith(id: tour.id == 'default' ? 'legacy' : tour.id),
      ]);
    }

    return const AudioTourCatalog([]);
  }

  Map<String, dynamic> toEventMetadata() => {
        'audio_tours': tours.map((tour) => tour.toJson()).toList(),
        'audio_tour': null,
      };
}

/// Finds wander clip between two POI item indices in the flat item list.
AudioTourWanderClip? wanderBetweenPoiStops(
  AudioTourConfig config,
  int fromPoiStopIndex,
  int toPoiStopIndex,
) {
  final poiIds = config.poiStopIds;
  if (fromPoiStopIndex < 0 ||
      toPoiStopIndex >= poiIds.length ||
      fromPoiStopIndex >= toPoiStopIndex) {
    return null;
  }

  final fromPoiId = poiIds[fromPoiStopIndex];
  final toPoiId = poiIds[toPoiStopIndex];
  var seenFrom = false;
  for (final item in config.items) {
    if (item.kind == AudioTourItemKind.poi) {
      if (item.poiId == fromPoiId) {
        seenFrom = true;
        continue;
      }
      if (item.poiId == toPoiId) break;
      continue;
    }
    if (seenFrom && item.wander != null) {
      return item.wander;
    }
  }
  return null;
}
