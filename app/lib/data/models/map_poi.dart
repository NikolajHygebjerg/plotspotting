import 'dart:convert';

import '../../core/search/poi_search.dart';
import 'poi_media.dart';
import 'poi_occupant.dart';
import 'poi_topic.dart';

class MapPoi {
  const MapPoi({
    required this.id,
    required this.name,
    required this.category,
    required this.lat,
    required this.lng,
    this.description,
    this.accessVertexId,
    this.sortOrder = 0,
    this.houseNumber,
    this.occupants = const [],
    this.searchKeywords,
    this.media = const [],
  });

  final String id;
  final String name;
  final String category;
  final double lat;
  final double lng;
  final String? description;
  final String? accessVertexId;
  final int sortOrder;
  final String? houseNumber;
  final List<PoiOccupant> occupants;
  final String? searchKeywords;
  final List<PoiMedia> media;

  List<PoiMedia> get images =>
      media.where((item) => item.kind == PoiMediaKind.image).toList();

  List<PoiMedia> get videos =>
      media.where((item) => item.kind == PoiMediaKind.video).toList();

  List<PoiMedia> get audioClips =>
      media.where((item) => item.kind == PoiMediaKind.audio).toList();

  PoiMedia? get primaryAudio =>
      audioClips.isNotEmpty ? audioClips.first : null;

  PoiMedia? audioById(String? id) {
    if (id == null || id.isEmpty) return primaryAudio;
    for (final clip in audioClips) {
      if (clip.id == id) return clip;
    }
    return null;
  }

  String audioLabel(PoiMedia clip) =>
      clip.caption?.trim().isNotEmpty == true ? clip.caption!.trim() : 'Lydfil';

  bool get hasAudio => audioClips.isNotEmpty;

  bool get hasMedia => media.isNotEmpty;

  bool get hasVisualMedia => images.isNotEmpty || videos.isNotEmpty;

  static const categories = [
    'home',
    'food',
    'toilet',
    'info',
    'activity',
    'exhibitor',
    'other',
  ];

  List<String> get occupantNames =>
      occupants.map((occupant) => occupant.name.trim()).where((name) => name.isNotEmpty).toList();

  String? get primaryOccupantName =>
      occupantNames.isEmpty ? null : occupantNames.first;

  String get occupantsLabel => occupantNames.join(', ');

  String get displayTitle {
    if (category == 'home' && houseNumber != null && houseNumber!.isNotEmpty) {
      if (occupantNames.isNotEmpty) {
        if (occupantNames.length == 1) {
          return 'Nr. $houseNumber · ${occupantNames.first}';
        }
        return 'Nr. $houseNumber · ${occupantNames.first} m.fl.';
      }
      return 'Nr. $houseNumber';
    }
    if (occupantNames.isNotEmpty && name.isEmpty) {
      return occupantNames.length == 1 ? occupantNames.first : occupantsLabel;
    }
    return name;
  }

  /// Label shown in navigation card, e.g. "Laila og Nikolaj (Friland 36)".
  String get navigationLabel {
    if (occupantNames.isNotEmpty) {
      final names = occupantsLabel;
      if (houseNumber != null && houseNumber!.isNotEmpty) {
        final place = name.isNotEmpty ? name : 'Friland';
        return '$names ($place $houseNumber)';
      }
      return names;
    }
    return displayTitle;
  }

  String get displaySubtitle {
    if (category == 'home') {
      final parts = <String>[];
      if (name.isNotEmpty && name != displayTitle) parts.add(name);
      if (occupantNames.length > 1) {
        parts.add(occupantsLabel);
      } else if (occupantNames.length == 1 &&
          !displayTitle.contains(occupantNames.first)) {
        parts.add(occupantNames.first);
      }
      return parts.isEmpty ? 'Bolig' : parts.join(' · ');
    }
    if (occupantNames.isNotEmpty) {
      return occupantsLabel;
    }
    return category;
  }

  bool matchesQuery(String query) => PoiSearch.matches(this, query);

