import '../../core/constants.dart';
import 'audio_tour.dart';
import 'map_bounds.dart';
import 'map_edge.dart';
import 'map_poi.dart';
import 'map_vertex.dart';
import 'treasure_hunt.dart';

class EventMeta {
  const EventMeta({
    required this.id,
    required this.name,
    this.description,
    this.status = 'draft',
    this.publicSlug,
    this.centerLat,
    this.centerLng,
    this.basemapUrl,
    this.basemapStatus = 'none',
    this.bounds,
    this.viewBounds,
    this.metadata = const {},
  });

  final String id;
  final String name;
  final String? description;
  final String status;
  final String? publicSlug;
  final double? centerLat;
  final double? centerLng;
  final String? basemapUrl;
  final String basemapStatus;
  final MapBounds? bounds;
  final MapBounds? viewBounds;
  final Map<String, dynamic> metadata;

  AudioTourCatalog get audioTourCatalog =>
      AudioTourCatalog.fromEventMetadata(metadata);

  AudioTourConfig get audioTour => audioTourCatalog.primaryTour;

  TreasureHuntCatalog get treasureHuntCatalog =>
      TreasureHuntCatalog.fromEventMetadata(metadata);

  TreasureHuntConfig get treasureHunt => treasureHuntCatalog.primaryHunt;

  /// Område gæster kan zoome/panorere inden for (typisk større end [bounds]).
  MapBounds? get navigationBounds {
    if (viewBounds != null && viewBounds!.isValid) return viewBounds;
    if (bounds != null && bounds!.isValid) {
      return bounds!.scaledAroundCenter(AppConstants.areaViewBoundsExpansionFactor);
    }
    return null;
  }

  bool get isPublished => status == 'published';
  bool get hasIllustratedBasemap =>
      basemapUrl != null &&
      basemapUrl!.isNotEmpty &&
      basemapStatus == 'ready' &&
      bounds != null &&
      bounds!.isValid;

  factory EventMeta.fromJson(Map<String, dynamic> json) {
    final bounds = MapBounds.fromEventMeta(
      south: (json['bounds_south'] as num?)?.toDouble(),
      west: (json['bounds_west'] as num?)?.toDouble(),
      north: (json['bounds_north'] as num?)?.toDouble(),
      east: (json['bounds_east'] as num?)?.toDouble(),
    );
    final viewBounds = MapBounds.fromEventMeta(
      south: (json['view_bounds_south'] as num?)?.toDouble(),
      west: (json['view_bounds_west'] as num?)?.toDouble(),
      north: (json['view_bounds_north'] as num?)?.toDouble(),
      east: (json['view_bounds_east'] as num?)?.toDouble(),
    );
    return EventMeta(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      status: json['status'] as String? ?? 'draft',
      publicSlug: json['public_slug'] as String?,
      centerLat: (json['center_lat'] as num?)?.toDouble(),
      centerLng: (json['center_lng'] as num?)?.toDouble(),
      basemapUrl: json['basemap_url'] as String?,
      basemapStatus: json['basemap_status'] as String? ?? 'none',
      bounds: bounds.isValid ? bounds : null,
      viewBounds: viewBounds.isValid ? viewBounds : null,
      metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? const {}),
    );
  }

  EventMeta copyWith({
    String? id,
    String? name,
    String? description,
    String? status,
    String? publicSlug,
    double? centerLat,
    double? centerLng,
    String? basemapUrl,
    String? basemapStatus,
    MapBounds? bounds,
    MapBounds? viewBounds,
    Map<String, dynamic>? metadata,
  }) {
    return EventMeta(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      status: status ?? this.status,
      publicSlug: publicSlug ?? this.publicSlug,
      centerLat: centerLat ?? this.centerLat,
      centerLng: centerLng ?? this.centerLng,
      basemapUrl: basemapUrl ?? this.basemapUrl,
      basemapStatus: basemapStatus ?? this.basemapStatus,
      bounds: bounds ?? this.bounds,
      viewBounds: viewBounds ?? this.viewBounds,
      metadata: metadata ?? this.metadata,
    );
  }
}

class EventMapData {
  EventMapData({
    required this.event,
    List<MapVertex>? vertices,
    List<MapEdge>? edges,
    List<MapPoi>? pois,
  })  : vertices = vertices ?? [],
        edges = edges ?? [],
        pois = pois ?? [];

  final EventMeta event;
  final List<MapVertex> vertices;
  final List<MapEdge> edges;
  final List<MapPoi> pois;

  bool get hasPois => pois.isNotEmpty;

  AudioTourCatalog get audioTourCatalog => event.audioTourCatalog;

  AudioTourConfig get audioTour => event.audioTour;

  bool get hasAudioTour => audioTourCatalog.hasConfiguredTour;

  TreasureHuntCatalog get treasureHuntCatalog => event.treasureHuntCatalog;

  TreasureHuntConfig get treasureHunt => event.treasureHunt;

  bool get hasTreasureHunt => treasureHuntCatalog.hasConfiguredHunt;

  MapPoi? poiById(String id) {
    for (final poi in pois) {
      if (poi.id == id) return poi;
    }
    return null;
  }

  List<MapPoi> audioTourStopsFor(AudioTourConfig config) {
    final ids = config.poiStopIds;
    if (ids.isEmpty) {
      return pois.where((poi) => poi.hasAudio).toList()
        ..sort((a, b) => a.displayTitle.compareTo(b.displayTitle));
    }
    return [
      for (final id in ids)
        if (poiById(id) != null) poiById(id)!,
    ];
  }

  List<MapPoi> get audioTourStops => audioTourStopsFor(audioTour);

  EventMapData copyWith({
    EventMeta? event,
    List<MapVertex>? vertices,
    List<MapEdge>? edges,
    List<MapPoi>? pois,
  }) {
    return EventMapData(
      event: event ?? this.event,
      vertices: vertices ?? this.vertices,
      edges: edges ?? this.edges,
      pois: pois ?? this.pois,
    );
  }

  Map<String, dynamic> toSavePayload({double? centerLat, double? centerLng}) => {
        'vertices': vertices.map((v) => v.toJson()).toList(),
        'edges': edges.map((e) => e.toJson()).toList(),
        'pois': pois.map((p) => p.toJson()).toList(),
        if (centerLat != null) 'center_lat': centerLat,
        if (centerLng != null) 'center_lng': centerLng,
      };

  factory EventMapData.fromEditResponse(Map<String, dynamic> json) {
    final eventJson = Map<String, dynamic>.from(json['event'] as Map);
    return EventMapData(
      event: EventMeta.fromJson(eventJson),
      vertices: (json['vertices'] as List? ?? const [])
          .map((e) => MapVertex.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      edges: (json['edges'] as List? ?? const [])
          .map((e) => MapEdge.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      pois: (json['pois'] as List? ?? const [])
          .map((e) => MapPoi.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  factory EventMapData.fromPublishedGraph({
    required EventMeta event,
    required Map<String, dynamic> graph,
  }) {
    return EventMapData(
      event: event,
      vertices: (graph['vertices'] as List? ?? const [])
          .map((e) => MapVertex.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      edges: (graph['edges'] as List? ?? const [])
          .map((e) => MapEdge.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      pois: (graph['pois'] as List? ?? const [])
          .map((e) => MapPoi.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}
