import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/publish_status.dart';
import '../models/audio_tour.dart';
import '../models/event_map_data.dart';
import '../models/map_bounds.dart';
import '../models/map_edge.dart';
import '../models/map_poi.dart';
import '../models/poi_media.dart';
import '../models/map_vertex.dart';

class EventRepository {
  EventRepository({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<String> createOutdoorEvent({
    required String name,
    required String organizationId,
    String? description,
    double? centerLat,
    double? centerLng,
  }) async {
    final response = await _client.rpc(
      'create_outdoor_event',
      params: {
        'p_name': name,
        'p_organization_id': organizationId,
        'p_description': description,
        'p_center_lat': centerLat,
        'p_center_lng': centerLng,
      },
    );
    return response as String;
  }

  Future<EventMapData> loadForEdit({required String eventId}) async {
    final response = await _client.rpc(
      'get_event_for_edit',
      params: {'p_event_id': eventId},
    );
    return EventMapData.fromEditResponse(Map<String, dynamic>.from(response as Map));
  }

  Future<void> saveGraph({
    required String eventId,
    required List<MapVertex> vertices,
    required List<MapEdge> edges,
    required List<MapPoi> pois,
    double? centerLat,
    double? centerLng,
  }) async {
    await _client.rpc(
      'save_event_graph',
      params: {
        'p_event_id': eventId,
        'p_vertices': vertices.map((v) => v.toJson()).toList(),
        'p_edges': edges.map((e) => e.toJson()).toList(),
        'p_pois': pois.map((p) => p.toJson()).toList(),
        'p_center_lat': centerLat,
        'p_center_lng': centerLng,
      },
    );
  }

  Future<void> saveArea({
    required String eventId,
    required MapBounds bounds,
    MapBounds? viewBounds,
    double? centerLat,
    double? centerLng,
  }) async {
    await _client.rpc(
      'save_event_area',
      params: {
        'p_event_id': eventId,
        'p_south': bounds.south,
        'p_west': bounds.west,
        'p_north': bounds.north,
        'p_east': bounds.east,
        'p_center_lat': centerLat,
        'p_center_lng': centerLng,
        if (viewBounds != null) ...{
          'p_view_south': viewBounds.south,
          'p_view_west': viewBounds.west,
          'p_view_north': viewBounds.north,
          'p_view_east': viewBounds.east,
        },
      },
    );
  }

  Future<void> assignEventToOrganization({
    required String eventId,
    required String organizationId,
  }) async {
    await _client.rpc(
      'assign_event_to_organization',
      params: {
        'p_event_id': eventId,
        'p_organization_id': organizationId,
      },
    );
  }

  Future<void> deleteEvent({required String eventId}) async {
    await _client.rpc(
      'delete_event',
      params: {'p_event_id': eventId},
    );

    try {
      final files = await _client.storage.from('event-basemaps').list(path: eventId);
      if (files.isNotEmpty) {
        await _client.storage.from('event-basemaps').remove(
              files.map((f) => '$eventId/${f.name}').toList(),
            );
      }
    } on Object {
      // Storage cleanup is best-effort.
    }

    try {
      await _removeStorageFolder('poi-media', eventId);
    } on Object {
      // Storage cleanup is best-effort.
    }
  }

  Future<void> saveMetadata({
    required String eventId,
    required Map<String, dynamic> metadata,
  }) async {
    await _client.rpc(
      'save_event_metadata',
      params: {
        'p_event_id': eventId,
        'p_metadata': metadata,
      },
    );
  }

  Future<AudioTourWanderClip> uploadWanderAudio({
    required String eventId,
    required String wanderId,
    required Uint8List bytes,
    required String fileName,
    String? title,
  }) async {
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final storagePath = '$eventId/audio-tour/wander/$wanderId/$safeName';

    await _client.storage.from('poi-media').uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: _mimeForPoiMedia(fileName, PoiMediaKind.audio),
          ),
        );

    final url = _client.storage.from('poi-media').getPublicUrl(storagePath);
    return AudioTourWanderClip(
      id: wanderId,
      url: url,
      storagePath: storagePath,
      title: title,
    );
  }

  Future<void> deleteWanderAudio(AudioTourWanderClip clip) async {
    final path = clip.storagePath;
    if (path == null || path.isEmpty) return;
    try {
      await _client.storage.from('poi-media').remove([path]);
    } on Object {
      // Best-effort cleanup.
    }
  }