  /// Pin color on the editor/visitor map.
  String get markerColorHex => switch (category) {
        'home' => '#2E7D32',
        'food' => '#EF6C00',
        'toilet' => '#1565C0',
        'info' => '#6A1B9A',
        'activity' => '#00897B',
        'exhibitor' => '#5D4037',
        _ => '#546E7A',
      };

  /// Icon shown on the map pin (tap target).
  String get mapPinIcon => switch (category) {
        'home' => 'I',
        'food' => 'F',
        'toilet' => 'T',
        'info' => 'i',
        'activity' => '*',
        'exhibitor' => 'E',
        _ => 'P',
      };

  /// Short label for map pin (keeps map readable).
  String get mapPinLabel {
    if (houseNumber != null && houseNumber!.isNotEmpty) return houseNumber!;
    if (name.isNotEmpty && name != 'Sted') return name;
    final primary = primaryOccupantName;
    if (primary != null) return primary.split(' ').first;
    return displayTitle;
  }

  MapPoi copyWith({
    String? id,
    String? name,
    String? category,
    double? lat,
    double? lng,
    String? description,
    String? accessVertexId,
    bool clearAccessVertexId = false,
    int? sortOrder,
    String? houseNumber,
    List<PoiOccupant>? occupants,
    String? searchKeywords,
    List<PoiMedia>? media,
  }) {
    return MapPoi(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      description: description ?? this.description,
      accessVertexId: clearAccessVertexId
          ? null
          : (accessVertexId ?? this.accessVertexId),
      sortOrder: sortOrder ?? this.sortOrder,
      houseNumber: houseNumber ?? this.houseNumber,
      occupants: occupants ?? this.occupants,
      searchKeywords: searchKeywords ?? this.searchKeywords,
      media: media ?? this.media,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        if (description != null) 'description': description,
        'lat': lat,
        'lng': lng,
        if (accessVertexId != null) 'access_vertex_id': accessVertexId,
        'sort_order': sortOrder,
        'metadata': _metadataJson(),
      };

  Map<String, dynamic> _metadataJson() {
    final visualMedia = infoMedia;
    final audioMedia = audioClips;

    return {
      if (houseNumber != null && houseNumber!.isNotEmpty) 'house_number': houseNumber,
      if (occupants.isNotEmpty)
        'occupants': occupants.map((occupant) => occupant.toJson()).toList(),
      if (primaryOccupantName != null) 'resident_name': primaryOccupantName,
      if (searchKeywords != null && searchKeywords!.isNotEmpty)
        'search_keywords': searchKeywords,
      if (media.isNotEmpty) 'media': media.map((item) => item.toJson()).toList(),
      'topics': {
        PoiTopic.address.name: {
          if (houseNumber != null && houseNumber!.isNotEmpty)
            'house_number': houseNumber,
        },
        PoiTopic.name.name: {
          if (name.trim().isNotEmpty && name.trim() != 'Sted') 'nickname': name.trim(),
          if (occupants.isNotEmpty)
            'occupants': occupants.map((occupant) => occupant.toJson()).toList(),
        },
        PoiTopic.info.name: {
          if (description != null && description!.isNotEmpty)
            'description': description,
          if (visualMedia.isNotEmpty)
            'media': visualMedia.map((item) => item.toJson()).toList(),
        },
        PoiTopic.audio.name: {
          if (audioMedia.isNotEmpty)
            'media': audioMedia.map((item) => item.toJson()).toList(),
        },
      },
    };
  }

  factory MapPoi.fromJson(Map<String, dynamic> json) {
    final metaMap = _metadataMapFromJson(json['metadata']);
    final normalized = _normalizeMetadataFromTopics(metaMap);

    var name = json['name'] as String? ?? '';
    final nickname = normalized.remove('_nickname') as String?;
    if (name.trim().isEmpty || name.trim() == 'Sted') {
      if (nickname != null && nickname.isNotEmpty) {
        name = nickname;
      }
    }

    var description = json['description'] as String?;
    final topicDescription = normalized.remove('_description') as String?;
    if (description == null || description.trim().isEmpty) {
      description = topicDescription;
    }

    return MapPoi(
      id: json['id'] as String,
      name: name,
      category: json['category'] as String? ?? 'other',
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      description: description,
      accessVertexId: json['access_vertex_id'] as String?,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      houseNumber: normalized['house_number'] as String?,
      occupants: _occupantsFromMetadata(normalized),
      searchKeywords: normalized['search_keywords'] as String?,
      media: _mediaFromMetadata(normalized),
    );
  }

  /// Backend gemmer emne-data i `metadata.topics` — hydrér flade felter ved load.
  static Map<String, dynamic> _metadataMapFromJson(Object? metadata) {
    if (metadata is Map) {
      return Map<String, dynamic>.from(metadata);
    }
    if (metadata is String && metadata.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(metadata);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } on Object {
        return {};
      }
    }
    return {};
  }