  Future<PoiMedia> uploadPoiMedia({
    required String eventId,
    required String poiId,
    required Uint8List bytes,
    required String fileName,
    required PoiMediaKind kind,
    String? caption,
  }) async {
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final storagePath = '$eventId/$poiId/${DateTime.now().millisecondsSinceEpoch}_$safeName';

    await _client.storage.from('poi-media').uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: _mimeForPoiMedia(fileName, kind),
          ),
        );

    final url = _client.storage.from('poi-media').getPublicUrl(storagePath);
    return PoiMedia(
      id: storagePath,
      url: url,
      kind: kind,
      storagePath: storagePath,
      caption: caption,
    );
  }

  Future<PoiMedia> uploadTreasureHuntCover({
    required String eventId,
    required String huntId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final storagePath =
        '$eventId/treasure-hunt/$huntId/cover_${DateTime.now().millisecondsSinceEpoch}_$safeName';

    await _client.storage.from('poi-media').uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: _mimeForPoiMedia(fileName, PoiMediaKind.image),
          ),
        );

    final url = _client.storage.from('poi-media').getPublicUrl(storagePath);
    return PoiMedia(
      id: storagePath,
      url: url,
      kind: PoiMediaKind.image,
      storagePath: storagePath,
    );
  }

  Future<void> deletePoiMedia(PoiMedia media) async {
    final path = media.storagePath;
    if (path == null || path.isEmpty) return;
    try {
      await _client.storage.from('poi-media').remove([path]);
    } on Object {
      // Best-effort cleanup.
    }
  }

  Future<void> _removeStorageFolder(String bucket, String folder) async {
    final entries = await _client.storage.from(bucket).list(path: folder);
    if (entries.isEmpty) return;

    final filePaths = <String>[];
    for (final entry in entries) {
      if (entry.id != null) {
        filePaths.add('$folder/${entry.name}');
        continue;
      }
      await _removeStorageFolder(bucket, '$folder/${entry.name}');
    }
    if (filePaths.isNotEmpty) {
      await _client.storage.from(bucket).remove(filePaths);
    }
  }

  String _mimeForPoiMedia(String fileName, PoiMediaKind kind) {
    final ext = fileName.split('.').last.toLowerCase();
    if (kind == PoiMediaKind.video) {
      return switch (ext) {
        'mov' => 'video/quicktime',
        'webm' => 'video/webm',
        _ => 'video/mp4',
      };
    }
    if (kind == PoiMediaKind.audio) {
      return switch (ext) {
        'mp3' => 'audio/mpeg',
        'wav' => 'audio/wav',
        'ogg' => 'audio/ogg',
        'aac' => 'audio/aac',
        'm4a' => 'audio/mp4',
        'webm' => 'audio/webm',
        _ => 'audio/mpeg',
      };
    }
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      _ => 'image/png',
    };
  }

  Future<String> uploadBasemap({
    required String eventId,
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    final path = '$eventId/basemap.$fileExtension';
    await _client.storage.from('event-basemaps').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: _mimeForExtension(fileExtension),
          ),
        );

    final publicUrl = _client.storage.from('event-basemaps').getPublicUrl(path);
    await _client.rpc(
      'set_event_basemap',
      params: {
        'p_event_id': eventId,
        'p_basemap_url': publicUrl,
        'p_status': 'ready',
      },
    );
    return publicUrl;
  }

  String _mimeForExtension(String ext) => switch (ext.toLowerCase()) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'webp' => 'image/webp',
        _ => 'image/png',
      };

  Future<PublishStatus> getPublishStatus({required String eventId}) async {
    final response = await _client.rpc(
      'get_publish_status',
      params: {'p_event_id': eventId},
    );
    return PublishStatus.fromJson(Map<String, dynamic>.from(response as Map));
  }

  Future<String> publishEvent({required String eventId}) async {
    return await _client.rpc(
      'publish_event',
      params: {'p_event_id': eventId},
    ) as String;
  }

  Future<EventMeta?> getPublishedMeta(String slug) async {
    final response = await _client.rpc(
      'get_event_meta_by_slug',
      params: {'p_slug': slug},
    );
    if (response == null) return null;

    final metaJson = Map<String, dynamic>.from(response as Map);
    await _mergePublishedMetadataFromTable(slug, metaJson);
    return EventMeta.fromJson(metaJson);
  }

  /// Older Supabase deployments omit [metadata] from [get_event_meta_by_slug].
  Future<void> _mergePublishedMetadataFromTable(
    String slug,
    Map<String, dynamic> metaJson,
  ) async {
    final existing = metaJson['metadata'];
    if (existing is Map && existing.isNotEmpty) return;

    final row = await _client
        .from('events')
        .select('metadata, status')
        .eq('public_slug', slug)
        .eq('status', 'published')
        .maybeSingle();
    if (row == null) return;

    final metadata = row['metadata'];
    if (metadata is Map && metadata.isNotEmpty) {
      metaJson['metadata'] = metadata;
    }
    metaJson['status'] ??= row['status'];
  }

  Future<EventMapData?> loadPublishedBySlug(String slug) async {
    final normalizedSlug = slug.trim().toLowerCase();
    if (normalizedSlug.isEmpty) return null;

    final data = await _loadPublishedBySlugOnce(normalizedSlug);
    if (data == null) return null;
    if (data.hasAudioTour || data.hasTreasureHunt) return data;

    // Published again under slug-2 when an older publish kept the canonical slug.
    return _loadPublishedBySlugOnce('$normalizedSlug-2') ?? data;
  }

  Future<EventMapData?> _loadPublishedBySlugOnce(String slug) async {
    final meta = await getPublishedMeta(slug);
    if (meta == null) return null;

    final graphResponse = await _client.rpc(
      'get_event_graph_by_slug',
      params: {'p_slug': slug},
    );
    if (graphResponse == null) return null;

    final graph = graphResponse is Map
        ? Map<String, dynamic>.from(graphResponse)
        : Map<String, dynamic>.from(graphResponse as Map);

    return EventMapData.fromPublishedGraph(
      event: meta.copyWith(status: 'published', publicSlug: slug),
      graph: graph,
    );
  }
}