  static Map<String, dynamic> _normalizeMetadataFromTopics(
    Map<String, dynamic> metaMap,
  ) {
    final normalized = Map<String, dynamic>.from(metaMap);
    final topics = normalized['topics'];
    if (topics is! Map) return normalized;

    final topicsMap = Map<String, dynamic>.from(topics);

    final address = topicsMap['address'];
    if (address is Map) {
      final houseNumber = Map<String, dynamic>.from(address)['house_number'] as String?;
      if (houseNumber != null &&
          houseNumber.trim().isNotEmpty &&
          (normalized['house_number'] as String?)?.trim().isNotEmpty != true) {
        normalized['house_number'] = houseNumber.trim();
      }
    }

    final nameTopic = topicsMap['name'];
    if (nameTopic is Map) {
      final nameMap = Map<String, dynamic>.from(nameTopic);
      if (normalized['occupants'] == null && nameMap['occupants'] is List) {
        normalized['occupants'] = nameMap['occupants'];
      }
      final nickname = nameMap['nickname'] as String?;
      if (nickname != null && nickname.trim().isNotEmpty) {
        normalized['_nickname'] = nickname.trim();
      }
    }

    final info = topicsMap['info'];
    if (info is Map) {
      final infoMap = Map<String, dynamic>.from(info);
      final topicDescription = infoMap['description'] as String?;
      if (topicDescription != null && topicDescription.trim().isNotEmpty) {
        normalized['_description'] = topicDescription.trim();
      }
      normalized['media'] = _mergeMediaLists(
        normalized['media'],
        infoMap['media'],
      );
    }

    final audio = topicsMap['audio'];
    if (audio is Map) {
      final audioMap = Map<String, dynamic>.from(audio);
      normalized['media'] = _mergeMediaLists(
        normalized['media'],
        audioMap['media'],
      );
    }

    return normalized;
  }

  static List<dynamic> _mergeMediaLists(Object? existing, Object? extra) {
    final merged = <dynamic>[];
    final seen = <String>{};

    void addItems(Object? raw) {
      if (raw is! List) return;
      for (final item in raw) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final id = map['id'] as String? ?? map['url'] as String? ?? '';
        if (id.isEmpty || seen.contains(id)) continue;
        seen.add(id);
        merged.add(map);
      }
    }

    addItems(existing);
    addItems(extra);
    return merged;
  }

  static List<PoiMedia> _mediaFromMetadata(Map<String, dynamic> metaMap) {
    final raw = metaMap['media'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => PoiMedia.fromJson(Map<String, dynamic>.from(item)))
        .where((item) => item.url.isNotEmpty)
        .toList();
  }

  static List<PoiOccupant> _occupantsFromMetadata(Map<String, dynamic> metaMap) {
    final raw = metaMap['occupants'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((item) => PoiOccupant.fromJson(Map<String, dynamic>.from(item)))
          .where((occupant) => occupant.name.trim().isNotEmpty)
          .toList();
    }

    final legacyName = metaMap['resident_name'] as String?;
    if (legacyName != null && legacyName.trim().isNotEmpty) {
      return [PoiOccupant(name: legacyName.trim())];
    }

    return const [];
  }
}
